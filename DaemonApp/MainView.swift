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

    var body: some View {
        VStack(spacing: 0) {
            // TOP STATUS BAR: RAM Usage & Quick Info
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(ramColor)
                        .frame(width: 10, height: 10)
                    Text(model.ramUsageText)
                        .font(.system(.subheadline, design: .monospaced, weight: .bold))
                        .foregroundColor(ramColor)
                }
                
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

                    // TAB 2: Defaults & Presets (Requested by User)
                    DefaultsConfigView()
                        .tabItem { Label("Defaults", systemImage: "slider.horizontal.3") }
                        .tag(1)

                    // TAB 3: Config Import & Export
                    ConfigBatchView(showFilePicker: $showFilePicker)
                        .tabItem { Label("Config", systemImage: "doc.text") }
                        .tag(2)

                    // TAB 4: Tools & Recovery (From Geranium)
                    ToolsRecoveryView(
                        onResetDefaults: { showResetDefaultsAlert = true },
                        onEmergencyReset: { showEmergencyResetAlert = true }
                    )
                    .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
                    .tag(3)
                }
            }
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
            "Critical Daemon Warning",
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
            Text("WARNING: Disabling \(service.label) is dangerous!\n\n\(SafetyManager.warning(for: service.label) ?? "This is a protected system service.")\n\nAre you sure you want to proceed?")
        }
        .alert("Reset Defaults", isPresented: $showResetDefaultsAlert) {
            Button("Reset to Builtin", role: .destructive) {
                presets.resetToBuiltin()
                model.statusMessage = "Target defaults reset to curated 498 daemon presets."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore all default targets back to the curated daemon.cfg presets (331 RAM-saver targets).")
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
        if model.freeRAMMB > 600 { return .green }
        if model.freeRAMMB > 350 { return .orange }
        return .red
    }
}

