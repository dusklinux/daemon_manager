import SwiftUI

struct BackgroundUIView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var presets = DefaultPresets.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("This page manages the wallpaper host, not arbitrary apps. Disabling saves a persistent launchd override. Restart userspace to fully stop its loaded process and extensions.")
                        .font(.subheadline)
                    Text("Wallpaper and Lock Screen customization can stop working. Re-enable it and restart userspace to restore them. The app does not run a background kill loop.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("Wallpaper host") {
                    if let service = model.allDaemons.first(where: { $0.label == "com.apple.PosterBoard" }) {
                        LiveServiceRow(service: service, targetDisabled: presets.targetState(for: service.label)) {
                            model.toggleDaemon(service, enable: $0)
                        }
                    } else if model.isScanningDaemons {
                        ProgressView("Finding background UI jobs…")
                    } else {
                        Text("PosterBoard was not found on this device.").foregroundColor(.secondary)
                    }
                }
                Section("System animations") {
                    if let disabled = model.animationsDisabled {
                        Toggle("Disable system animations", isOn: Binding(
                            get: { disabled }, set: { model.manageAnimations(disable: $0) }))
                    }
                    if model.isChangingAnimations { ProgressView("Reading animation control…") }
                    if let error = model.animationControlError { Text(error).foregroundColor(.orange) }
                    Text("Uses the optional NoAnimationsX 1.2 rootless tweak to suppress SpringBoard animation actions. Respring after changing the switch. It does not change animation speed or animations inside other apps. Coverage depends on the system transition; verify app opening/closing and the switcher on your device.")
                        .font(.caption).foregroundColor(.secondary)
                    Link("Developer repository (for Sileo)", destination: URL(string: "https://repo.icrazeios.com/")!)
                }
                .disabled(model.isChangingAnimations || model.isDiagnosingDisk)
                Section("Cache and compression") {
                    Text("Speculative pages are reclaimable filesystem cache managed by the kernel. They are not a SysMain service, and clearing them is not a lasting RAM saving.")
                    Text("iOS compresses memory automatically. There is no verified, useful force-compress control here; intentionally creating pressure could evict apps and add CPU work.")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Background UI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .task { model.manageAnimations() }
    }
}
