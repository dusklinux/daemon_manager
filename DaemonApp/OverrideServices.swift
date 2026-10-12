import Foundation

struct OverrideGroup: Identifiable {
    let title: String
    let labels: [String]
    var dependencies: [String] = []
    var note: String = ""
    var controlsAirDrop = false
    var id: String { title }

    var allLabels: [String] {
        var seen = Set<String>()
        return (labels + dependencies).filter { seen.insert($0).inserted }
    }

    func actionLabels(enable: Bool) -> [String] {
        enable ? allLabels : allLabels.filter { labels.contains($0) && !SafetyManager.isCritical($0) }
    }
}

enum OverrideServices {
    // Core OS services are assumed available; these are feature-specific jobs
    // and known shared prerequisites, not a complete OS dependency graph.
    static let groups = [
        OverrideGroup(title: "Wallpaper", labels: ["com.apple.PosterBoard", "com.apple.PaperBoard"], note: "Controls wallpaper and Lock Screen hosts. Display or editing can be unavailable while off."),
        OverrideGroup(title: "Accessibility and captions", labels: ["com.apple.AccessibilityUIServer", "com.apple.livetranscriptionui"], note: "Hosts accessibility interfaces and Live Captions on supported devices."),
        OverrideGroup(title: "AirDrop", labels: ["com.apple.sharing.airdropui"], dependencies: ["com.apple.sharingd", "com.apple.pluginkit.pkd"], note: "On/Off also changes Allow AirDrop for sending and receiving. Shared sharingd and pkd remain enabled for other app extensions and sharing.", controlsAirDrop: true),
        OverrideGroup(title: "Wallet", labels: ["com.apple.PassbookUISceneService", "com.apple.passd"], note: "Wallet interface and pass backend; Apple Pay or passes can be unavailable while off."),
        OverrideGroup(title: "Shortcuts", labels: ["com.apple.ShortcutsUI", "com.apple.linkd"], dependencies: ["com.apple.siriactionsd", "com.apple.pluginkit.pkd"], note: "Includes interactive UI and the app-action broker. Apple’s Set Flashlight action passed testing; the WhatsApp Meta AI action remains unresolved. Restart userspace after group changes."),
        OverrideGroup(title: "Screen recording", labels: ["com.apple.replaykitangel", "com.apple.replayd"], note: "Enable both, then respring before recording: SpringBoard retained a broken connection until respring in device tests. Screen capture/broadcast is separate from Camera photos and videos."),
        OverrideGroup(title: "Widget updates and Live Activities", labels: ["com.apple.chronod", "com.apple.liveactivitiesd"], dependencies: ["com.apple.pluginkit.pkd"], note: "Stops these update jobs; does not remove configured widgets or disable every legacy widget path. Keep pkd on to avoid the reproduced CPU loop."),
        OverrideGroup(title: "Apple Account and settings sync", labels: ["com.apple.appleaccountd", "com.apple.amsaccountsd", "com.apple.cloudsettingssyncagent", "com.apple.cloudd"], dependencies: ["com.apple.accountsd", "com.apple.akd", "com.apple.adid", "com.apple.syncdefaultsd", "com.apple.apsd"], note: "Account/authentication and optional media, CloudKit and settings sync. Group Off preserves Critical account/authentication services. Service roles were checked; account sign-in was not tested. Restart userspace after changes."),
        OverrideGroup(title: "Messages and FaceTime", labels: ["com.apple.imagent", "com.apple.identityservicesd", "com.apple.avconferenced"], dependencies: ["com.apple.nehelper", "com.apple.apsd", "com.apple.accountsd", "com.apple.akd"], note: "Messaging identities and audio/video calls. Nehelper restored Messages in device tests; FaceTime calls were not tested. Restart userspace after changes."),
        OverrideGroup(title: "iCloud Drive", labels: ["com.apple.bird", "com.apple.cloudd"], dependencies: ["com.apple.FileProvider", "com.apple.accountsd", "com.apple.akd"], note: "CloudDocs and CloudKit sync. Shared FileProvider remains available for local Files and sharing. Sync was not tested. Restart userspace after changes."),
        OverrideGroup(title: "iCloud Photos", labels: ["com.apple.cloudphotod", "com.apple.assetsd.nebulad"], dependencies: ["com.apple.assetsd", "com.apple.cloudd", "com.apple.accountsd", "com.apple.akd"], note: "Photos cloud-sync jobs; shared Photos storage remains available for local capture. Cloud sync was not tested. Restart userspace after changes."),
        OverrideGroup(title: "App Store and media purchases", labels: ["com.apple.appstored", "com.apple.appstorecomponentsd", "com.apple.itunesstored", "com.apple.amsaccountsd"], dependencies: ["com.apple.accountsd", "com.apple.akd", "com.apple.adid"], note: "Store downloads and media accounts, separate from TrollStore installation. Purchases/downloads were not tested. Restart userspace after changes."),
        OverrideGroup(title: "Contacts and calendars", labels: ["com.apple.contactsd", "com.apple.calaccessd", "com.apple.dataaccess.dataaccessd"], dependencies: ["com.apple.accountsd"], note: "Address book, calendar access and configured account sync. Disabling affects apps using these stores; sync was not tested. Restart userspace after changes.")
    ]
    // Only these jobs passed live load/unload round trips. Other groups save
    // overrides and require userspace restart, without hot-unloading dependencies.
    static let labels: Set<String> = [
        "com.apple.PosterBoard", "com.apple.PaperBoard", "com.apple.AccessibilityUIServer",
        "com.apple.livetranscriptionui", "com.apple.sharing.airdropui", "com.apple.PassbookUISceneService",
        "com.apple.ShortcutsUI", "com.apple.replaykitangel", "com.apple.replayd",
        "com.apple.chronod", "com.apple.liveactivitiesd"
    ]
}
