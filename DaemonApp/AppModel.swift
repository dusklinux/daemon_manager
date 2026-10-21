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
    @Published private(set) var pendingSessionChangeCount = 0
    private var pendingSessionOperations: [DisabledServiceKey: (service: LaunchdService, disable: Bool)] = [:]
    // Keep selections while the execution console replaces the tab content.
    @Published var serviceSelection: Set<String> = []
    @Published var criticalSelection: Set<String> = []
    @Published var selectingServices = false
    @Published var selectingCriticalServices = false
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
    @Published private(set) var springBoardUIState: SpringBoardUIState?
    @Published private(set) var springBoardUIError: String?

    @Published private(set) var duskMemoryStatus: DuskieMemoryStatus?
    @Published private(set) var duskMemoryError: String?
    @Published private(set) var isChangingDuskieMemory = false
    var hasDuskieMemoryWorker: Bool {
        FileManager.default.isExecutableFile(atPath: "/var/jb/usr/libexec/duskie-control")
    }
    private var isReadingDuskieMemory = false

    func refreshDuskieMemory() {
        guard !isReadingDuskieMemory, !isChangingDuskieMemory else { return }
        isReadingDuskieMemory = true
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try DuskieMemoryStatus.read() }
            DispatchQueue.main.async {
                self.isReadingDuskieMemory = false
                switch result {
                case .success(let status): self.duskMemoryStatus = status; self.duskMemoryError = nil
                case .failure(let error): self.duskMemoryStatus = nil; self.duskMemoryError = error.localizedDescription
                }
            }
        }
    }

    func setDuskieMemory(enabled: Bool) {
        guard hasDuskieMemoryWorker, !isChangingDuskieMemory else { return }
        isChangingDuskieMemory = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.posixRunSync(executable: "/var/jb/usr/libexec/duskie-control",
                                          args: [enabled ? "memory-start" : "memory-stop"], trackProcess: false)
            let status = try? DuskieMemoryStatus.read()
            DispatchQueue.main.async {
                self.isChangingDuskieMemory = false
                self.duskMemoryStatus = status
                self.duskMemoryError = result.exitCode == 0 ? nil : "Worker command failed (\(result.exitCode)): \(result.output)"
            }
        }
    }

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
        service.domain != nil && disabledServices != nil && !isApplyingConfig && !isDiagnosingDisk && !isChangingAirDrop && !isRefreshingState && !isScanningDaemons && isProcessing.isEmpty
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
            let result = self.posixRunSync(executable: elevated.executable, args: elevated.arguments, standardInput: elevated.standardInput, trackProcess: false)
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
            let result = self.posixRunSync(executable: command.executable, args: command.arguments, standardInput: command.standardInput, trackProcess: false)
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
                self.disabledServices = failures.isEmpty ? merged : nil
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
        
        isProcessing.insert(service.id)
        DispatchQueue.global(qos: .userInitiated).async {
            let cmd = self.nativeOverrideCommand(operations: [(service, !enable)], live: OverrideServices.labels.contains(service.label))
            let elevated = self.buildElevatedCommand(rawCommand: cmd, pwd: pwd)
            let result = self.posixRunSync(executable: elevated.executable, args: elevated.arguments, standardInput: elevated.standardInput)
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
                    self.recordSessionChanges([(service: service, disable: !enable)], live: OverrideServices.labels.contains(service.label))
                    self.statusMessage = OverrideServices.labels.contains(service.label)
                        ? "Feature override and loaded job state verified."
                        : "Override saved. Choose Apply Now for this session or Restart Userspace."
                }
            }
        }
    }

    private func recordSessionChanges(_ operations: [(service: LaunchdService, disable: Bool)], live: Bool) {
        for operation in operations {
            guard let domain = operation.service.domain else { continue }
            let key = DisabledServiceKey(domain: domain, label: operation.service.label)
            if live { pendingSessionOperations.removeValue(forKey: key) }
            else { pendingSessionOperations[key] = operation }
        }
        pendingSessionChangeCount = pendingSessionOperations.count
    }

    func applySelectedServices(_ services: [LaunchdService], enable: Bool) {
        guard disabledServices != nil else { return }
        let operations = services.filter { $0.domain != nil }.map { (service: $0, disable: !enable) }
        executeNativeBatch(operations: operations, title: "Selected services: \(enable ? "On" : "Off")")
    }

    func applyPendingSessionChanges() {
        let operations = pendingSessionOperations.values.sorted { $0.service.id < $1.service.id }
        executeNativeBatch(operations: operations, title: "Applying saved changes now", live: true)
    }

    // Apply changed builtin or explicitly customized targets.
    func applyAllDefaults() {
        guard disabledServices != nil, !isApplyingConfig, !isDiagnosingDisk, !isChangingAirDrop,
              !isRefreshingState, !isScanningDaemons, isProcessing.isEmpty else { return }
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
    private func executeNativeBatch(operations: [(service: LaunchdService, disable: Bool)], title: String, live: Bool = false, airDropControl: [Any]? = nil, interfaceControl: [Any]? = nil, completion: ((Bool) -> Void)? = nil) {
        guard !isApplyingConfig, !isDiagnosingDisk, !isChangingAirDrop, isProcessing.isEmpty else { return }
        let pwd = self.rootPassword
        var seen = Set<DisabledServiceKey>()
        let operations = operations.filter { op in
            guard let domain = op.service.domain else { return false }
            return seen.insert(DisabledServiceKey(domain: domain, label: op.service.label)).inserted
        }
        let controlCount = (airDropControl == nil ? 0 : 1) + (interfaceControl == nil ? 0 : 1)
        let total = operations.count + controlCount
        
        guard total > 0 else {
            statusMessage = "All requested daemons already match target state."
            completion?(true)
            return
        }

        let warningCount = operations.filter { SafetyManager.requiresWarning($0.service.label) && $0.disable }.count

        isApplyingConfig = true
        if airDropControl != nil { airDropAllowed = nil; airDropError = nil }
        if interfaceControl != nil { springBoardUIState = nil; springBoardUIError = nil }
        showLogConsole = true
        var startLog = "--- STARTING BATCH: \(title) (\(operations.count) services, \(controlCount) feature controls) ---\n"
        if warningCount > 0 {
            startLog += "[!] CAUTION: \(warningCount) services with keep-enabled warnings included in disable batch.\n"
        }
        liveLog = startLog
        applyProgressText = "\(title) [0/\(total)]"

        DispatchQueue.global(qos: .userInitiated).async {
            let rawCmd = self.nativeOverrideCommand(operations: operations, live: live, airDropControl: airDropControl, interfaceControl: interfaceControl)
            let elevated = self.buildElevatedCommand(rawCommand: rawCmd, pwd: pwd)

            var completedCount = 0
            var pendingOutput = ""
            self.posixRunAsync(
                executable: elevated.executable,
                args: elevated.arguments,
                standardInput: elevated.standardInput
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
                    if airDropControl != nil {
                        let line = self.liveLog.split(separator: "\n").last { $0.hasPrefix("airdrop_allowed=") }
                        let value = line.flatMap { Int($0.dropFirst("airdrop_allowed=".count)) }
                        self.airDropAllowed = value.flatMap { [0, 1].contains($0) ? $0 == 1 : nil }
                    }
                    if interfaceControl != nil {
                        let line = self.liveLog.split(separator: "\n").last { $0.hasPrefix("ui_state=") }
                        self.springBoardUIState = line.flatMap {
                            try? JSONDecoder().decode(SpringBoardUIState.self, from: Data($0.dropFirst(9).utf8))
                        }
                    }
                    self.refreshState {
                        DispatchQueue.main.async {
                            self.isApplyingConfig = false
                            if exitCode != 0 {
                                self.recordSessionChanges(operations.filter {
                                    self.isDisabled($0.service) == $0.disable
                                }, live: false)
                            }
                            completion?(exitCode == 0)
                        }
                    }
                    if exitCode == 0 {
                        self.recordSessionChanges(operations, live: live)
                        if controlCount > 0 {
                            self.statusMessage = "\(operations.count) service overrides and \(controlCount) feature controls saved. Apply Now handles jobs; interface changes need respring or userspace restart."
                        } else {
                            self.statusMessage = live
                                ? "\(total) feature overrides and loaded jobs verified. Respring if a client retained its previous state."
                                : "\(total) overrides saved. Choose Apply Now or Restart Userspace."
                        }
                    } else {
                        self.statusMessage = nil
                        self.errorMessage = "\(title) failed or only partially applied (exit \(exitCode)). Review the execution log."
                    }
                }
            }
        }
    }

    func applyFeatureGroup(_ group: OverrideGroup, enable: Bool) {
        applyFeatureGroups([group], enable: enable)
    }

    func applyFeatureGroups(_ groups: [OverrideGroup], enable: Bool, includeSpringBoardInterfaces: Bool = false) {
        guard disabledServices != nil, !isApplyingConfig, !isDiagnosingDisk,
              !isChangingAirDrop, !isRefreshingState, !isScanningDaemons, isProcessing.isEmpty,
              !groups.isEmpty || includeSpringBoardInterfaces else { return }
        var airDropControl: [Any]?
        var interfaceControl: [Any]?
        if groups.contains(where: \.controlsAirDrop) {
            guard let helper = Bundle.main.path(forResource: "airdrop-policy", ofType: nil) else {
                errorMessage = "AirDrop policy helper is missing from this build."
                return
            }
            airDropControl = [helper, enable]
        }
        if includeSpringBoardInterfaces {
            guard let asset = Bundle.main.path(forResource: "DaemonManagerUI", ofType: "dylib") else {
                errorMessage = "The SpringBoard companion is missing from this build."
                return
            }
            interfaceControl = [asset, !enable]
        }
        let labels = Set(OverrideServices.actionLabels(for: groups, enable: enable))
        let features = Set(groups.flatMap(\.labels))
        let operations = allDaemons.filter { service in
            guard labels.contains(service.label) else { return false }
            return features.contains(service.label) || isDisabled(service) == true
        }.map { (service: $0, disable: !enable) }
        let live = operations.allSatisfy { OverrideServices.labels.contains($0.service.label) }
        let title = groups.count == 1 && !includeSpringBoardInterfaces
            ? groups[0].title : "Selected groups"
        executeNativeBatch(operations: operations, title: "\(title): \(enable ? "On" : "Off")",
                           live: live, airDropControl: airDropControl, interfaceControl: interfaceControl)
    }

    // Emergency Factory Reset (borrowed from Geranium)
    func emergencyResetLaunchd() {
        guard !isApplyingConfig, !isDiagnosingDisk, !isChangingAirDrop, isProcessing.isEmpty else { return }
        let pwd = self.rootPassword
        let resetScript = """
        cp /var/db/com.apple.xpc.launchd/disabled.plist /var/db/com.apple.xpc.launchd/disabled.backup 2>/dev/null
        rm -f /var/db/com.apple.xpc.launchd/disabled.plist /var/db/com.apple.xpc.launchd/disabled.migrated
        """
        
        let elevated = buildElevatedCommand(rawCommand: resetScript, pwd: pwd)
        DispatchQueue.global(qos: .userInitiated).async {
            let res = self.posixRunSync(executable: elevated.executable, args: elevated.arguments, standardInput: elevated.standardInput)
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
        guard !isApplyingConfig, !isDiagnosingDisk, !isChangingAirDrop, isProcessing.isEmpty else { return }
        let pwd = self.rootPassword
        let cmd = "if command -v sbreload >/dev/null 2>&1; then sbreload; else killall -9 SpringBoard backboardd; fi"
        let elevated = buildElevatedCommand(rawCommand: cmd, pwd: pwd)
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.posixRunSync(executable: elevated.executable, args: elevated.arguments, standardInput: elevated.standardInput)
        }
    }

    // Userspace Reboot
    func userspaceReboot() {
        guard !isApplyingConfig, !isDiagnosingDisk, !isChangingAirDrop, isProcessing.isEmpty else { return }
        let pwd = self.rootPassword
        let cmd = "launchctl reboot userspace"
        let elevated = buildElevatedCommand(rawCommand: cmd, pwd: pwd)
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.posixRunSync(executable: elevated.executable, args: elevated.arguments, standardInput: elevated.standardInput)
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
        guard !targetStates.isEmpty, disabledServices != nil, !isApplyingConfig, !isDiagnosingDisk,
              !isChangingAirDrop, !isRefreshingState, !isScanningDaemons, isProcessing.isEmpty else { return }
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

    private func nativeOverrideCommand(operations: [(service: LaunchdService, disable: Bool)], live: Bool = false, airDropControl: [Any]? = nil, interfaceControl: [Any]? = nil) -> String {
        let items = operations.compactMap { op -> [String]? in
            guard let domain = op.service.domain else { return nil }
            let item = [op.service.label, op.disable ? "disable" : "enable", domain]
            return live ? item + [op.service.plistPath ?? ""] : item
        }
        let arguments: [Any] = [items, live, airDropControl as Any? ?? NSNull(), interfaceControl as Any? ?? NSNull()]
        let data = try! JSONSerialization.data(withJSONObject: arguments)
        let payload = data.base64EncodedString()
        let script = NativeOverrides.script + "\n" +
            (airDropControl == nil ? "" : AirDropControl.script) + "\n" +
            (interfaceControl == nil ? "" : SpringBoardUIControl.script) + "\n" +
            FeatureBatchControl.script + "\nsys.exit(apply_feature_batch(*json.loads(base64.b64decode('\(payload)'))))\n"
        return "\(Self.shellQuote(pythonPath)) -c \(Self.shellQuote(script))"
    }

    func refreshAirDrop() { runAirDropPolicy(action: "read") }
    func refreshSpringBoardUI() { runSpringBoardUI(action: "read") }
    func setSpringBoardInterface(_ key: String, disabled: Bool) {
        runSpringBoardUI(action: "set", values: [key: disabled])
    }
    func setSpringBoardInterfaces(disabled: Bool) {
        runSpringBoardUI(action: "set", values: Dictionary(uniqueKeysWithValues: SpringBoardUIControl.keys.map { ($0, disabled) }))
    }
    func removeSpringBoardUI() { runSpringBoardUI(action: "remove") }

    private func runSpringBoardUI(action: String, values: [String: Bool] = [:]) {
        guard !isApplyingConfig, !isChangingAirDrop, !isDiagnosingDisk, isProcessing.isEmpty else { return }
        guard let asset = Bundle.main.path(forResource: "DaemonManagerUI", ofType: "dylib") else {
            springBoardUIError = "The SpringBoard companion is missing from this build."
            return
        }
        isApplyingConfig = true
        springBoardUIError = nil
        if action != "read" { liveLog = "Updating SpringBoard interfaces…\n"; showLogConsole = true }
        let data = try! JSONSerialization.data(withJSONObject: [asset, action, values])
        let script = SpringBoardUIControl.script + "\nimport base64\nui_control(*json.loads(base64.b64decode('\(data.base64EncodedString())')))\n"
        let elevated = buildElevatedCommand(rawCommand: Self.shellQuote(pythonPath) + " -c " + Self.shellQuote(script), pwd: rootPassword)
        DispatchQueue.global(qos: .utility).async {
            let result = self.posixRunSync(executable: elevated.executable, args: elevated.arguments, standardInput: elevated.standardInput, trackProcess: false)
            let line = result.output.split(separator: "\n").first { $0.hasPrefix("ui_state=") }
            let state = line.flatMap { try? JSONDecoder().decode(SpringBoardUIState.self, from: Data($0.dropFirst(9).utf8)) }
            DispatchQueue.main.async {
                self.isApplyingConfig = false
                if action != "read" { self.liveLog += result.output + "\n[exit \(result.exitCode)]\n" }
                if result.exitCode == 0, let state { self.springBoardUIState = state }
                else { self.springBoardUIState = nil; self.springBoardUIError = result.output.isEmpty ? "Could not read interface settings." : result.output }
            }
        }
    }
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
            let result = self.posixRunSync(executable: elevated.executable, args: elevated.arguments, standardInput: elevated.standardInput, trackProcess: false)
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

    private func buildElevatedCommand(rawCommand: String, pwd: String) -> ElevatedCommand {
        ElevatedCommand.build(command: rawCommand, password: pwd, shell: rootlessShellPath,
                              sudo: sudoPath, python: pythonPath,
                              hasSudo: FileManager.default.fileExists(atPath: sudoPath))
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
    
    private func posixRunAsync(executable: String, args: [String], standardInput: String? = nil, trackProcess: Bool = true, onOutput: @escaping (String) -> Void, onCompletion: @escaping (Int32) -> Void) {
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
        guard pipe(&outPipe) == 0 else { onCompletion(-1); return }
        var inputPipe: [Int32] = [-1, -1]
        if standardInput != nil {
            guard pipe(&inputPipe) == 0 else {
                close(outPipe[0]); close(outPipe[1]); onCompletion(-1); return
            }
            fcntl(inputPipe[1], F_SETNOSIGPIPE, 1)
            posix_spawn_file_actions_adddup2(&fileActions, inputPipe[0], STDIN_FILENO)
            posix_spawn_file_actions_addclose(&fileActions, inputPipe[0])
            posix_spawn_file_actions_addclose(&fileActions, inputPipe[1])
        }
        // Concurrent read-only helpers must not inherit another helper's pipe
        // and keep its output or password input open after that helper exits.
        for fd in outPipe + inputPipe where fd >= 0 { fcntl(fd, F_SETFD, FD_CLOEXEC) }
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
        if inputPipe[0] >= 0 { close(inputPipe[0]) }
        if spawnStatus != 0 {
            close(outPipe[0])
            if inputPipe[1] >= 0 { close(inputPipe[1]) }
            onCompletion(-1)
            return
        }
        if let standardInput {
            let inputFD = inputPipe[1]
            DispatchQueue.global().async {
                defer { close(inputFD) }
                Data(standardInput.utf8).withUnsafeBytes { bytes in
                    var offset = 0
                    while offset < bytes.count {
                        let written = write(inputFD, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                        if written > 0 { offset += written }
                        else if written < 0 && errno == EINTR { continue }
                        else { break }
                    }
                }
            }
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

    private func posixRunSync(executable: String, args: [String], standardInput: String? = nil, trackProcess: Bool = true) -> (exitCode: Int32, output: String) {
        let semaphore = DispatchSemaphore(value: 0)
        var fullOutput = ""
        var finalCode: Int32 = -1
        posixRunAsync(executable: executable, args: args, standardInput: standardInput, trackProcess: trackProcess) { text in fullOutput += text } onCompletion: { code in
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