// MARK: - Tab 1: Live Services
struct LiveServicesView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var presets = DefaultPresets.shared
    @State private var searchText = ""
    @State private var filter: FilterType = .all
    let onSafetyPrompt: (LaunchdService, Bool) -> Void

    enum FilterType: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case disabled = "Disabled"
        case mismatch = "Mismatch"
    }

    private var filteredServices: [LaunchdService] {
        var list = model.allDaemons
        if !searchText.isEmpty {
            list = list.filter { $0.label.localizedCaseInsensitiveContains(searchText) }
        }
        switch filter {
        case .all: return list
        case .active: return list.filter { (model.isDisabled($0) ?? false) == false }
        case .disabled: return list.filter { (model.isDisabled($0) ?? false) == true }
        case .mismatch:
            return list.filter { service in
                let targetDisabled = presets.targetState(for: service.label)
                let currentlyDisabled = model.isDisabled(service) ?? false
                return currentlyDisabled != targetDisabled
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar & Filter
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search daemons...", text: $searchText)
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
                List(filteredServices) { service in
                    LiveServiceRow(
                        service: service,
                        targetDisabled: presets.targetState(for: service.label),
                        onToggle: { enable in
                            if !enable && SafetyManager.isCritical(service.label) {
                                onSafetyPrompt(service, enable)
                            } else {
                                model.toggleDaemon(service, enable: enable)
                            }
                        }
                    )
                }
                .listStyle(.plain)
            }
        }
    }

    private func badgeTitle(for f: FilterType) -> String {
        switch f {
        case .all: return "All (\(model.allDaemons.count))"
        case .active:
            let c = model.allDaemons.filter { (model.isDisabled($0) ?? false) == false }.count
            return "On (\(c))"
        case .disabled:
            let c = model.allDaemons.filter { (model.isDisabled($0) ?? false) == true }.count
            return "Off (\(c))"
        case .mismatch:
            let c = model.allDaemons.filter {
                let target = presets.targetState(for: $0.label)
                return (model.isDisabled($0) ?? false) != target
            }.count
            return "Opt (\(c))"
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
    private var isCurrentlyDisabled: Bool { model.isDisabled(service) ?? false }
    private var isMatch: Bool { isCurrentlyDisabled == targetDisabled }
    private var isCritical: Bool { SafetyManager.isCritical(service.label) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Circle()
                    .fill(isCritical ? Color.red : (isCurrentlyDisabled ? Color.orange : Color.green))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(service.label)
                            .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        if isCritical {
                            Text("⛔ CRITICAL: DO NOT DISABLE")
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.red.opacity(0.2))
                                .foregroundColor(.red)
                                .clipShape(Capsule())
                        } else {
                            Text(targetDisabled ? "TARGET: OFF" : "TARGET: ON")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(isMatch ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                .foregroundColor(isMatch ? .green : .orange)
                                .clipShape(Capsule())
                        }
                    }

                    Text(service.metadataText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isProcessing {
                    ProgressView().frame(width: 44)
                } else {
                    Toggle("", isOn: Binding(
                        get: { !isCurrentlyDisabled },
                        set: { onToggle($0) }
                    ))
                    .labelsHidden()
                    .tint(isCritical ? .orange : .green)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { isExpanded.toggle() } }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if isCritical {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.octagon.fill").foregroundColor(.red)
                            Text("CRITICAL: \(SafetyManager.warning(for: service.label) ?? "Core system daemon. Disabling will cause bootloop, CPU spikes, or loss of device access.")")
                                .font(.caption2.bold())
                                .foregroundColor(.red)
                        }
                        .padding(6)
                        .background(Color.red.opacity(0.12))
                        .cornerRadius(6)
                    } else if let warn = SafetyManager.warning(for: service.label) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                            Text(warn).font(.caption2.bold()).foregroundColor(.orange)
                        }
                    }
                    Text(DaemonDescriptions.get(for: service.label))
                        .font(.caption)
                        .foregroundColor(.primary)
                    if let path = service.plistPath {
                        Text(path).font(.caption2).foregroundColor(.secondary).textSelection(.enabled)
                    }
                }
                .padding(.leading, 20)
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 4)
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
        case disable = "Disable (RAM)"
        case keep = "Keep Active"
    }

    private var filteredDaemons: [LaunchdService] {
        var list = model.allDaemons
        if !searchText.isEmpty {
            list = list.filter { $0.label.localizedCaseInsensitiveContains(searchText) }
        }
        switch filter {
        case .all: return list
        case .disable: return list.filter { presets.targetState(for: $0.label) == true }
        case .keep: return list.filter { presets.targetState(for: $0.label) == false }
        }
    }

    private var unoptimizedCount: Int {
        model.allDaemons.filter {
            let target = presets.targetState(for: $0.label)
            return (model.isDisabled($0) ?? false) != target
        }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Action Card
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Target RAM Presets")
                            .font(.headline.bold())
                        Text("\(model.allDaemons.count) daemons • \(unoptimizedCount) pending optimization")
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
                    .disabled(model.isApplyingConfig)
                }

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

    private var isCritical: Bool { SafetyManager.isCritical(service.label) }
    private var isTargetDisabled: Bool {
        presets.targetState(for: service.label)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(service.label)
                            .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                            .lineLimit(1)

                        if isCritical {
                            Text("⛔ CRITICAL")
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.red.opacity(0.2))
                                .foregroundColor(.red)
                                .clipShape(Capsule())
                        }
                    }

                    Text(isTargetDisabled ? "Target: Disabled (RAM Saver)" : "Target: Keep Active")
                        .font(.caption2)
                        .foregroundColor(isTargetDisabled ? (isCritical ? .red : .orange) : .green)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { !isTargetDisabled },
                    set: { presets.setTargetState(for: service.label, disable: !$0) }
                ))
                .labelsHidden()
                .tint(isCritical ? .orange : .green)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { isExpanded.toggle() } }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if isCritical {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.octagon.fill").foregroundColor(.red)
                            Text("CRITICAL: \(SafetyManager.warning(for: service.label) ?? "Core system service. Must remain enabled.")")
                                .font(.caption2.bold())
                                .foregroundColor(.red)
                        }
                        .padding(6)
                        .background(Color.red.opacity(0.12))
                        .cornerRadius(6)
                    }
                    Text(DaemonDescriptions.get(for: service.label))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let path = service.plistPath {
                        Text(path).font(.caption2).foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
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

                    Text("Export the current running state of all daemons to share or use on other devices.")
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

                // Safety & Recovery (Geranium feature)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recovery & Reset")
                        .font(.headline)

                    Text("Reset your targets back to the curated 498-daemon presets, or perform an emergency recovery if any services malfunction.")
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
