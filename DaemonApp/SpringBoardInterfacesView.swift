import SwiftUI

struct SpringBoardInterfacesView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    private let features: [(String, String, String)] = [
        ("controlCenter", "Control Center", "Disables presentation and its opening gesture. Shared networking, audio and device services remain available."),
        ("appLibrary", "App Library", "Disables the App Library interface. Installed apps remain installed; use Home or Spotlight to open them.")
    ]

    var body: some View {
        List {
            Section {
                Text("On enables an interface; Off disables its access as described below. Respring after changing settings. These are SpringBoard controls, not separate daemons. No measured RAM saving is promised.")
                    .font(.caption).foregroundColor(.secondary)
                if let state = model.springBoardUIState {
                    Text(state.pending ? "Changes pending respring" : state.installed ? "Applied" : "Companion not installed")
                        .font(.caption).foregroundColor(state.pending ? .orange : .secondary)
                    if !state.installed {
                        Button("Install interface controls") { model.setSpringBoardInterfaces(disabled: false) }
                    }
                }
                HStack {
                    Button("All On") { model.setSpringBoardInterfaces(disabled: false) }
                    Button("All Off") { model.setSpringBoardInterfaces(disabled: true) }
                }.buttonStyle(.bordered)
            }
            Section("Interfaces") {
                ForEach(features, id: \.0) { key, title, description in
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(title, isOn: Binding(
                            get: { !(model.springBoardUIState?.saved[key] ?? false) },
                            set: { model.setSpringBoardInterface(key, disabled: !$0) }
                        ))
                        Text(description).font(.caption).foregroundColor(.secondary)
                        if let runtime = model.springBoardUIState?.runtime, runtime.supported[key] != true {
                            Text("Hook unavailable on this build").font(.caption).foregroundColor(.orange)
                        }
                    }
                }
            }
            Section {
                Text("Today View remains available: its tested disable hooks did not remove the page on this phone. Turning off widget-update daemons does not remove it. Keep pkd enabled for app extensions.")
                    .font(.caption).foregroundColor(.secondary)
                Button("Respring") { model.respring() }
                Button("Refresh applied state") { model.refreshSpringBoardUI() }
                Button("Remove interface controls") { model.removeSpringBoardUI() }
                if let error = model.springBoardUIError { Text(error).font(.caption).foregroundColor(.red) }
            }
        }
        .disabled(model.isApplyingConfig || model.isDiagnosingDisk || model.isChangingAirDrop ||
                  !model.isProcessing.isEmpty || model.isScanningDaemons || model.isRefreshingState)
        .navigationTitle("SpringBoard interfaces")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.refreshSpringBoardUI() }
        .onChange(of: scenePhase) { phase in if phase == .active { model.refreshSpringBoardUI() } }
    }
}
