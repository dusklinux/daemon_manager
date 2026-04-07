import Foundation
import Combine
import Darwin

struct LaunchdService: Identifiable, Hashable {
    enum Kind: String {
        case agent = "LaunchAgent"
        case daemon = "LaunchDaemon"
        case unresolved = "Unresolved"
    }

    let label: String
    let plistPath: String?
    let domain: String?
    let kind: Kind

    var id: String {
        if let domain, let plistPath { return "\(domain)|\(plistPath)" }
        return "unresolved|\(label)"
    }

    var metadataText: String {
        switch kind {
        case .unresolved: return "Unresolved import"
        default: return "\(kind.rawValue) • \(domain ?? "unknown")"
        }
    }

    static func unresolved(label: String) -> LaunchdService {
        LaunchdService(label: label, plistPath: nil, domain: nil, kind: .unresolved)
    }
}

private struct DisabledServiceKey: Hashable {
    let domain: String
    let label: String
}

final class AppModel: ObservableObject {
    @Published private(set) var configDaemons: [LaunchdService] = []
    @Published private(set) var allDaemons: [LaunchdService] = []
    @Published private(set) var isProcessing: Set<String> = []
    @Published private(set) var isScanningDaemons = false
    @Published private(set) var isRefreshingState = false
    @Published private(set) var daemonManagerAvailable = false
    @Published private(set) var environmentWarning: String?

    @Published var ramUsageText = "Calculating RAM..."
    @Published var isDarkTheme = true
    @Published var errorMessage: String?
    
    @Published var rootPassword = UserDefaults.standard.string(forKey: "rootPassword") ?? "alpine" {
        didSet { UserDefaults.standard.set(rootPassword, forKey: "rootPassword") }
    }
    
    @Published private(set) var rawConfigContent: String? = nil
    @Published private(set) var targetStates: [String: Bool] = [:]
    
    @Published var applyProgressText: String? = nil
    @Published var isApplyingConfig: Bool = false
    @Published var showLogConsole: Bool = false
    @Published var liveLog: String = ""
    
    private var currentPid: pid_t? = nil
    private var disabledServices: Set<DisabledServiceKey>?
    private var importedLabels: [String] = []
    private var timer: Timer?

    private let mobileDomain: String
    private let rootlessShellPath = "/var/jb/bin/sh"
    
    // Persistent paths for the script and config
    @Published var daemonManagerPath: String = UserDefaults.standard.string(forKey: "customScriptPath") ?? "/var/jb/basebin/daemonmanager" {
        didSet { UserDefaults.standard.set(daemonManagerPath, forKey: "customScriptPath") }
    }
    @Published var lastImportedConfigPath: String? = UserDefaults.standard.string(forKey: "customConfigPath") {
        didSet { UserDefaults.standard.set(lastImportedConfigPath, forKey: "customConfigPath") }
    }

    init() {
        if let pw = getpwnam("mobile") {
            mobileDomain = "user/\(pw.pointee.pw_uid)"
        } else {
            mobileDomain = "user/501"
        }

        validateEnvironment()
        startRAMTimer()
        fetchAllDaemons()
        refreshState()
        loadInitialConfig()
    }

    deinit {
        timer?.invalidate()
    }

    func refreshAll() {
        validateEnvironment()
        fetchAllDaemons()
        refreshState()
        
        if let path = lastImportedConfigPath, let content = try? String(contentsOfFile: path, encoding: .utf8) {
            processConfigContent(content)
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func isDisabled(_ service: LaunchdService) -> Bool? {
        guard let domain = service.domain, let disabledServices else { return nil }
        return disabledServices.contains(DisabledServiceKey(domain: domain, label: service.label))
    }

    func canToggle(_ service: LaunchdService) -> Bool {
        daemonManagerAvailable && service.domain != nil && disabledServices != nil
    }

    func toggleUnavailableReason(_ service: LaunchdService) -> String? {
        if !daemonManagerAvailable { return "Missing script dependency at: \(daemonManagerPath)" }
        if service.domain == nil { return "This imported label could not be resolved." }
        if disabledServices == nil { return "Current launchd disabled-state has not finished loading." }
        return nil
    }

    func startRAMTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateRAMUsage()
        }
        updateRAMUsage()
    }

