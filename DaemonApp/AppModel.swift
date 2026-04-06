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
        case .unresolved:
            return "Unresolved import"
        default:
            return "\(kind.rawValue) • \(domain ?? "unknown")"
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

private struct ProcessResult {
    let exitCode: Int32
    let output: String
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
    
    // NEW: Tracks the intended state from the imported config (true = Should be ON)
    @Published private(set) var targetStates: [String: Bool] = [:]

    private var disabledServices: Set<DisabledServiceKey>?
    private var importedLabels: [String] = []
    private var timer: Timer?

    private let mobileDomain: String
    private let daemonManagerPath = "/var/jb/basebin/daemonmanager"
    private let rootlessShellPath = "/var/jb/bin/sh"

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
        guard let domain = service.domain, let disabledServices else {
            return nil
        }

        return disabledServices.contains(DisabledServiceKey(domain: domain, label: service.label))
    }

    func canToggle(_ service: LaunchdService) -> Bool {
        daemonManagerAvailable &&
        service.domain != nil &&
        disabledServices != nil
    }

    func toggleUnavailableReason(_ service: LaunchdService) -> String? {
        if !daemonManagerAvailable {
            return "Missing executable dependency: \(daemonManagerPath)"
        }

        if service.domain == nil {
            return "This imported label could not be resolved to a scanned launchd plist."
        }

        if disabledServices == nil {
            return "Current launchd disabled-state has not finished loading yet."
        }

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
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )

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
        DispatchQueue.main.async {
            self.isRefreshingState = true
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let domains = ["system", self.mobileDomain]
            var merged = Set<DisabledServiceKey>()
            var failures: [String] = []

            for domain in domains {
                let result = self.posixRun(executable: self.rootlessShellPath, args: ["-c", "launchctl print-disabled \(domain)"])

                guard result.exitCode == 0 else {
                    let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    let message = detail.isEmpty
                        ? "launchctl print-disabled \(domain) failed with exit code \(result.exitCode)."
                        : "launchctl print-disabled \(domain) failed:\n\(detail)"
                    failures.append(message)
                    continue
                }

                merged.formUnion(self.parseDisabledServices(from: result.output, domain: domain))
            }

            DispatchQueue.main.async {
                if failures.isEmpty {
                    self.disabledServices = merged
                }

                self.isRefreshingState = false

                if !failures.isEmpty {
                    self.errorMessage = failures.joined(separator: "\n\n")
                }

                completion?()
            }
        }
    }

    func fetchAllDaemons() {
        DispatchQueue.main.async {
            self.isScanningDaemons = true
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            let locations: [(path: String, kind: LaunchdService.Kind, domain: String)] = [
                ("/System/Library/LaunchAgents", .agent, self.mobileDomain),
                ("/System/Library/LaunchDaemons", .daemon, "system"),
                ("/var/jb/Library/LaunchAgents", .agent, self.mobileDomain),
                ("/var/jb/Library/LaunchDaemons", .daemon, "system")
            ]

            var servicesByID: [String: LaunchdService] = [:]

            for location in locations {
                let directoryURL = URL(fileURLWithPath: location.path, isDirectory: true)

                guard let fileURLs = try? fileManager.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else {
                    continue
                }

                for fileURL in fileURLs where fileURL.pathExtension == "plist" {
                    guard let service = self.loadService(from: fileURL, kind: location.kind, domain: location.domain) else {
                        continue
                    }
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
        guard canToggle(service) else {
            if let reason = toggleUnavailableReason(service) {
                presentError(reason)
            }
            return
        }

        DispatchQueue.main.async {
            self.isProcessing.insert(service.id)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let action = enable ? "enable" : "disable"
            
            let result = self.posixRun(
                executable: self.rootlessShellPath,
                args: [self.daemonManagerPath, action, service.label]
            )

            guard result.exitCode == 0 else {
                let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                let message = detail.isEmpty
                    ? "Failed to \(action) \(service.label) (exit code \(result.exitCode))."
                    : "Failed to \(action) \(service.label):\n\(detail)"

                DispatchQueue.main.async {
                    self.isProcessing.remove(service.id)
                    self.errorMessage = message
                }
                return
            }

            self.refreshState {
                self.isProcessing.remove(service.id)
            }
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
            presentError("Permission Denied: TrollStore apps cannot read sandboxed iCloud files. Please move 'daemon.cfg' directly to your 'On My iPhone > Downloads' folder and try again.")
            return
        }

        // NEW: We now parse both the labels AND their intended state.
        let parsed = parseImportedConfig(from: content)

        DispatchQueue.main.async {
            self.importedLabels = parsed.labels
            self.targetStates = parsed.targets
            self.rawConfigContent = content
            self.resolveImportedConfig()
        }
    }
    
    func applyImportedConfig() {
        guard let content = rawConfigContent else { return }
        guard daemonManagerAvailable else {
            presentError("Missing executable dependency: \(daemonManagerPath)")
            return
        }

        DispatchQueue.main.async {
            self.isRefreshingState = true
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_daemon.cfg")
            do {
                try content.write(to: tempURL, atomically: true, encoding: .utf8)
            } catch {
                self.presentError("Failed to write temporary config file: \(error.localizedDescription)")
                DispatchQueue.main.async { self.isRefreshingState = false }
                return
            }

            let result = self.posixRun(
                executable: self.rootlessShellPath,
                args: [self.daemonManagerPath, "apply-file", tempURL.path]
            )

            try? FileManager.default.removeItem(at: tempURL)

            guard result.exitCode == 0 else {
                let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                let message = detail.isEmpty
                    ? "Failed to apply config batch (exit code \(result.exitCode))."
                    : "Failed to apply config:\n\(detail)"

                DispatchQueue.main.async {
                    self.errorMessage = message
                    self.isRefreshingState = false
                }
                return
            }

            self.refreshState()
        }
    }

    private func validateEnvironment() {
        let fileManager = FileManager.default
        let available =
            fileManager.fileExists(atPath: daemonManagerPath) &&
            fileManager.isExecutableFile(atPath: daemonManagerPath)

        DispatchQueue.main.async {
            self.daemonManagerAvailable = available
            self.environmentWarning = available ? nil : "Missing executable dependency: \(self.daemonManagerPath)"
        }
    }

    private func resolveImportedConfig() {
        guard !importedLabels.isEmpty else {
            configDaemons = []
            return
        }

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

    // NEW: Extracts both the label and the requested yes/no state from daemon.cfg
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
                
                // Decode intended mode (yes/off/disable -> target is disabled(false))
                // (no/on/enable -> target is enabled(true))
                if fields.count >= 2 {
                    let mode = String(fields[1]).lowercased()
                    if ["yes", "off", "disable", "disabled"].contains(mode) {
                        targets[label] = false
                    } else if ["no", "on", "enable", "enabled"].contains(mode) {
                        targets[label] = true
                    }
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

            guard parts.count >= 3 else { continue }
            guard let arrowRange = line.range(of: "=>") else { continue }

            let label = parts[1]
            let rawValue = line[arrowRange.upperBound...]
                .trimmingCharacters(in: trimSet)
                .lowercased()

            if rawValue == "true" || rawValue == "disabled" {
                disabled.insert(DisabledServiceKey(domain: domain, label: label))
            }
        }

        return disabled
    }

    private func loadService(from plistURL: URL, kind: LaunchdService.Kind, domain: String) -> LaunchdService? {
        guard let data = try? Data(contentsOf: plistURL) else {
            return nil
        }

        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }

        let fallbackLabel = plistURL.deletingPathExtension().lastPathComponent
        let trimmedLabel = (plist["Label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = (trimmedLabel?.isEmpty == false) ? trimmedLabel! : fallbackLabel

        return LaunchdService(
            label: label,
            plistPath: plistURL.path,
            domain: domain,
            kind: kind
        )
    }

    private static func sortServices(_ lhs: LaunchdService, _ rhs: LaunchdService) -> Bool {
        let lhsLabel = lhs.label.localizedLowercase
        let rhsLabel = rhs.label.localizedLowercase

        if lhsLabel != rhsLabel {
            return lhsLabel < rhsLabel
        }

        let lhsDomain = lhs.domain ?? ""
        let rhsDomain = rhs.domain ?? ""

        if lhsDomain != rhsDomain {
            return lhsDomain < rhsDomain
        }

        return (lhs.plistPath ?? "") < (rhs.plistPath ?? "")
    }

    private func presentError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
        }
    }

    private func posixRun(executable: String, args: [String]) -> ProcessResult {
        let argv: [UnsafeMutablePointer<CChar>?] = ([executable] + args).map { $0.withCString(strdup) } + [nil]
        defer {
            for case let pointer? in argv {
                free(pointer)
            }
        }

        let environment = [
            "PATH=/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "LC_ALL=C"
        ]
        let env: [UnsafeMutablePointer<CChar>?] = environment.map { $0.withCString(strdup) } + [nil]
        defer {
            for case let pointer? in env {
                free(pointer)
            }
        }

        var fileActions: posix_spawn_file_actions_t? = nil
        let initStatus = posix_spawn_file_actions_init(&fileActions)
        guard initStatus == 0 else {
            return ProcessResult(
                exitCode: -1,
                output: "posix_spawn_file_actions_init failed: \(initStatus)"
            )
        }
        defer {
            posix_spawn_file_actions_destroy(&fileActions)
        }

        var outPipe: [Int32] = [-1, -1]
        guard pipe(&outPipe) == 0 else {
            return ProcessResult(
                exitCode: -1,
                output: "pipe() failed: \(String(cString: strerror(errno)))"
            )
        }
        defer {
            if outPipe[0] != -1 { close(outPipe[0]) }
            if outPipe[1] != -1 { close(outPipe[1]) }
        }

        guard posix_spawn_file_actions_adddup2(&fileActions, outPipe[1], STDOUT_FILENO) == 0 else {
            return ProcessResult(exitCode: -1, output: "posix_spawn_file_actions_adddup2(stdout) failed")
        }

        guard posix_spawn_file_actions_adddup2(&fileActions, outPipe[1], STDERR_FILENO) == 0 else {
            return ProcessResult(exitCode: -1, output: "posix_spawn_file_actions_adddup2(stderr) failed")
        }

        guard posix_spawn_file_actions_addclose(&fileActions, outPipe[0]) == 0 else {
            return ProcessResult(exitCode: -1, output: "posix_spawn_file_actions_addclose(read) failed")
        }

        guard posix_spawn_file_actions_addclose(&fileActions, outPipe[1]) == 0 else {
            return ProcessResult(exitCode: -1, output: "posix_spawn_file_actions_addclose(write) failed")
        }

        var pid: pid_t = 0
        let spawnStatus = posix_spawn(&pid, executable, &fileActions, nil, argv, env)
        guard spawnStatus == 0 else {
            return ProcessResult(
                exitCode: Int32(spawnStatus),
                output: "posix_spawn failed: \(String(cString: strerror(spawnStatus)))"
            )
        }

        close(outPipe[1])
        outPipe[1] = -1

        let output = readAll(from: outPipe[0])

        close(outPipe[0])
        outPipe[0] = -1

        var waitStatus: Int32 = 0
        while waitpid(pid, &waitStatus, 0) == -1 {
            if errno == EINTR {
                continue
            }

            return ProcessResult(
                exitCode: -1,
                output: output + "\nwaitpid() failed: \(String(cString: strerror(errno)))"
            )
        }

        return ProcessResult(
            exitCode: decodeWaitStatus(waitStatus),
            output: output
        )
    }

    private func readAll(from fileDescriptor: Int32) -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let bytesRead = read(fileDescriptor, &buffer, buffer.count)

            if bytesRead > 0 {
                data.append(contentsOf: buffer[..<bytesRead])
            } else if bytesRead == 0 {
                break
            } else if errno == EINTR {
                continue
            } else {
                break
            }
        }

        return String(decoding: data, as: UTF8.self)
    }

    private func decodeWaitStatus(_ status: Int32) -> Int32 {
        let signal = status & 0x7F
        if signal == 0 {
            return (status >> 8) & 0xFF
        }
        return 128 + signal
    }
}
