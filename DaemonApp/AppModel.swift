import Foundation
import Combine
import Darwin

struct LaunchdService: Identifiable, Hashable {
    enum Kind: String {
        case agent = "LaunchAgent"
        case daemon = "LaunchDaemon"
        case angel = "LaunchAngel"
        case unresolved = "Unresolved"
    }

    let label: String
    let plistPath: String?
    let domain: String?
    let kind: Kind
    var executablePath: String? = nil

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

    @Published var ramUsageText = "… MiB"
    @Published var freeRAMMB: Double = 0.0
    @Published private(set) var memorySnapshot: MemorySnapshot?
    @Published private(set) var memoryPressure: MemoryPressure?
    @Published private(set) var isReadingMemoryPressure = false
    private var pressureSource: DispatchSourceMemoryPressure?
    private var pressureRevision = 0
    @Published var isDarkTheme = true
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    
    // Default to 2345 matching user device
    @Published var rootPassword = UserDefaults.standard.string(forKey: "rootPassword") ?? "2345" {
        didSet { UserDefaults.standard.set(rootPassword, forKey: "rootPassword") }
    }
    
    @Published private(set) var rawConfigContent: String? = nil
    @Published private(set) var targetStates: [String: Bool] = [:]
    
    @Published var applyProgressText: String? = nil
    @Published var isApplyingConfig: Bool = false
    @Published var showLogConsole: Bool = false
    @Published var liveLog: String = ""
    
    @Published private(set) var diskHealthReport: DiskHealthReport?
    @Published private(set) var diskHealthError: String?
    @Published private(set) var isDiagnosingDisk = false
    @Published private(set) var airDropAllowed: Bool?
    @Published private(set) var airDropError: String?
    @Published private(set) var isChangingAirDrop = false

    private var currentPid: pid_t? = nil
    private var disabledServices: Set<DisabledServiceKey>?
    private var importedLabels: [String] = []
    private var timer: Timer?

    let mobileDomain: String
    
    // Fallback paths across rootless and rootful setups
    var rootlessShellPath: String {
        if FileManager.default.fileExists(atPath: "/var/jb/bin/sh") { return "/var/jb/bin/sh" }
        return "/bin/sh"
    }
    
