import SwiftUI

struct OverridesView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var presets = DefaultPresets.shared
    let onSafetyPrompt: (LaunchdService, Bool) -> Void

    var body: some View {
        List {
            Section {
                Text("Group On enables listed feature services and shared dependencies. Group Off preserves Critical services and shared dependencies. Shared jobs appear in more than one group; changing one affects every group using it. Status reflects saved overrides. On allows demand launching; it does not keep idle jobs running. Broader account/sync groups require userspace restart and are not fully feature-tested.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("AirDrop sending and receiving") {
                Toggle("Allow AirDrop", isOn: Binding(
                    get: { model.airDropAllowed ?? false },
                    set: { model.setAirDropAllowed($0) }
                ))
                .disabled(model.airDropAllowed == nil || model.isChangingAirDrop || model.isApplyingConfig || model.isDiagnosingDisk)
                if model.isChangingAirDrop { ProgressView("Updating AirDrop…") }
                Text("Disables AirDrop through its system feature setting, while keeping the normal Share Sheet available. The interface host below is separately switchable.")
                    .font(.caption).foregroundColor(.secondary)
                if let error = model.airDropError { Text(error).font(.caption).foregroundColor(.red) }
                Button("Refresh AirDrop state") { model.refreshAirDrop() }
                    .disabled(model.isChangingAirDrop || model.isApplyingConfig || model.isDiagnosingDisk)
            }
            ForEach(OverrideServices.groups) { group in
                Section(group.title) {
                    Text(group.note).font(.caption).foregroundColor(.secondary)
                    HStack {
                        Text(groupState(group)).font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Button("On") { model.applyFeatureGroup(group, enable: true) }
                        Button("Off") { model.applyFeatureGroup(group, enable: false) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isApplyingConfig || model.isDiagnosingDisk || model.isChangingAirDrop || !model.isProcessing.isEmpty || model.isScanningDaemons || model.isRefreshingState)
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
            }
        }
        .listStyle(.insetGrouped)
        .task { model.refreshAirDrop() }
    }

    private func groupState(_ group: OverrideGroup) -> String {
        let services = model.allDaemons.filter { group.allLabels.contains($0.label) }
        if Set(services.map(\.label)).count != group.allLabels.count { return "Some services not found" }
        let states = services.compactMap { model.isDisabled($0) }
        guard !states.isEmpty, states.count == services.count else { return "State unavailable" }
        if group.controlsAirDrop, model.airDropAllowed == nil { return "AirDrop state unavailable" }
        if states.allSatisfy({ !$0 }) && (!group.controlsAirDrop || model.airDropAllowed == true) { return "On" }
        let features = services.filter { group.actionLabels(enable: false).contains($0.label) }
        if !features.isEmpty, features.allSatisfy({ model.isDisabled($0) == true }),
           !group.controlsAirDrop || model.airDropAllowed == false { return "Feature off; dependencies preserved" }
        return "Mixed"
    }
}
