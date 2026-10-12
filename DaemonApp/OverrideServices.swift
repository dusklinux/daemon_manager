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
        OverrideGroup(title: "Wallet", labels: ["com.apple.PassbookUISceneService", "com.apple.passd"], note: "Wallet interface and shared PassKit backend. Group Off disables the interface but preserves Critical passd because the tested App Store free-app confirmation also needs it. Individual passd disabling remains available. Apple Pay and Wallet passes were not tested."),
        OverrideGroup(title: "Shortcuts", labels: ["com.apple.ShortcutsUI", "com.apple.linkd"], dependencies: ["com.apple.siriactionsd", "com.apple.pluginkit.pkd"], note: "Includes interactive UI and the app-action broker. Apple’s Set Flashlight action passed testing; the WhatsApp Meta AI action remains unresolved. Restart userspace after group changes."),
        OverrideGroup(title: "Screen recording", labels: ["com.apple.replaykitangel", "com.apple.replayd"], note: "Enable both, then respring before recording: SpringBoard retained a broken connection until respring in device tests. Screen capture/broadcast is separate from Camera photos and videos."),
        OverrideGroup(title: "Widget updates and Live Activities", labels: ["com.apple.chronod", "com.apple.liveactivitiesd"], dependencies: ["com.apple.pluginkit.pkd"], note: "Stops these update jobs; does not remove configured widgets or disable every legacy widget path. Keep pkd on to avoid the reproduced CPU loop."),
        OverrideGroup(title: "Apple Account and settings sync", labels: ["com.apple.appleaccountd", "com.apple.amsaccountsd", "com.apple.cloudsettingssyncagent", "com.apple.cloudd"], dependencies: ["com.apple.accountsd", "com.apple.akd", "com.apple.adid", "com.apple.absd", "com.apple.cdpd", "com.apple.followupd", "com.apple.identityservicesd", "com.apple.imagent", "com.apple.syncdefaultsd", "com.apple.apsd", "com.apple.protectedcloudstorage.protectedcloudkeysyncing", "com.apple.SecureBackupDaemon"], note: "Full Apple Account sign-in passed on the test phone with the listed authentication jobs restored, including imagent for SMS codes, and a userspace restart. The final cdpd/followupd/Identity Services set was tested together, not individually isolated. Group Off preserves Critical authentication jobs. Cloud sync needs separate verification. Restart userspace after changes."),
        OverrideGroup(title: "Messages and FaceTime", labels: ["com.apple.imagent", "com.apple.identityservicesd", "com.apple.avconferenced"], dependencies: ["com.apple.nehelper", "com.apple.apsd", "com.apple.accountsd", "com.apple.akd"], note: "Restoring imagent plus respring restored carrier SMS verification delivery. Group Off preserves imagent and Identity Services for SMS/account setup; their individual switches remain available. Nehelper restored Messages in earlier tests; FaceTime calls remain untested. Restart userspace after changes."),
        OverrideGroup(title: "iCloud Drive", labels: ["com.apple.bird", "com.apple.cloudd"], dependencies: ["com.apple.FileProvider", "com.apple.accountsd", "com.apple.akd", "com.apple.protectedcloudstorage.protectedcloudkeysyncing", "com.apple.SecureBackupDaemon"], note: "CloudDocs and CloudKit sync. Shared FileProvider remains available for local Files and sharing. Restoring the protected-key and secure-backup prerequisites repaired key recovery in logs; end-to-end file sync remains under investigation. Complete any Settings account verification and restart userspace after changes."),
        OverrideGroup(title: "Photos sharing and export", labels: ["com.apple.photos.ImageConversionService", "com.apple.photos.VideoConversionService"], dependencies: ["com.apple.assetsd", "com.apple.pluginkit.pkd", "com.apple.sharingd"], note: "Restoring ImageConversionService and respringing repaired Photos → WhatsApp image export. Restoring VideoConversionService separately and respringing then repaired the Camera video test. Both are Critical: group Off preserves them, so the group Off button is unavailable. Use individual switches when deliberately disabling export. Camera capture is separate from sharing conversion. Restart userspace after group changes."),
        OverrideGroup(title: "iCloud Photos", labels: ["com.apple.cloudphotod", "com.apple.assetsd.nebulad"], dependencies: ["com.apple.assetsd", "com.apple.cloudd", "com.apple.accountsd", "com.apple.akd", "com.apple.protectedcloudstorage.protectedcloudkeysyncing", "com.apple.SecureBackupDaemon"], note: "Photos cloud-sync jobs; shared Photos storage remains available for local capture. Restoring the protected-key and secure-backup prerequisites repaired key recovery in logs; end-to-end photo sync remains under investigation. Complete any Settings account verification and restart userspace after changes."),
        OverrideGroup(title: "App Store and media purchases", labels: ["com.apple.appstored", "com.apple.appstorecomponentsd", "com.apple.itunesstored", "com.apple.amsaccountsd", "com.apple.amsengagementd"], dependencies: ["com.apple.accountsd", "com.apple.akd", "com.apple.adid", "com.apple.passd", "com.apple.storekitd"], note: "Store downloads and media accounts, separate from TrollStore installation. Restoring passd and respringing repaired a free-app download, installation and launch. A second new free app also passed after amsengagementd was turned back off; it remains optional for other Media Services prompts. Group Off preserves Critical passd. Paid purchases remain untested. Restart userspace after changes."),
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