    var sudoPath: String {
        if FileManager.default.fileExists(atPath: "/var/jb/usr/bin/sudo") { return "/var/jb/usr/bin/sudo" }
        return "/usr/bin/sudo"
    }
    
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
        startMemoryPressureMonitoring()
        fetchAllDaemons()
        refreshState()
        loadInitialConfig()
    }

    deinit {
        timer?.invalidate()
        pressureSource?.cancel()
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
        service.domain != nil && disabledServices != nil && !isApplyingConfig && !isDiagnosingDisk && !isChangingAirDrop && !isProcessing.contains(service.id)
    }

    func toggleUnavailableReason(_ service: LaunchdService) -> String? {
        if service.domain == nil { return "This service domain could not be resolved." }
        if disabledServices == nil { return "Current launchd state is still loading." }
        return nil
    }

    func startRAMTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateRAMUsage()
        }
        updateRAMUsage()
    }

    private func updateRAMUsage() {
        // Refreshing failure must not leave a stale value looking live.
        let snapshot = MemorySnapshot.read()
        memorySnapshot = snapshot
        freeRAMMB = snapshot?.freeAndSpeculativeMiB ?? 0
        ramUsageText = snapshot.map { String(format: "%.0f MiB", $0.freeAndSpeculativeMiB) } ?? "— MiB"
    }

    private func startMemoryPressureMonitoring() {
        memoryPressure = MemoryPressure.read()
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let flags = source?.data else { return }
            if flags.contains(.critical) { self.memoryPressure = .critical }
            else if flags.contains(.warning) { self.memoryPressure = .warning }
            else if flags.contains(.normal) { self.memoryPressure = .normal }
            self.pressureRevision += 1
        }
        pressureSource = source
        source.activate()
    }

    func refreshMemoryDetails() {
        updateRAMUsage()
        guard !isReadingMemoryPressure else { return }
        if let pressure = MemoryPressure.read() {
            memoryPressure = pressure
            pressureRevision += 1
            return
        }
        // iOS restricts the current-pressure sysctl to privileged callers.
        // Seed the live notification monitor once per panel opening/refresh.
        isReadingMemoryPressure = true
        let revision = pressureRevision
        let script = #"""
import ctypes as c
lib = c.CDLL(None)
value = c.c_int32()
size = c.c_size_t(4)
rc = lib.sysctlbyname(b"kern.memorystatus_vm_pressure_level", c.byref(value), c.byref(size), None, 0)
if rc == 0:
    print("pressure=" + str(value.value))
"""#
        let elevated = buildElevatedCommand(rawCommand: Self.shellQuote(pythonPath) + " -c " + Self.shellQuote(script), pwd: rootPassword)
        DispatchQueue.global(qos: .utility).async {
            let result = self.posixRunSync(executable: elevated.executable, args: elevated.arguments, trackProcess: false)
            let line = result.output.split(separator: "\n").first { $0.hasPrefix("pressure=") }
            let value = line.flatMap { Int32($0.dropFirst("pressure=".count)) }
            let pressure = value.flatMap { MemoryPressure(rawValue: $0) }
            DispatchQueue.main.async {
                self.isReadingMemoryPressure = false
                // A newer live event takes precedence over the initial read.
                if self.pressureRevision == revision, result.exitCode == 0, let pressure {
                    self.memoryPressure = pressure
                    self.pressureRevision += 1
                }
            }
        }
    }

    func readDiskHealth(generate: Bool) {
        guard !isDiagnosingDisk, !isApplyingConfig, !isChangingAirDrop, isProcessing.isEmpty else { return }
        isDiagnosingDisk = true
        diskHealthReport = nil
        diskHealthError = nil
        let script = DiskDiagnostics.script + "\nrun(" + (generate ? "True" : "False") + ")\n"
        let command = buildElevatedCommand(rawCommand: Self.shellQuote(pythonPath) + " -c " + Self.shellQuote(script), pwd: rootPassword)
        DispatchQueue.global(qos: .utility).async {
            let result = self.posixRunSync(executable: command.executable, args: command.arguments, trackProcess: false)
            let lines = result.output.split(separator: "\n")
            let json = lines.first { $0.hasPrefix("disk_report=") }.map { Data($0.dropFirst(12).utf8) }
            let report = json.flatMap { try? JSONDecoder().decode(DiskHealthReport.self, from: $0) }
            let error = lines.first { $0.hasPrefix("disk_error=") }.map { String($0.dropFirst(11)) }
            DispatchQueue.main.async {
                self.isDiagnosingDisk = false
                self.diskHealthReport = result.exitCode == 0 ? report : nil
                self.diskHealthError = self.diskHealthReport == nil ? (error ?? "Could not read the diagnostic. Check the root password in Tools.") : nil
                self.refreshState()
            }
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
                    failures.append("launchctl print-disabled \(domain) exited with code \(result.exitCode).")
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
                ("/System/Library/LaunchAngels", .angel, self.mobileDomain),
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
                    // Input and shared system overlays remain outside the tested feature hosts.
                    if location.kind == .angel && !OverrideServices.labels.contains(service.label) { continue }
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

    // Direct native launchctl execution - works out of the box without external scripts!
    func toggleDaemon(_ service: LaunchdService, enable: Bool) {
        guard canToggle(service) else { return }
        let pwd = self.rootPassword
        let action = enable ? "enable" : "disable"
        
        DispatchQueue.main.async { self.isProcessing.insert(service.id) }
        DispatchQueue.global(qos: .userInitiated).async {
            let cmd = self.nativeOverrideCommand(operations: [(service, !enable)], live: OverrideServices.labels.contains(service.label))
            let elevated = self.buildElevatedCommand(rawCommand: cmd, pwd: pwd)
            let result = self.posixRunSync(executable: elevated.executable, args: elevated.arguments)
            guard result.exitCode == 0 else {
                DispatchQueue.main.async {
                    self.isProcessing.remove(service.id)
                    self.errorMessage = "Failed to \(action) \(service.label) (exit code \(result.exitCode)).\n\(result.output)"
                }
                return
            }
            self.refreshState {
                DispatchQueue.main.async {
                    self.isProcessing.remove(service.id)
                    self.statusMessage = OverrideServices.labels.contains(service.label)
                        ? "Feature override and loaded job state verified."
                        : "Override saved. Restart userspace to apply the process change fully."
                }
            }
        }
    }

    // Apply changed builtin or explicitly customized targets.
    func applyAllDefaults() {
        guard disabledServices != nil, !isApplyingConfig, !isDiagnosingDisk, !isChangingAirDrop else { return }
        let presets = DefaultPresets.shared
        var targetsToChange: [(service: LaunchdService, disable: Bool)] = []
        
        for service in allDaemons {
            let targetDisable = presets.targetState(for: service.label)
            let currentlyDisabled = isDisabled(service) ?? false
            if currentlyDisabled != targetDisable {
                targetsToChange.append((service, targetDisable))
            }
        }
        
        guard !targetsToChange.isEmpty else {
            statusMessage = "All daemons already match the curated defaults!"
            return
        }
        
        executeNativeBatch(operations: targetsToChange, title: "Applying Defaults")
    }

    // Native batch executor with live progress
    private func executeNativeBatch(operations: [(service: LaunchdService, disable: Bool)], title: String, live: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard !isDiagnosingDisk, !isChangingAirDrop else { return }
        let pwd = self.rootPassword
        var seen = Set<DisabledServiceKey>()
        let operations = operations.filter { op in
            guard let domain = op.service.domain else { return false }
            return seen.insert(DisabledServiceKey(domain: domain, label: op.service.label)).inserted
        }
        let total = operations.count
        
        guard total > 0 else {
            statusMessage = "All requested daemons already match target state."
            completion?(true)
            return
        }

        let warningCount = operations.filter { SafetyManager.requiresWarning($0.service.label) && $0.disable }.count

        DispatchQueue.main.async {
            self.isApplyingConfig = true
            self.showLogConsole = true
            var startLog = "--- STARTING BATCH: \(title) (\(total) services) ---\n"
            if warningCount > 0 {
                startLog += "[!] CAUTION: \(warningCount) services with keep-enabled warnings included in disable batch.\n"
            }
            self.liveLog = startLog
            self.applyProgressText = "\(title) [0/\(total)]"
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let rawCmd = self.nativeOverrideCommand(operations: operations, live: live)
            let elevated = self.buildElevatedCommand(rawCommand: rawCmd, pwd: pwd)

            var completedCount = 0
            var pendingOutput = ""
            self.posixRunAsync(
                executable: elevated.executable,
                args: elevated.arguments
            ) { liveText in
                DispatchQueue.main.async {
                    self.liveLog += liveText
                    pendingOutput += liveText
                    while let newline = pendingOutput.firstIndex(of: "\n") {
                        let line = String(pendingOutput[..<newline])
                        pendingOutput.removeSubrange(...newline)
                        if line.hasPrefix("[done]") { completedCount += 1 }
                    }
                    self.applyProgressText = "\(title) [\(min(completedCount, total))/\(total)]"
                }
            } onCompletion: { exitCode in
                DispatchQueue.main.async {
                    self.liveLog += "\n--- BATCH COMPLETED WITH EXIT CODE \(exitCode) ---\n"
                    self.applyProgressText = nil
                    self.refreshState {
                        DispatchQueue.main.async {
                            self.isApplyingConfig = false
                            completion?(exitCode == 0)
                        }
                    }
                    if exitCode == 0 {
                        self.statusMessage = live
                            ? "\(total) feature overrides and loaded jobs verified. Respring if a client retained its previous state."
                            : "\(total) overrides saved. Restart userspace to apply the process changes fully."
                    } else {
                        self.statusMessage = nil
                        self.errorMessage = "\(title) failed or only partially applied (exit \(exitCode)). Review the execution log."
                    }
                }
            }
        }
    }

    func applyFeatureGroup(_ group: OverrideGroup, enable: Bool) {
        guard disabledServices != nil, !isApplyingConfig, !isDiagnosingDisk,
              !isChangingAirDrop, isProcessing.isEmpty else { return }
        let labels = Set(group.actionLabels(enable: enable))
        let operations = allDaemons.filter { service in
            guard labels.contains(service.label) else { return false }
            // Feature jobs are reverified even if their saved state already matches.
            // Shared dependencies are enabled only when their override is disabled.
            return group.labels.contains(service.label) || isDisabled(service) == true
        }.map { (service: $0, disable: !enable) }
        let live = operations.allSatisfy { OverrideServices.labels.contains($0.service.label) }
        executeNativeBatch(operations: operations, title: "\(group.title): \(enable ? "On" : "Off")", live: live) { success in
            if success && group.controlsAirDrop { self.setAirDropAllowed(enable) }
        }
    }

    // Emergency Factory Reset (borrowed from Geranium)
    func emergencyResetLaunchd() {
        guard !isDiagnosingDisk, !isChangingAirDrop else { return }
        let pwd = self.rootPassword
        let resetScript = """
        cp /var/db/com.apple.xpc.launchd/disabled.plist /var/db/com.apple.xpc.launchd/disabled.backup 2>/dev/null
        rm -f /var/db/com.apple.xpc.launchd/disabled.plist /var/db/com.apple.xpc.launchd/disabled.migrated
        """
        
        let elevated = buildElevatedCommand(rawCommand: resetScript, pwd: pwd)
        DispatchQueue.global(qos: .userInitiated).async {
            let res = self.posixRunSync(executable: elevated.executable, args: elevated.arguments)
            DispatchQueue.main.async {
                if res.exitCode == 0 {
                    self.statusMessage = "Launchd disabled database reset. Backup saved to disabled.backup. Please userspace reboot or respring."
                    self.refreshState()
                } else {
                    self.errorMessage = "Emergency reset failed: \(res.output)"
                }
            }
        }
    }

    // Quick Respring
    func respring() {
        guard !isDiagnosingDisk, !isChangingAirDrop else { return }
        let pwd = self.rootPassword
        let cmd = "if command -v sbreload >/dev/null 2>&1; then sbreload; else killall -9 SpringBoard backboardd; fi"
        let elevated = buildElevatedCommand(rawCommand: cmd, pwd: pwd)
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.posixRunSync(executable: elevated.executable, args: elevated.arguments)
        }
    }

    // Userspace Reboot
    func userspaceReboot() {
        guard !isDiagnosingDisk, !isChangingAirDrop else { return }
        let pwd = self.rootPassword
        let cmd = "launchctl reboot userspace"
        let elevated = buildElevatedCommand(rawCommand: cmd, pwd: pwd)
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.posixRunSync(executable: elevated.executable, args: elevated.arguments)
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
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        
        guard let data = try? Data(contentsOf: url) else {
            presentError("Permission Denied: Cannot read \(fileName).")
            return
        }

        if fileName == "daemonmanager" {
            self.daemonManagerPath = url.path
            validateEnvironment()
            liveLog += "\n[+] Detected custom script: \(url.path)"
        } else {
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

    func applyImportedConfig() {
        guard !targetStates.isEmpty, disabledServices != nil, !isApplyingConfig, !isChangingAirDrop else { return }
        var targetsToChange: [(service: LaunchdService, disable: Bool)] = []
        for service in allDaemons {
            if let targetDisable = targetStates[service.label] {
                let currentlyDisabled = isDisabled(service) ?? false
                if currentlyDisabled != targetDisable {
                    targetsToChange.append((service, targetDisable))
                }
            }
        }
        executeNativeBatch(operations: targetsToChange, title: "Applying Config")
    }

    func exportCurrentConfig() -> String {
        var lines: [String] = ["# Exported Daemon Configuration", "# Format: <label> <yes: disable | no: keep enabled>"]
        for service in allDaemons {
            let isOff = isDisabled(service) ?? false
            lines.append("\(service.label) \(isOff ? "yes" : (SafetyManager.isCritical(service.label) ? "NO" : "no"))")
        }
        return lines.joined(separator: "\n")
    }

    private func nativeOverrideCommand(operations: [(service: LaunchdService, disable: Bool)], live: Bool = false) -> String {
        let items = operations.compactMap { op -> [String]? in
            guard let domain = op.service.domain else { return nil }
            let item = [op.service.label, op.disable ? "disable" : "enable", domain]
            return live ? item + [op.service.plistPath ?? ""] : item
        }
        let data = try! JSONSerialization.data(withJSONObject: items)
        let payload = data.base64EncodedString()
        let function = live ? "apply_live" : "apply"
        let script = NativeOverrides.script + "\nsys.exit(\(function)(json.loads(base64.b64decode('\(payload)'))))\n"
        return "\(Self.shellQuote(pythonPath)) -c \(Self.shellQuote(script))"
    }

    func refreshAirDrop() { runAirDropPolicy(action: "read") }
    func setAirDropAllowed(_ allowed: Bool) { runAirDropPolicy(action: allowed ? "on" : "off") }

    private func runAirDropPolicy(action: String) {
        guard !isChangingAirDrop, !isApplyingConfig, !isDiagnosingDisk, isProcessing.isEmpty else { return }
        guard let helper = Bundle.main.path(forResource: "airdrop-policy", ofType: nil) else {
            airDropError = "AirDrop policy helper is missing from this build."
            return
        }
        isChangingAirDrop = true
        airDropError = nil
        let data = try! JSONSerialization.data(withJSONObject: [helper, action])
        let script = NativeOverrides.script + "\n" + AirDropControl.script +
            "\nsys.exit(air_drop(*json.loads(base64.b64decode('\(data.base64EncodedString())'))))\n"
        let elevated = buildElevatedCommand(rawCommand: Self.shellQuote(pythonPath) + " -c " + Self.shellQuote(script), pwd: rootPassword)
        DispatchQueue.global(qos: .utility).async {
            let result = self.posixRunSync(executable: elevated.executable, args: elevated.arguments, trackProcess: false)
            let line = result.output.split(separator: "\n").first { $0.hasPrefix("airdrop_allowed=") }
            let value = line.flatMap { Int($0.dropFirst("airdrop_allowed=".count)) }
            DispatchQueue.main.async {
                self.isChangingAirDrop = false
                if result.exitCode == 0, let value, [0, 1].contains(value) {
                    self.airDropAllowed = value == 1
                    if action != "read" { self.statusMessage = value == 1 ? "AirDrop allowed. Enable its interface host to use it." : "AirDrop sending and receiving disabled." }
                } else {
                    self.airDropAllowed = nil
                    self.airDropError = result.output.isEmpty ? "Could not verify AirDrop policy." : result.output
                }
                self.refreshState()
            }
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func buildElevatedCommand(rawCommand: String, pwd: String) -> (executable: String, arguments: [String]) {
        let safePwd = pwd.replacingOccurrences(of: "\"", with: "\\\"")
        let innerCmd = rawCommand.replacingOccurrences(of: "'", with: "'\\''")
        
        if FileManager.default.fileExists(atPath: sudoPath) {
            let shellCmd = "echo \"\(safePwd)\" | \"\(sudoPath)\" -S -p \"\" \(rootlessShellPath) -c '\(innerCmd)'"
            return (rootlessShellPath, ["-c", shellCmd])
        } else {
            let pythonExe = pythonPath
            let pythonScript = """
            import os, sys, pty, select
            pw = sys.argv[1]
            cmd = sys.argv[2:]
            pid, fd = pty.fork()
            if pid == 0:
                os.execv(cmd[0], cmd)
            else:
                buf = b""
                while True:
                    r, _, _ = select.select([fd], [], [], 2.0)
                    if not r: break
                    try:
                        c = os.read(fd, 1024)
                        if not c: break
                        buf += c
                        if b"assword" in buf or b"Password:" in buf: break
                    except OSError:
                        break
                os.write(fd, (pw + "\\n").encode())
                try:
                    while True:
                        d = os.read(fd, 1024)
                        if not d: break
                        sys.stdout.buffer.write(d)
                        sys.stdout.flush()
                except OSError:
                    pass
                _, s = os.waitpid(pid, 0)
                sys.exit((s >> 8) & 0xFF)
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
            // Native mode is active by default; script is optional
            self.environmentWarning = available ? nil : "Native Mode: Direct launchctl execution (Standalone)"
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
                    // yes = disable (target: true), no = keep enabled (target: false)
                    if ["yes", "off", "disable", "disabled"].contains(mode) { targets[label] = true }
                    else if ["no", "on", "enable", "enabled"].contains(mode) { targets[label] = false }
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
        let arguments = plist["ProgramArguments"] as? [String]
        return LaunchdService(label: label, plistPath: plistURL.path, domain: domain, kind: kind,
                              executablePath: plist["Program"] as? String ?? arguments?.first)
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
    
    private func posixRunAsync(executable: String, args: [String], trackProcess: Bool = true, onOutput: @escaping (String) -> Void, onCompletion: @escaping (Int32) -> Void) {
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
        if trackProcess { self.currentPid = pid }
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
                if trackProcess && self.currentPid == pid { self.currentPid = nil }
                onCompletion(finalCode)
            }
        }
        source.resume()
    }

    private func posixRunSync(executable: String, args: [String], trackProcess: Bool = true) -> (exitCode: Int32, output: String) {
        let semaphore = DispatchSemaphore(value: 0)
        var fullOutput = ""
        var finalCode: Int32 = -1
        posixRunAsync(executable: executable, args: args, trackProcess: trackProcess) { text in fullOutput += text } onCompletion: { code in
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