    private func updateRAMUsage() {
        let hostPort = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, hostPort) }
        var pageSize: vm_size_t = 0
        guard host_page_size(hostPort, &pageSize) == KERN_SUCCESS else { return }
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let status = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return }
        let freeBytes = Double(vmStats.free_count + vmStats.speculative_count) * Double(pageSize)
        let freeMB = freeBytes / 1_048_576.0
        DispatchQueue.main.async { self.ramUsageText = String(format: "Free RAM: %.0f MB", freeMB) }
    }

    func refreshState(completion: (() -> Void)? = nil) {
        DispatchQueue.main.async { self.isRefreshingState = true }
        DispatchQueue.global(qos: .userInitiated).async {
            let domains = ["system", self.mobileDomain]
            var merged = Set<DisabledServiceKey>()
            var failures: [String] = []
            for domain in domains {
                let result = self.posixRunSync(executable: self.rootlessShellPath, args: ["-c", "launchctl print-disabled \(domain)"])
                guard result.exitCode == 0 else {
                    failures.append("launchctl print-disabled \(domain) failed with exit code \(result.exitCode).")
                    continue
                }
                merged.formUnion(self.parseDisabledServices(from: result.output, domain: domain))
            }
            DispatchQueue.main.async {
                if failures.isEmpty { self.disabledServices = merged }
                self.isRefreshingState = false
                if !failures.isEmpty { self.errorMessage = failures.joined(separator: "\n\n") }
                completion?()
            }
        }
    }

    func fetchAllDaemons() {
        DispatchQueue.main.async { self.isScanningDaemons = true }
        DispatchQueue.global(qos: .userInitiated).async {
            let locations: [(path: String, kind: LaunchdService.Kind, domain: String)] = [
                ("/System/Library/LaunchAgents", .agent, self.mobileDomain),
                ("/System/Library/LaunchDaemons", .daemon, "system"),
                ("/var/jb/Library/LaunchAgents", .agent, self.mobileDomain),
                ("/var/jb/Library/LaunchDaemons", .daemon, "system")
            ]
            var servicesByID: [String: LaunchdService] = [:]
            for location in locations {
                let directoryURL = URL(fileURLWithPath: location.path, isDirectory: true)
                guard let fileURLs = try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
                for fileURL in fileURLs where fileURL.pathExtension == "plist" {
                    guard let service = self.loadService(from: fileURL, kind: location.kind, domain: location.domain) else { continue }
                    servicesByID[service.id] = service
                }
            }
            let services = servicesByID.values.sorted(by: Self.sortServices)
            DispatchQueue.main.async {
                self.allDaemons = services
                self.isScanningDaemons = false
                self.resolveImportedConfig()
            }
        }
    }

    func toggleDaemon(_ service: LaunchdService, enable: Bool) {
        guard canToggle(service) else { return }
        let pwd = self.rootPassword
        DispatchQueue.main.async { self.isProcessing.insert(service.id) }
        DispatchQueue.global(qos: .userInitiated).async {
            let action = enable ? "enable" : "disable"
            let elevated = self.buildElevatedCommand(action: action, args: [service.label], pwd: pwd)
            let result = self.posixRunSync(executable: elevated.executable, args: elevated.arguments)
            guard result.exitCode == 0 else {
                DispatchQueue.main.async {
                    self.isProcessing.remove(service.id)
                    self.errorMessage = "Failed to \(action) \(service.label) (exit code \(result.exitCode)).\n\(result.output)"
                }
                return
            }
            self.refreshState { self.isProcessing.remove(service.id) }
        }
    }

    private func loadInitialConfig() {
        if let path = lastImportedConfigPath, FileManager.default.fileExists(atPath: path) {
            importFile(url: URL(fileURLWithPath: path))
        } else {
            let defaultPath = "/var/jb/basebin/daemon.cfg"
            if FileManager.default.fileExists(atPath: defaultPath) {
                importFile(url: URL(fileURLWithPath: defaultPath))
            }
        }
    }

    func importFile(url: URL) {
        let fileName = url.lastPathComponent
        
        // Ensure we can read the file (security scoped for picker)
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        
        guard let data = try? Data(contentsOf: url) else {
            presentError("Permission Denied: Cannot read \(fileName).")
            return
        }

        if fileName == "daemonmanager" {
            self.daemonManagerPath = url.path
            validateEnvironment()
            liveLog += "\n[+] Detected and set new script path: \(url.path)"
        } else {
            // Assume it is a config file
            self.lastImportedConfigPath = url.path
            let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
            processConfigContent(content)
        }
    }
    
    private func processConfigContent(_ content: String) {
        let parsed = parseImportedConfig(from: content)
        DispatchQueue.main.async {
            self.importedLabels = parsed.labels
            self.targetStates = parsed.targets
            self.rawConfigContent = content
            self.resolveImportedConfig()
        }
    }
    
    private func executeBatchOperation(action: String, args: [String], progressTextPrefix: String, onFinish: (() -> Void)? = nil) {
        guard daemonManagerAvailable else { return }
        let pwd = self.rootPassword
        
        DispatchQueue.main.async {
            self.isApplyingConfig = true
            self.showLogConsole = true
            self.liveLog = "--- STARTING DAEMONMANAGER (\(action.uppercased())) ---\n"
            self.applyProgressText = "\(progressTextPrefix)..."
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let elevated = self.buildElevatedCommand(action: action, args: args, pwd: pwd)
            self.posixRunAsync(
                executable: elevated.executable,
                args: elevated.arguments
            ) { liveText in
                DispatchQueue.main.async {
                    self.liveLog += liveText
                    if let range = liveText.range(of: #"\[[0-9]+/[0-9]+\]"#, options: .regularExpression) {
                        self.applyProgressText = "\(progressTextPrefix) \(String(liveText[range]))"
                    }
                }
            } onCompletion: { exitCode in
                onFinish?()
                DispatchQueue.main.async {
                    self.liveLog += "\n--- PROCESS EXITED WITH CODE \(exitCode) ---\n"
                    self.applyProgressText = nil
                    self.isApplyingConfig = false
                    if exitCode != 0 && exitCode != 15 && exitCode != 143 && exitCode != 9 {
                        self.errorMessage = "Process failed with code \(exitCode). Check the log for details."
                    }
                    self.refreshState()
                }
            }
        }
    }
    
    func applyImportedConfig() {
        guard let path = lastImportedConfigPath else { return }
        executeBatchOperation(action: "apply-file", args: [path], progressTextPrefix: "Applying")
    }

    func resetConfig() {
        executeBatchOperation(action: "reset", args: [], progressTextPrefix: "Resetting")
    }

    private func buildElevatedCommand(action: String, args: [String], pwd: String, isRaw: Bool = false) -> (executable: String, arguments: [String]) {
        let sudoPath = "/var/jb/usr/bin/sudo"
        let safePwd = pwd.replacingOccurrences(of: "\"", with: "\\\"")
        let safeArgs = args.map { "\"\($0)\"" }.joined(separator: " ")
        
        let innerCmd: String
        if isRaw {
            innerCmd = action
        } else {
            // Force execution via shell to bypass +x issues on some filesystems
            innerCmd = "\"\(self.rootlessShellPath)\" \"\(self.daemonManagerPath)\" \(action) \(safeArgs)"
        }
        
        if FileManager.default.fileExists(atPath: sudoPath) {
            let shellCmd = "echo \"\(safePwd)\" | \"\(sudoPath)\" -S -p \"\" \(self.rootlessShellPath) -c '\(innerCmd)'"
            return (self.rootlessShellPath, ["-c", shellCmd])
        } else {
            let pythonExe = pythonPath
            let pythonScript = """
            import os, sys, pty, select, signal
            pw = sys.argv[1]
            cmd = sys.argv[2:]
            pid, fd = pty.fork()
            if pid == 0:
                os.execv(cmd[0], cmd)
            else:
                buffer = b""
                while True:
                    r, w, e = select.select([fd], [], [], 2.0)
                    if not r: break
                    try:
                        chunk = os.read(fd, 1024)
                        if not chunk: break
                        buffer += chunk
                        if b"assword" in buffer or b"Password:" in buffer:
                            break
                    except OSError:
                        break
                os.write(fd, (pw + "\\n").encode())
                try:
                    while True:
                        data = os.read(fd, 1024)
                        if not data: break
                        sys.stdout.buffer.write(data)
                        sys.stdout.flush()
                except OSError:
                    pass
                _, status = os.waitpid(pid, 0)
                sys.exit(os.waitstatus_to_exitcode(status) if hasattr(os, 'waitstatus_to_exitcode') else (status >> 8))
            """
            let suExe = "/var/jb/usr/bin/su"
            let suArgs = ["-c", pythonScript, safePwd, suExe, "-", "root", "-c", innerCmd]
            return (pythonExe, suArgs)
        }
    }
        
    private var pythonPath: String {
        let paths = ["/var/jb/usr/bin/python3", "/var/jb/usr/local/bin/python3", "/usr/bin/python3"]
        for p in paths { if FileManager.default.fileExists(atPath: p) { return p } }
        return "/var/jb/usr/bin/python3"
    }

    private func validateEnvironment() {
        let available = FileManager.default.fileExists(atPath: daemonManagerPath)
        DispatchQueue.main.async {
            self.daemonManagerAvailable = available
            self.environmentWarning = available ? nil : "Missing script at: \(self.daemonManagerPath)"
        }
    }

    private func resolveImportedConfig() {
        guard !importedLabels.isEmpty else { configDaemons = []; return }
        let grouped = Dictionary(grouping: allDaemons, by: \.label)
        var resolved: [LaunchdService] = []
        var seen = Set<String>()
        for label in importedLabels {
            if let matches = grouped[label], !matches.isEmpty {
                for service in matches.sorted(by: Self.sortServices) where seen.insert(service.id).inserted {
                    resolved.append(service)
                }
            } else {
                let unresolved = LaunchdService.unresolved(label: label)
                if seen.insert(unresolved.id).inserted { resolved.append(unresolved) }
            }
        }
        configDaemons = resolved
    }

    private func parseImportedConfig(from content: String) -> (labels: [String], targets: [String: Bool]) {
        var labels: [String] = []
        var targets: [String: Bool] = [:]
        var seen = Set<String>()
        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard let firstToken = fields.first else { continue }
            let label = String(firstToken)
            if seen.insert(label).inserted {
                labels.append(label)
                if fields.count >= 2 {
                    let mode = String(fields[1]).lowercased()
                    if ["yes", "off", "disable", "disabled"].contains(mode) { targets[label] = false }
                    else if ["no", "on", "enable", "enabled"].contains(mode) { targets[label] = true }
                }
            }
        }
        return (labels, targets)
    }

    private func parseDisabledServices(from output: String, domain: String) -> Set<DisabledServiceKey> {
        var disabled = Set<DisabledServiceKey>()
        let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;"))
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: trimSet)
            let parts = line.components(separatedBy: "\"")
            guard parts.count >= 3, let arrowRange = line.range(of: "=>") else { continue }
            let label = parts[1]
            let rawValue = line[arrowRange.upperBound...].trimmingCharacters(in: trimSet).lowercased()
            if rawValue == "true" || rawValue == "disabled" {
                disabled.insert(DisabledServiceKey(domain: domain, label: label))
            }
        }
        return disabled
    }

    private func loadService(from plistURL: URL, kind: LaunchdService.Kind, domain: String) -> LaunchdService? {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        let fallbackLabel = plistURL.deletingPathExtension().lastPathComponent
        let trimmedLabel = (plist["Label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = (trimmedLabel?.isEmpty == false) ? trimmedLabel! : fallbackLabel
        return LaunchdService(label: label, plistPath: plistURL.path, domain: domain, kind: kind)
    }

    private static func sortServices(_ lhs: LaunchdService, _ rhs: LaunchdService) -> Bool {
        let lhsLabel = lhs.label.localizedLowercase
        let rhsLabel = rhs.label.localizedLowercase
        if lhsLabel != rhsLabel { return lhsLabel < rhsLabel }
        let lhsDomain = lhs.domain ?? ""
        let rhsDomain = rhs.domain ?? ""
        if lhsDomain != rhsDomain { return lhsDomain < rhsDomain }
        return (lhs.plistPath ?? "") < (rhs.plistPath ?? "")
    }

    private func presentError(_ message: String) {
        DispatchQueue.main.async { self.errorMessage = message }
    }
    
    private func posixRunAsync(executable: String, args: [String], onOutput: @escaping (String) -> Void, onCompletion: @escaping (Int32) -> Void) {
        let argv: [UnsafeMutablePointer<CChar>?] = ([executable] + args).map { strdup($0) } + [nil]
        defer { for case let pointer? in argv { free(pointer) } }
        var envDict = ProcessInfo.processInfo.environment
        envDict["PATH"] = "/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (envDict["PATH"] ?? "")
        envDict["LC_ALL"] = "C"
        let envStrings = envDict.map { "\($0.key)=\($0.value)" }
        let env: [UnsafeMutablePointer<CChar>?] = envStrings.map { strdup($0) } + [nil]
        defer { for case let pointer? in env { free(pointer) } }
        var fileActions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        var outPipe: [Int32] = [-1, -1]
        pipe(&outPipe)
        posix_spawn_file_actions_adddup2(&fileActions, outPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, outPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, outPipe[0])
        posix_spawn_file_actions_addclose(&fileActions, outPipe[1])
        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        var flags: Int16 = 0
        posix_spawnattr_getflags(&attr, &flags)
        posix_spawnattr_setflags(&attr, flags | Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attr, 0)
        var pid: pid_t = 0
        let spawnStatus = posix_spawn(&pid, executable, &fileActions, &attr, argv, env)
        close(outPipe[1]) 
        if spawnStatus != 0 {
            close(outPipe[0])
            onCompletion(-1)
            return
        }
        self.currentPid = pid
        let fd = outPipe[0]
        fcntl(fd, F_SETFL, O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.global())
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead > 0 {
                let text = String(decoding: buffer[..<bytesRead], as: UTF8.self)
                onOutput(text)
            } else if bytesRead == 0 { source.cancel() }
        }
        source.setCancelHandler {
            close(fd)
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            let finalCode = self.decodeWaitStatus(status)
            DispatchQueue.main.async {
                self.currentPid = nil
                onCompletion(finalCode)
            }
        }
        source.resume()
    }

    private func posixRunSync(executable: String, args: [String]) -> (exitCode: Int32, output: String) {
        let semaphore = DispatchSemaphore(value: 0)
        var fullOutput = ""
        var finalCode: Int32 = -1
        posixRunAsync(executable: executable, args: args) { text in fullOutput += text } onCompletion: { code in
            finalCode = code
            semaphore.signal()
        }
        semaphore.wait()
        return (finalCode, fullOutput)
    }

    private func decodeWaitStatus(_ status: Int32) -> Int32 {
        let signal = status & 0x7F
        if signal == 0 { return (status >> 8) & 0xFF }
        return 128 + signal
    }
}
