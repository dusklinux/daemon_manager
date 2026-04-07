import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var model: AppModel
    @State private var showFilePicker = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                // ROW 1: System Info and Persistent Settings
                HStack(spacing: 8) {
                    Text(model.ramUsageText)
                        .font(.system(.subheadline, design: .monospaced, weight: .bold))
                        .foregroundColor(model.isDarkTheme ? .green : .blue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    Spacer(minLength: 4)
                    
                    if model.rawConfigContent != nil && !model.isApplyingConfig && !model.showLogConsole {
                        Button(action: { model.applyImportedConfig() }) {
                            Label("Apply", systemImage: "checkmark.seal.fill")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.small)
                    }
                    
                    SecureField("Pwd", text: $model.rootPassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 65)
                        .font(.system(.caption, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    
                    Button(action: { model.isDarkTheme.toggle() }) {
                        Image(systemName: model.isDarkTheme ? "sun.max.fill" : "moon.fill")
                            .foregroundColor(.primary)
                    }
                }

                // ROW 2: Primary Controls (Cancel button removed as requested)
                if model.showLogConsole && !model.isApplyingConfig {
                    HStack(spacing: 12) {
                        Button(action: { model.showLogConsole = false; model.dismissError() }) {
                            Label("Dismiss Log", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        
                        if #available(iOS 16.0, *) {
                            ShareLink(item: model.liveLog) {
                                Label("Export Log", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else if !model.isApplyingConfig {
                    HStack(spacing: 12) {
                        Button(action: { showFilePicker = true }) {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)

                        Button(action: { model.resetConfig() }) {
                            Label("Reset", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: model.refreshAll) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                    .font(.system(.subheadline, weight: .semibold))
                }

                // Status Indicator for active processes
                if model.isScanningDaemons || model.isRefreshingState || model.isApplyingConfig {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        
                        if let progressText = model.applyProgressText {
                            Text(progressText)
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .foregroundColor(.secondary)
                        } else if model.isApplyingConfig {
                            Text("Executing as root...")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))

            // Environment Warnings (Script missing, etc.)
            if let warning = model.environmentWarning {
                Text(warning)
                    .font(.footnote)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.2))
            }

            if model.showLogConsole {
                ConsoleLogView(logText: model.liveLog)
            } else {
                TabView {
                    DaemonListView(
                        services: model.configDaemons,
                        emptyMessage: "No config loaded. Import 'daemon.cfg'."
                    )
                    .tabItem { Label("Config", systemImage: "doc.text") }

                    DaemonListView(
                        services: model.allDaemons,
                        emptyMessage: model.isScanningDaemons ? "Scanning launchd..." : "No services found."
                    )
                    .tabItem { Label("Services", systemImage: "cpu") }
                }
            }
        }
        // Combined file importer for daemonmanager or daemon.cfg
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                model.importFile(url: url)
            case .failure(let error):
                model.errorMessage = "Import failed: \(error.localizedDescription)"
            }
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
    }
}

struct ConsoleLogView: View {
    let logText: String
    
    var body: some View {
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

struct DaemonListView: View {
    @EnvironmentObject var model: AppModel
    let services: [LaunchdService]
    let emptyMessage: String
    @State private var searchText = ""
    @State private var filter: FilterType = .all

    enum FilterType: String, CaseIterable {
        case all = "All"
        case enabled = "Enabled"
        case disabled = "Disabled"
    }
    
    private func count(for type: FilterType) -> Int {
        switch type {
        case .all: return services.count
        case .enabled: return services.filter { model.isDisabled($0) == false }.count
        case .disabled: return services.filter { model.isDisabled($0) == true }.count
        }
    }

    private var filteredServices: [LaunchdService] {
        var result = services
        if !searchText.isEmpty {
            result = result.filter { $0.label.localizedCaseInsensitiveContains(searchText) }
        }
        switch filter {
        case .all: break
        case .enabled: result = result.filter { model.isDisabled($0) == false }
        case .disabled: result = result.filter { model.isDisabled($0) == true }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search labels...", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(UIColor.tertiarySystemFill))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.top, 12)

            Picker("Filter", selection: $filter) {
                ForEach(FilterType.allCases, id: \.self) { type in
                    Text("\(type.rawValue) (\(count(for: type)))").tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if services.isEmpty {
                Spacer(); Text(emptyMessage).foregroundColor(.secondary); Spacer()
            } else if filteredServices.isEmpty {
                Spacer(); Text("No matching services.").foregroundColor(.secondary); Spacer()
            } else {
                List(filteredServices) { service in
                    DaemonRow(service: service)
                }
                .listStyle(.plain)
            }
        }
    }
}

struct DaemonRow: View {
    @EnvironmentObject var model: AppModel
    let service: LaunchdService
    @State private var isExpanded = false

    private var isProcessing: Bool { model.isProcessing.contains(service.id) }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { !(model.isDisabled(service) ?? true) },
            set: { newValue in model.toggleDaemon(service, enable: newValue) }
        )
    }

    private var statusColor: Color {
        if let disabled = model.isDisabled(service) { return disabled ? .red : .green }
        return .gray
    }
    
    private var currentState: Bool? {
        guard let disabled = model.isDisabled(service) else { return nil }
        return !disabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Circle().fill(statusColor).frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(service.label)
                            .font(.system(.callout, design: .monospaced))
                            .lineLimit(1)
                        
                        if let targetState = model.targetStates[service.label] {
                            let isMatch = (currentState == targetState)
                            Text(targetState ? "CFG: ON" : "CFG: OFF")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(isMatch ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                .foregroundColor(isMatch ? .green : .orange)
                                .clipShape(Capsule())
                        }
                    }
                    Text(service.metadataText).font(.caption2).foregroundColor(.secondary)
                }

                Spacer()

                if isProcessing {
                    ProgressView().frame(width: 44)
                } else if model.canToggle(service) {
                    Toggle("", isOn: toggleBinding).labelsHidden().tint(.green)
                } else {
                    Image(systemName: "questionmark.circle").foregroundColor(.orange).frame(width: 24)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { isExpanded.toggle() } }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text(DaemonDescriptions.get(for: service.label)).font(.caption).foregroundColor(.secondary)
                    if let path = service.plistPath { Text(path).font(.caption2).foregroundColor(.secondary).textSelection(.enabled) }
                    if let reason = model.toggleUnavailableReason(service) { Text(reason).font(.caption2).foregroundColor(.orange) }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.vertical, 6)
        .disabled(isProcessing)
        .opacity(isProcessing ? 0.6 : 1.0)
    }
}

struct DaemonDescriptions {
    static let dict: [String: String] = [
        "com.apple.tipsd": "Handles Tips content delivery.",
        "com.apple.crash_mover": "Processes background crash logs.",
        "com.apple.powerd": "Core power management (Sensitive).",
        "com.apple.SpringBoard": "Main iOS UI process.",
        "com.apple.searchd": "Search indexing support.",
        "com.apple.wifid": "Core Wi-Fi service."
    ]

    static func get(for label: String) -> String {
        if let desc = dict[label] { return desc }
        if label.localizedCaseInsensitiveContains("accessibility") { return "iOS Accessibility feature support." }
        return "Managed via launchctl wrapper."
    }
}
