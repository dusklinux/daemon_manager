import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var presets = DefaultPresets.shared
    @State private var selectedTab = 0
    @State private var showFilePicker = false
    @State private var showResetDefaultsAlert = false
    @State private var showEmergencyResetAlert = false
    @State private var pendingToggleService: LaunchdService? = nil
    @State private var pendingToggleAction: Bool = false
    @State private var showSafetyAlert = false
    @State private var showMemoryDetails = false

    var body: some View {
        VStack(spacing: 0) {
            // TOP STATUS BAR: RAM Usage & Quick Info
            HStack(spacing: 12) {
                Button { showMemoryDetails = true } label: {
                    HStack(spacing: 6) {
                        Circle().fill(ramColor).frame(width: 10, height: 10)
                        Text(model.ramUsageText)
                            .font(.system(.subheadline, design: .monospaced, weight: .bold))
                            .foregroundColor(ramColor)
                        Image(systemName: "chevron.down").font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Memory details, \(model.ramUsageText)")

                Spacer()

                if model.isApplyingConfig {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        if let txt = model.applyProgressText {
                            Text(txt)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Button(action: { model.isDarkTheme.toggle() }) {
                    Image(systemName: model.isDarkTheme ? "sun.max.fill" : "moon.fill")
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemBackground))

            // Live status banner
            if let status = model.statusMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text(status).font(.caption).foregroundColor(.primary)
                    Spacer()
                    Button("Dismiss") { model.statusMessage = nil }
                        .font(.caption2.bold())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.15))
            }

            if model.showLogConsole {
                ConsoleLogView(logText: model.liveLog)
            } else {
                TabView(selection: $selectedTab) {
                    // TAB 1: Live Services
                    LiveServicesView(
                        onSafetyPrompt: { service, enable in
                            pendingToggleService = service
                            pendingToggleAction = enable
                            showSafetyAlert = true
                        }
                    )
                    .tabItem { Label("Services", systemImage: "cpu") }
                    .tag(0)
                    .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .tabBar)
                    .toolbarBackground(.visible, for: .tabBar)

                    LiveServicesView(criticalOnly: true,
                        onSafetyPrompt: { service, enable in
                            pendingToggleService = service
                            pendingToggleAction = enable
                            showSafetyAlert = true
                        }
                    )
                    .tabItem { Label("Critical", systemImage: "exclamationmark.shield") }
                    .tag(4)
                    .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .tabBar)
                    .toolbarBackground(.visible, for: .tabBar)

                    // TAB 2: Defaults & Presets (Requested by User)
                    DefaultsConfigView()
                        .tabItem { Label("Defaults", systemImage: "slider.horizontal.3") }
                        .tag(1)
                        .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .tabBar)
                        .toolbarBackground(.visible, for: .tabBar)

                    // TAB 3: Config Import & Export
                    ConfigBatchView(showFilePicker: $showFilePicker)
                        .tabItem { Label("Config", systemImage: "doc.text") }
                        .tag(2)
                        .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .tabBar)
                        .toolbarBackground(.visible, for: .tabBar)

                    // TAB 4: Tools & Recovery (From Geranium)
                    ToolsRecoveryView(
                        onResetDefaults: { showResetDefaultsAlert = true },
                        onEmergencyReset: { showEmergencyResetAlert = true }
                    )
                    .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
                    .tag(3)
                    .toolbarBackground(Color(UIColor.secondarySystemBackground), for: .tabBar)
                    .toolbarBackground(.visible, for: .tabBar)
                }
            }
        }
        .sheet(isPresented: $showMemoryDetails) {
            MemoryDetailsView()
                .environmentObject(model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                model.importFile(url: url)
            case .failure(let error):
                model.errorMessage = "Import failed: \(error.localizedDescription)"
            }
        }
        .alert(
            "Service Disable Warning",
            isPresented: $showSafetyAlert,
            presenting: pendingToggleService
        ) { service in
            Button("Proceed Anyway", role: .destructive) {
                model.toggleDaemon(service, enable: pendingToggleAction)
            }
            Button("Cancel", role: .cancel) {
                pendingToggleService = nil
            }
        } message: { service in
            Text("\(service.label)\n\n\(SafetyManager.warning(for: service.label) ?? "Keep this system service enabled.")")
        }
        .alert("Reset Defaults", isPresented: $showResetDefaultsAlert) {
            Button("Reset to Builtin", role: .destructive) {
                presets.resetToBuiltin()
                model.statusMessage = "Target defaults reset to \(DefaultPresets.builtinDefaults.count) builtin presets."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restore \(DefaultPresets.builtinDefaults.count) builtin targets, including \(DefaultPresets.builtinDefaults.values.filter { $0 }.count) default-off entries. Saved custom target choices will be cleared.")
        }
        .alert("Emergency Factory Reset", isPresented: $showEmergencyResetAlert) {
            Button("Reset Launchd State", role: .destructive) {
                model.emergencyResetLaunchd()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This backs up disabled.plist and deletes the disabled launchd database. All system services will return to Apple factory defaults upon reboot.")
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.dismissError() } }
            )
        ) {
            Button("OK", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .statusBarHidden(true)
    }

    private var ramColor: Color {
        switch model.memoryPressure {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        case nil: return .secondary
        }
    }
}

