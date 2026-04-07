import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var model: AppModel
    @State private var showFilePicker = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                HStack {
                    Text(model.ramUsageText)
                        .font(.system(.subheadline, design: .monospaced, weight: .bold))
                        .foregroundColor(model.isDarkTheme ? .green : .blue)
                    
                    Spacer()
                    
                    Button(action: { model.isDarkTheme.toggle() }) {
                        Image(systemName: model.isDarkTheme ? "sun.max.fill" : "moon.fill")
                            .foregroundColor(.primary)
                            .imageScale(.large)
                    }
                }

                HStack(spacing: 12) {
                    Button(action: { showFilePicker = true }) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isApplyingConfig)

                    // FIX: Dynamic Cancel -> Dismiss State Machine
                    if model.isApplyingConfig {
                        Button(action: {
                            if model.isApplyFinished {
                                model.dismissLog()
                            } else {
                                model.cancelApply()
                            }
                        }) {
                            Label(model.isApplyFinished ? "Dismiss" : "Cancel", systemImage: model.isApplyFinished ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(model.isApplyFinished ? .blue : .red)
                    } else if model.rawConfigContent != nil {
                        Button(action: { model.applyImportedConfig() }) {
                            Label("Apply", systemImage: "checkmark.seal.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }

                    Button(action: model.refreshAll) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isApplyingConfig)
                }

                if model.isScanningDaemons || model.isRefreshingState || model.isApplyingConfig {
                    HStack(spacing: 8) {
                        if !model.isApplyFinished {
                            ProgressView()
                                .controlSize(.small)
                        }
                        
                        if let progressText = model.applyProgressText {
                            Text(progressText)
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))

            if let warning = model.environmentWarning {
                Text(warning)
                    .font(.footnote)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.2))
            }

            if model.isApplyingConfig {
                ConsoleLogView(logText: model.liveLog)
            } else {
                TabView {
                    DaemonListView(
                        services: model.configDaemons,
                        emptyMessage: "No config loaded. Tap 'Import'."
                    )
                    .tabItem { Label("Config", systemImage: "doc.text") }

                    DaemonListView(
                        services: model.allDaemons,
                        emptyMessage: model.isScanningDaemons ? "Scanning launchd plist directories..." : "No launchd services found."
                    )
                    .tabItem { Label("Services", systemImage: "cpu") }
                }
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                model.importConfig(url: url)
            case .failure(let error):
                model.errorMessage = "File import failed: \(error.localizedDescription)"
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
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
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
                Spacer()
                Text(emptyMessage).foregroundColor(.secondary)
                Spacer()
            } else if filteredServices.isEmpty {
                Spacer()
                Text("No matching services.").foregroundColor(.secondary)
                Spacer()
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
                            .truncationMode(.middle)
                        
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

                    Text(service.metadataText)
                        .font(.caption2).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
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
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }

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
        "com.apple.tipsd": "Handles Tips content and related suggestion delivery.",
        "com.apple.crash_mover": "Moves or processes crash logs in the background.",
        "com.apple.powerd": "Core power-management service. Disabling it can destabilize the device.",
        "com.apple.SpringBoard": "Main iOS shell and UI process. Disabling it can break the interface.",
        "com.apple.searchd": "Supports search indexing and related queries.",
        "com.apple.wifid": "Core Wi-Fi service. Disabling it can break wireless connectivity."
    ]

    static func get(for label: String) -> String {
        if let description = dict[label] { return description }
        if label.localizedCaseInsensitiveContains("accessibility") { return "Related to iOS accessibility features." }
        return "Toggles launchd disabled-state through the external wrapper script."
    }
}
