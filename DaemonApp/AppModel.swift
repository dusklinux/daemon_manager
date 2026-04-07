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
        if let domain, let plistPath {
            return "\(domain)|\(plistPath)"
        }
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
    
    @Published private(set) var rawConfigContent: String? = nil
    @Published private(set) var targetStates: [String: Bool] = [:]
    
    @Published var applyProgressText: String? = nil
    @Published var isApplyingConfig: Bool = false
    @Published var isApplyFinished: Bool = false // NEW: Prevents log from auto-closing
    @Published var liveLog: String = ""
    private var currentPid: pid_t? = nil

    private var disabledServices: Set<DisabledServiceKey>?
    private var importedLabels: [String] = []
    private var timer: Timer?

    private let mobileDomain: String
    private let rootlessShellPath = "/var/jb/bin/sh"
    private let daemonManagerPath: String

    init() {
        if let pw = getpwnam("mobile") {
            mobileDomain = "user/\(pw.pointee.pw_uid)"
        } else {
            mobileDomain = "user/501"
        }

        let externalScript = "/var/jb/basebin/daemonmanager"
        if FileManager.default.fileExists(atPath: externalScript) {
            daemonManagerPath = externalScript
        } else if let bundledScript = Bundle.main.path(forResource: "daemonmanager", ofType: nil) {
            daemonManagerPath = bundledScript
        } else {
            daemonManagerPath = externalScript
        }

        validateEnvironment()
        startRAMTimer()
        fetchAllDaemons()
        refreshState()
        
        let externalConfig = "/var/jb/basebin/daemon.cfg"
        if FileManager.default.fileExists(atPath: externalConfig) {
            importConfig(url: URL(fileURLWithPath: externalConfig))
        } else if let bundledConfig = Bundle.main.url(forResource: "daemon", withExtension: "cfg") {
            importConfig(url: bundledConfig)
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refreshAll() {
        validateEnvironment()
        fetchAllDaemons()
        refreshState()
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

        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        let freeBytes = Double(vmStats.free_count + vmStats.speculative_count) * Double(pageSize)
        let usedBytes = max(0, totalBytes - freeBytes)

        let totalGB = totalBytes / 1_073_741_824.0
        let usedGB = usedBytes / 1_073_741_824.0

        DispatchQueue.main.async {
            self.ramUsageText = String(format: "System RAM: %.2f GB Used / %.2f GB Total", usedGB, totalGB)
        }
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

        DispatchQueue.main.async { self.isProcessing.insert(service.id) }

        DispatchQueue.global(qos: .userInitiated).async {
            let action = enable ? "enable" : "disable"
            let result = self.posixRunSync(executable: self.rootlessShellPath, args: [self.daemonManagerPath, action, service.label])

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

    func importConfig(url: URL) {
        var fileContent: String? = nil
        if let data = FileManager.default.contents(atPath: url.path) {
            fileContent = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
        }
        if fileContent == nil {
            if let data = try? Data(contentsOf: url) {
                fileContent = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
            }
        }

        guard let content = fileContent else {
            presentError("Permission Denied: Cannot read file.")
            return
        }

        let parsed = parseImportedConfig(from: content)
        DispatchQueue.main.async {
            self.importedLabels = parsed.labels
            self.targetStates = parsed.targets
            self.rawConfigContent = content
            self.resolveImportedConfig()
        }
    }
    
    // FIX: Forcefully kill the process with SIGKILL (9) instead of SIGTERM (15).
    // Bash cannot trap or ignore SIGKILL. The script will die instantly.
    func cancelApply() {
        if let pid = currentPid {
            kill(pid, SIGKILL)
            DispatchQueue.main.async {
                self.liveLog += "\n\n[!] USER CANCELLED: Sent SIGKILL to forcefully terminate process."
            }
        }
    }
    
    // NEW: Dismisses the log view and resets the state so the user can try again
    func dismissLog() {
        DispatchQueue.main.async {
            self.isApplyingConfig = false
            self.isApplyFinished = false
            self.liveLog = ""
            self.applyProgressText = nil
        }
    }
    
    func applyImportedConfig() {
        guard let content = rawConfigContent else { return }
        guard daemonManagerAvailable else { return }

        DispatchQueue.main.async {
            self.isApplyingConfig = true
            self.isApplyFinished = false
            self.liveLog = "--- STARTING DAEMONMANAGER ---\n"
            self.applyProgressText = "Preparing Config..."
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let tempURL = URL(fileURLWithPath: "/var/mobile/Library/Preferences/temp_daemon.cfg")
            do {
                try content.write(to: tempURL, atomically: true, encoding: .utf8)
            } catch {
                DispatchQueue.main.async { 
                    self.liveLog += "\n[Error] Failed to write temporary config: \(error.localizedDescription)"
                    self.isApplyFinished = true
                }
                return
            }

            self.posixRunAsync(
                executable: self.rootlessShellPath,
                args: [self.daemonManagerPath, "apply-file", tempURL.path]
            ) { liveText in
                DispatchQueue.main.async {
                    self.liveLog += liveText
                    if let range = liveText.range(of: #"\[[0-9]+/[0-9]+\]"#, options: .regularExpression) {
                        self.applyProgressText = "Applying \(String(liveText[range]))"
                    }
                }
            } onCompletion: { exitCode in
                try? FileManager.default.removeItem(at: tempURL)
                
                // FIX: Do not auto-close the log. Set isApplyFinished = true and wait for user.
                DispatchQueue.main.async {
                    self.liveLog += "\n--- PROCESS EXITED WITH CODE \(exitCode) ---\n"
                    if exitCode != 0 && exitCode != 9 { // 9 is SIGKILL (User Cancelled)
                        self.errorMessage = "Process failed with code \(exitCode). Check the log for details."
                    }
                    self.applyProgressText = exitCode == 0 ? "Success!" : (exitCode == 9 ? "Cancelled" : "Failed")
                    self.isApplyFinished = true
                    self.refreshState()
                }
            }
        }
    }

    private func validateEnvironment() {
        let available = FileManager.default.fileExists(atPath: daemonManagerPath)
        DispatchQueue.main.async {
            self.daemonManagerAvailable = available
            self.environmentWarning = available ? nil : "Missing script dependency at: \(self.daemonManagerPath)"
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
                if seen.insert(unresolved.id).inserted {
                    resolved.append(unresolved)
                }
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

        var pid: pid_t = 0
        let spawnStatus = posix_spawn(&pid, executable, &fileActions, nil, argv, env)
        
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
            } else if bytesRead == 0 {
                source.cancel()
            }
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
        
        posixRunAsync(executable: executable, args: args) { text in
            fullOutput += text
        } onCompletion: { code in
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
