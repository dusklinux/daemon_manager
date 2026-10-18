import SwiftUI

struct FeatureGroupsView: View {
    @EnvironmentObject var model: AppModel
    @State private var selecting = false
    @State private var selected: Set<String> = []
    let onSafetyPrompt: (LaunchdService, Bool) -> Void

    private var busy: Bool {
        model.isApplyingConfig || model.isDiagnosingDisk || model.isChangingAirDrop ||
        !model.isProcessing.isEmpty || model.isScanningDaemons || model.isRefreshingState
    }

    private func applySelection(enable: Bool) {
        model.applyFeatureGroups(OverrideServices.groups.filter { selected.contains($0.id) },
                                 enable: enable,
                                 includeSpringBoardInterfaces: selected.contains(OverrideServices.springBoardInterfacesTitle))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(OverrideServices.menuTitles, id: \.self) { title in
                    HStack(spacing: 8) {
                        if selecting {
                            Button {
                                if !selected.insert(title).inserted { selected.remove(title) }
                            } label: {
                                Image(systemName: selected.contains(title) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Select \(title)")
                            .accessibilityValue(selected.contains(title) ? "Selected" : "Not selected")
                        }
                        if title == OverrideServices.springBoardInterfacesTitle {
                            NavigationLink(title) { SpringBoardInterfacesView() }
                            if !selecting {
                                Button("On") { model.setSpringBoardInterfaces(disabled: false) }.buttonStyle(.bordered)
                                Button("Off") { model.setSpringBoardInterfaces(disabled: true) }.buttonStyle(.bordered)
                            }
                        } else if let group = OverrideServices.groups.first(where: { $0.id == title }) {
                            NavigationLink {
                                FeatureGroupView(group: group, onSafetyPrompt: onSafetyPrompt)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.title)
                                    Text(featureGroupState(group, model: model))
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                            if !selecting {
                                Button("On") { model.applyFeatureGroup(group, enable: true) }.buttonStyle(.bordered)
                                Button("Off") { model.applyFeatureGroup(group, enable: false) }
                                    .buttonStyle(.bordered)
                                    .disabled(group.actionLabels(enable: false).isEmpty)
                            }
                        }
                    }
                    .disabled(busy)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Feature Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if selecting {
                        Button(selected.count == OverrideServices.menuTitles.count ? "Clear" : "Select All") {
                            selected = selected.count == OverrideServices.menuTitles.count ? [] : Set(OverrideServices.menuTitles)
                        }
                        .disabled(busy)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(selecting ? "Done" : "Select") {
                        selecting.toggle()
                        if !selecting { selected.removeAll() }
                    }
                    .disabled(busy)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    HStack {
                        Text("\(selected.count) selected").font(.subheadline)
                        Spacer()
                        Button("On") { applySelection(enable: true) }
                        Button("Off") { applySelection(enable: false) }
                    }
                    .buttonStyle(.bordered)
                    .padding()
                    .background(.bar)
                    .disabled(selected.isEmpty || busy)
                }
            }
        }
    }
}

private struct FeatureGroupView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var presets = DefaultPresets.shared
    let group: OverrideGroup
    let onSafetyPrompt: (LaunchdService, Bool) -> Void

    private var busy: Bool {
        model.isApplyingConfig || model.isDiagnosingDisk || model.isChangingAirDrop ||
        !model.isProcessing.isEmpty || model.isScanningDaemons || model.isRefreshingState
    }

    var body: some View {
        List {
            Section {
                Text(group.note).font(.caption).foregroundColor(.secondary)
                HStack {
                    Text(featureGroupState(group, model: model)).font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("On") { model.applyFeatureGroup(group, enable: true) }
                    Button("Off") { model.applyFeatureGroup(group, enable: false) }
                        .disabled(group.actionLabels(enable: false).isEmpty)
                }
                .buttonStyle(.bordered)
                .disabled(busy)
                Text("On enables listed services and prerequisites. Critical services are managed in the Critical tab. Off preserves prerequisite-only jobs. Recommended On services remain switchable; disabling them can remove functionality used by other groups. Status shows the listed service settings, not a completed feature test.")
                    .font(.caption).foregroundColor(.secondary)
            }
            if group.controlsAirDrop {
                Section("AirDrop sending and receiving") {
                    Toggle("Allow AirDrop", isOn: Binding(
                        get: { model.airDropAllowed ?? false },
                        set: { model.setAirDropAllowed($0) }
                    ))
                    .disabled(model.airDropAllowed == nil || busy)
                    if model.isChangingAirDrop { ProgressView("Updating AirDrop…") }
                    Text("Blocks AirDrop sending and receiving while keeping the normal Share Sheet available. The interface host is separately switchable below.")
                        .font(.caption).foregroundColor(.secondary)
                    if let error = model.airDropError { Text(error).font(.caption).foregroundColor(.red) }
                    Button("Refresh AirDrop state") { model.refreshAirDrop() }.disabled(busy)
                }
            }
            Section("Services") {
                ForEach(group.visibleLabels, id: \.self) { label in
                    if let service = model.allDaemons.first(where: { $0.label == label }) {
                        LiveServiceRow(service: service, targetDisabled: presets.targetState(for: label)) {
                            if !$0 && SafetyManager.requiresWarning(service.label) { onSafetyPrompt(service, $0) }
                            else { model.toggleDaemon(service, enable: $0) }
                        }
                    } else if model.isScanningDaemons {
                        ProgressView("Finding \(label)…")
                    } else {
                        Text("\(label): not found on this device").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            Section("Apply process changes") {
                Button("Respring") { model.respring() }.disabled(busy)
                Button("Restart userspace") { model.userspaceReboot() }.disabled(busy)
                Text("Restoring a feature can require a respring to replace stale UI connections. Broader account/sync groups require a userspace restart. Both interrupt the current app session.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if group.controlsAirDrop { model.refreshAirDrop() } }
    }
}

private func featureGroupState(_ group: OverrideGroup, model: AppModel) -> String {
    let labels = Set(group.visibleLabels)
    let services = model.allDaemons.filter { labels.contains($0.label) }
    if Set(services.map(\.label)).count != labels.count { return "Some services not found" }
    let states = services.compactMap { model.isDisabled($0) }
    guard !states.isEmpty, states.count == services.count else { return "State unavailable" }
    if group.controlsAirDrop, model.airDropAllowed == nil { return "AirDrop state unavailable" }
    if states.allSatisfy({ !$0 }) && (!group.controlsAirDrop || model.airDropAllowed == true) { return "On" }
    let features = services.filter { group.actionLabels(enable: false).contains($0.label) }
    if !features.isEmpty, features.allSatisfy({ model.isDisabled($0) == true }),
       !group.controlsAirDrop || model.airDropAllowed == false { return "Feature off" }
    return "Mixed"
}
