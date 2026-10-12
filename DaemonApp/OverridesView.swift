import SwiftUI

struct OverridesView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var presets = DefaultPresets.shared

    var body: some View {
        List {
            Section {
                Text("Optional feature hosts can be switched off when unused. These switches save the override and load or unload the tested job immediately. On enables demand launching; it does not keep an idle host running.")
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
                    ForEach(group.labels, id: \.self) { label in
                        if let service = model.allDaemons.first(where: { $0.label == label }) {
                            LiveServiceRow(service: service, targetDisabled: presets.targetState(for: label)) {
                                model.toggleDaemon(service, enable: $0)
                            }
                        } else if model.isScanningDaemons {
                            ProgressView("Finding \(label)…")
                        } else {
                            Text("\(label): not found on this device").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    if group.title == "Screen recording" {
                        Text("Enable both services before using Screen Recording or broadcasting. Camera photos and Camera video recording use separate services.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .task { model.refreshAirDrop() }
    }
}
