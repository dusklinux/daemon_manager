import SwiftUI

struct OverridesView: View {
    @EnvironmentObject var model: AppModel
    let onSafetyPrompt: (LaunchdService, Bool) -> Void

    var body: some View {
        NavigationStack {
            List(OverrideServices.groups) { group in
                NavigationLink {
                    OverrideGroupView(group: group, onSafetyPrompt: onSafetyPrompt)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title)
                        Text(overrideGroupState(group, model: model))
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Overrides")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct OverrideGroupView: View {
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
                    Text(overrideGroupState(group, model: model)).font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("On") { model.applyFeatureGroup(group, enable: true) }
                    Button("Off") { model.applyFeatureGroup(group, enable: false) }
                        .disabled(group.actionLabels(enable: false).isEmpty)
                }
                .buttonStyle(.bordered)
                .disabled(busy)
                Text("On enables the listed feature services and prerequisites. Off preserves Critical services and prerequisite-only jobs. Shared jobs also affect other groups. Status shows saved overrides, not a completed feature test.")
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
                ForEach(group.allLabels, id: \.self) { label in
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

private func overrideGroupState(_ group: OverrideGroup, model: AppModel) -> String {
    let services = model.allDaemons.filter { group.allLabels.contains($0.label) }
    if Set(services.map(\.label)).count != group.allLabels.count { return "Some services not found" }
    let states = services.compactMap { model.isDisabled($0) }
    guard !states.isEmpty, states.count == services.count else { return "State unavailable" }
    if group.controlsAirDrop, model.airDropAllowed == nil { return "AirDrop state unavailable" }
    if states.allSatisfy({ !$0 }) && (!group.controlsAirDrop || model.airDropAllowed == true) { return "On" }
    let features = services.filter { group.actionLabels(enable: false).contains($0.label) }
    if !features.isEmpty, features.allSatisfy({ model.isDisabled($0) == true }),
       !group.controlsAirDrop || model.airDropAllowed == false { return "Feature off" }
    return "Mixed"
}