// MARK: - Tab 1: Live Services
struct LiveServicesView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var presets = DefaultPresets.shared
    @State private var searchText = ""
    @State private var filter: FilterType = .all
    var criticalOnly = false
    let onSafetyPrompt: (LaunchdService, Bool) -> Void

    // Membership depends on classification, never the current toggle state.
    private var services: [LaunchdService] {
        let list = criticalOnly ? model.allDaemons.filter { SafetyManager.isCritical($0.label) } : model.allDaemons
        guard criticalOnly else { return list }
        return list.sorted {
            let leftOff = model.isDisabled($0) == true
            let rightOff = model.isDisabled($1) == true
            return leftOff != rightOff ? leftOff : $0.label.localizedStandardCompare($1.label) == .orderedAscending
        }
    }

    enum FilterType: String, CaseIterable {
        case all = "All"
        case active = "Enabled"
        case disabled = "Disabled"
        case mismatch = "Mismatch"
    }

    private var filteredServices: [LaunchdService] {
        var list = services
        if !searchText.isEmpty {
            list = list.filter { $0.label.localizedCaseInsensitiveContains(searchText) }
        }
        switch filter {
        case .all: return list
        case .active: return list.filter { model.isDisabled($0) == false }
        case .disabled: return list.filter { (model.isDisabled($0) ?? false) == true }
        case .mismatch:
            return list.filter { service in
                let targetDisabled = presets.targetState(for: service.label)
                guard let currentlyDisabled = model.isDisabled(service) else { return false }
                return currentlyDisabled != targetDisabled
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar & Filter
            VStack(spacing: 8) {
                if criticalOnly {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Critical services").font(.headline)
                        Text("Keep these core services enabled. Disabling them can break core usage, boot, or stability; expand a service to see its specific warning.")
                            .font(.caption).foregroundColor(.secondary)
                        Text("\(services.filter { model.isDisabled($0) == true }.count) disabled • Disabled entries appear first and stay in this tab.")
                            .font(.caption.weight(.semibold)).foregroundColor(.red)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField(criticalOnly ? "Search critical services..." : "Search daemons...", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(10)

                Picker("Filter", selection: $filter) {
                    ForEach(FilterType.allCases, id: \.self) { f in
                        Text(badgeTitle(for: f)).tag(f)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemBackground))

            // Service List
            if model.isScanningDaemons {
                Spacer()
                ProgressView("Scanning system launchd...")
                Spacer()
            } else if filteredServices.isEmpty {
                Spacer()
                Text("No matching daemons found.")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                Spacer()
            } else {
                List {
                    if criticalOnly {
                        serviceRows(filteredServices)
                    } else {
                        let ordinary = filteredServices.filter { !SafetyManager.isCritical($0.label) }
                        let critical = filteredServices.filter { SafetyManager.isCritical($0.label) }
                        if !ordinary.isEmpty {
                            Section("Non-critical services") { serviceRows(ordinary) }
                        }
                        if !critical.isEmpty {
                            Section("Critical — also in the Critical tab") { serviceRows(critical) }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func serviceRows(_ list: [LaunchdService]) -> some View {
        ForEach(list) { service in
            LiveServiceRow(
                service: service,
                targetDisabled: presets.targetState(for: service.label),
                onToggle: { enable in
                    if !enable && SafetyManager.requiresWarning(service.label) {
                        onSafetyPrompt(service, enable)
                    } else {
                        model.toggleDaemon(service, enable: enable)
                    }
                }
            )
        }
    }

    private func badgeTitle(for f: FilterType) -> String {
        switch f {
        case .all: return "All (\(services.count))"
        case .active:
            let c = services.filter { model.isDisabled($0) == false }.count
            return "On (\(c))"
        case .disabled:
            let c = services.filter { (model.isDisabled($0) ?? false) == true }.count
            return "Off (\(c))"
        case .mismatch:
            let c = services.filter {
                let target = presets.targetState(for: $0.label)
                guard let current = model.isDisabled($0) else { return false }
                return current != target
            }.count
            return "Changes (\(c))"
        }
    }
}

struct LiveServiceRow: View {
    @EnvironmentObject var model: AppModel
    let service: LaunchdService
    let targetDisabled: Bool
    let onToggle: (Bool) -> Void
    @State private var isExpanded = false

    private var isProcessing: Bool { model.isProcessing.contains(service.id) }
    private var currentState: Bool? { model.isDisabled(service) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(SafetyManager.requiresWarning(service.label) ? Color.red :
                                  (currentState == nil ? Color.gray : (currentState == true ? Color.orange : Color.green)))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(service.label)
                                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            ServiceWarningBadge(label: service.label)
                            Text(currentState == nil ? "Loading override state…" :
                                 (currentState == true ? "Disabled override" : "Not disabled by override"))
                                .font(.caption).foregroundColor(.secondary)
                            Text(targetDisabled ? "Default target: Off" : "Default target: On")
                                .font(.caption2)
                                .foregroundColor(currentState == targetDisabled ? .secondary : .orange)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isExpanded ? "Hide" : "Show") details for \(service.label)")

                if isProcessing {
                    ProgressView().frame(width: 44)
                } else {
                    Toggle("Enable \(service.label)", isOn: Binding(
                        get: { currentState != true },
                        set: { onToggle($0) }
                    ))
                    .labelsHidden()
                    .tint(.green)
                    .disabled(!model.canToggle(service))
                }
            }
            if isExpanded {
                ServiceDetailsView(service: service)
                    .padding(.leading, 18)
            }
        }
        .padding(.vertical, 6)
    }
}

struct ServiceWarningBadge: View {
    let label: String
    var body: some View {
        if SafetyManager.warning(for: label) != nil {
            Text(SafetyManager.isCritical(label) ? "⛔ CRITICAL: KEEP ENABLED" : "RECOMMENDED ON")
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .foregroundColor(SafetyManager.isCritical(label) ? .red : .orange)
                .background((SafetyManager.isCritical(label) ? Color.red : Color.orange).opacity(0.12))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Tab 2: Defaults & Presets (Requested by User)
struct DefaultsConfigView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var presets = DefaultPresets.shared
    @State private var searchText = ""
    @State private var filter: DefaultFilter = .all

    enum DefaultFilter: String, CaseIterable {
        case all = "All"
        case disable = "Off"
        case keep = "On"
        case recommended = "Recommended"
    }

    private var presetServices: [LaunchdService] {
        let installed = Set(model.allDaemons.map(\.label))
        let missing = DefaultPresets.builtinDefaults.keys.filter { !installed.contains($0) }
            .map { LaunchdService.unresolved(label: $0) }
        return (model.allDaemons + missing).sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    private var filteredDaemons: [LaunchdService] {
        var list = presetServices
        if !searchText.isEmpty {
            list = list.filter { $0.label.localizedCaseInsensitiveContains(searchText) }
        }
        switch filter {
        case .all: return list
        case .disable: return list.filter { presets.targetState(for: $0.label) == true }
        case .keep: return list.filter { presets.targetState(for: $0.label) == false }
        case .recommended: return list.filter { SafetyManager.recommendation(for: $0.label) != nil }
        }
    }

    private var unoptimizedCount: Int {
        model.allDaemons.filter {
            let target = presets.targetState(for: $0.label)
            guard let current = model.isDisabled($0) else { return false }
            return current != target
        }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Action Card
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default targets")
                            .font(.headline.bold())
                        Text("\(DefaultPresets.builtinDefaults.count) built-in targets • \(unoptimizedCount) pending changes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { model.applyAllDefaults() }) {
                        Label("Apply Defaults", systemImage: "bolt.fill")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(model.isApplyingConfig || model.isRefreshingState || model.isScanningDaemons)
                }

                Text("Built-in defaults are included in the app. Applying targets changes only installed services; entries not found on this device remain available as targets. Restart userspace for full effect.")
                    .font(.caption).foregroundColor(.secondary)
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search preset targets...", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(10)

                Picker("Filter", selection: $filter) {
                    ForEach(DefaultFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))

            // Presets List
            List(filteredDaemons) { service in
                DefaultsRow(service: service)
            }
            .listStyle(.plain)
        }
    }
}

struct DefaultsRow: View {
    @StateObject private var presets = DefaultPresets.shared
    let service: LaunchdService
    @State private var isExpanded = false
    @State private var showCriticalWarning = false

    private var isTargetDisabled: Bool { presets.targetState(for: service.label) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(service.label)
                                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            ServiceWarningBadge(label: service.label)
                            if service.kind == .unresolved {
                                Text("Not found on this device").font(.caption2).foregroundColor(.secondary)
                            }
                            Text(isTargetDisabled ? "Target: Off" : "Target: Keep enabled")
                                .font(.caption).foregroundColor(isTargetDisabled ? .orange : .green)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Toggle("Keep \(service.label) enabled by default", isOn: Binding(
                    get: { !isTargetDisabled },
                    set: { enabled in
                        if !enabled && SafetyManager.isCritical(service.label) {
                            showCriticalWarning = true
                        } else {
                            presets.setTargetState(for: service.label, disable: !enabled)
                        }
                    }
                ))
                .labelsHidden()
                .tint(.green)
            }
            if isExpanded { ServiceDetailsView(service: service) }
        }
        .padding(.vertical, 6)
        .alert("Critical Service Target", isPresented: $showCriticalWarning) {
            Button("Set Target Off", role: .destructive) {
                presets.setTargetState(for: service.label, disable: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(SafetyManager.warning(for: service.label) ?? "Keep this core service enabled.")
        }
    }
}

// MARK: - Tab 3: Config Import & Export
struct ConfigBatchView: View {
    @EnvironmentObject var model: AppModel
    @Binding var showFilePicker: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Import Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Config Import & Apply")
                        .font(.headline)

                    Text("Import custom daemon.cfg files in '<label> yes/no' format. Target states will be parsed and ready for batch application.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button(action: { showFilePicker = true }) {
                            Label("Import File", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        if model.rawConfigContent != nil {
                            Button(action: { model.applyImportedConfig() }) {
                                Label("Apply Config", systemImage: "checkmark.seal.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(model.isApplyingConfig)
                        }
                    }

                    if let path = model.lastImportedConfigPath {
                        Text("Loaded: \(URL(fileURLWithPath: path).lastPathComponent)")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)

                // Export Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Export Configuration")
                        .font(.headline)

                    Text("Export the current saved overrides of all daemons to share or use on other devices.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    if #available(iOS 16.0, *) {
                        ShareLink(
                            item: model.exportCurrentConfig(),
                            subject: Text("daemon.cfg"),
                            message: Text("Exported iOS Daemon Configuration")
                        ) {
                            Label("Export Current State (.cfg)", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)

                // Console / Log View Toggle
                if !model.liveLog.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Execution Log").font(.headline)
                            Spacer()
                            Button("View Full Console") { model.showLogConsole = true }
                                .font(.caption.bold())
                        }
                        Text(model.liveLog.suffix(300))
                            .font(.system(.caption2, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black)
                            .foregroundColor(.green)
                            .cornerRadius(8)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
    }
}

// MARK: - Tab 4: Tools & Recovery (From Geranium)
struct ToolsRecoveryView: View {
    @EnvironmentObject var model: AppModel
    @State private var showBackgroundUI = false
    @State private var showDiskHealth = false
    let onResetDefaults: () -> Void
    let onEmergencyReset: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Fast Actions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Actions")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Button(action: { model.respring() }) {
                            VStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise.circle.fill").font(.title2)
                                Text("Respring").font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)

                        Button(action: { model.userspaceReboot() }) {
                            VStack(spacing: 6) {
                                Image(systemName: "power.circle.fill").font(.title2)
                                Text("Reboot Userspace").font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)

                        Button(action: model.refreshAll) {
                            VStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath.circle.fill").font(.title2)
                                Text("Refresh").font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Background UI").font(.headline)
                    Text("Manage the verified wallpaper host through native launchd overrides. No background killer or periodic polling.")
                        .font(.footnote).foregroundColor(.secondary)
                    Button { showBackgroundUI = true } label: {
                        Label("Background UI", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Disk Health").font(.headline)
                    Text("Read NAND wear and erase-cycle counters from an on-demand sysdiagnose report.")
                        .font(.footnote).foregroundColor(.secondary)
                    Button { showDiskHealth = true } label: {
                        Label("Disk diagnostics", systemImage: "stethoscope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)

                // Safety & Recovery (Geranium feature)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recovery & Reset")
                        .font(.headline)

                    Text("Reset target choices to the \(DefaultPresets.builtinDefaults.count) builtin presets, or recover launchd overrides if services malfunction.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Button(action: onResetDefaults) {
                        Label("Reset Targets to Curated Defaults", systemImage: "arrow.uturn.backward.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive, action: onEmergencyReset) {
                        Label("Emergency Factory Reset (Launchd)", systemImage: "exclamationmark.triangle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)

                // Credentials & Environment
                VStack(alignment: .leading, spacing: 12) {
                    Text("Root Credentials")
                        .font(.headline)

                    HStack {
                        Text("Root Password:")
                            .font(.subheadline)
                        SecureField("Password", text: $model.rootPassword)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.subheadline, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                    }

                    if let warning = model.environmentWarning {
                        Text(warning)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            }
            .padding()
        }
        .sheet(isPresented: $showBackgroundUI) {
            BackgroundUIView().environmentObject(model)
        }
        .sheet(isPresented: $showDiskHealth) {
            DiskHealthView().environmentObject(model)
        }
    }
}

// MARK: - Console Log View
struct ConsoleLogView: View {
    @EnvironmentObject var model: AppModel
    let logText: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Process Output")
                    .font(.caption.monospaced().bold())
                Spacer()
                if #available(iOS 16.0, *) {
                    ShareLink(item: logText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                Button("Dismiss") { model.showLogConsole = false }
                    .font(.caption.bold())
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemBackground))

            ScrollViewReader { proxy in
                ScrollView {
                    Text(logText)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("bottom")
                }
                .background(Color.black)
                .foregroundColor(.green)
                .onChange(of: logText) { _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}
