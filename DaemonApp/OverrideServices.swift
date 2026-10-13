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
        OverrideGroup(title: "Wallpaper", labels: ["com.apple.PosterBoard", "com.apple.PaperBoard"], note: "Controls wallpaper and Lock Screen hosts. PosterBoard is also required for the tested Lock Screen media controls. Group Off can break their rendering even with liveactivitiesd on. Restart userspace after changes."),
        OverrideGroup(title: "Lock Screen media controls", labels: ["com.apple.PosterBoard", "com.apple.liveactivitiesd"], note: "Both default Off and remain freely switchable. On restores the tested Lock Screen and Notification Center playback panel; Off disables both hosts. liveactivitiesd also supports Live Activities, and PosterBoard is shared with Wallpaper. PaperBoard was not required in the tested profile. Control Center playback controls worked with both off. Restart userspace after changes: repeated MediaRemoteUI rendering failures survived resprings."),
        OverrideGroup(title: "Accessibility and captions", labels: ["com.apple.AccessibilityUIServer", "com.apple.livetranscriptionui"], note: "Hosts accessibility interfaces and Live Captions on supported devices."),
        OverrideGroup(title: "USB and wired accessories", labels: ["com.apple.afcd", "com.apple.mobile.house_arrest", "com.apple.mobile.notification_proxy", "com.apple.mobile.insecure_notification_proxy", "com.apple.accessoryd", "com.apple.iapd", "com.apple.iap2d", "com.apple.iapauthd", "com.apple.usb.networking.addNetworkInterface"], dependencies: ["com.apple.mobile.lockdown", "com.openssh.sshd"], note: "Groups computer file access, host notifications, wired accessory protocols and USB network setup. On restores these jobs plus shared pairing and SSH prerequisites; Off preserves Critical lockdownd and OpenSSH. These jobs are not all required for USB SSH, and Off does not disable the USB controller or wall charging. Restart userspace after changes. The earlier USB recovery followed a full override reset and restart; no single service was isolated as its cause."),
        OverrideGroup(title: "AirDrop", labels: ["com.apple.sharing.airdropui"], dependencies: ["com.apple.sharingd", "com.apple.pluginkit.pkd"], note: "On/Off also changes Allow AirDrop for sending and receiving. Shared sharingd and pkd remain enabled for other app extensions and sharing.", controlsAirDrop: true),
        OverrideGroup(title: "Wallet", labels: ["com.apple.PassbookUISceneService", "com.apple.passd"], note: "Wallet interface and shared PassKit backend. Group Off disables the interface but preserves Critical passd because the tested App Store free-app confirmation also needs it. Individual passd disabling remains available. Apple Pay and Wallet passes were not tested."),
        OverrideGroup(title: "Shortcuts", labels: ["com.apple.ShortcutsUI", "com.apple.linkd"], dependencies: ["com.apple.siriactionsd", "com.apple.pluginkit.pkd"], note: "Includes interactive UI and the app-action broker. Apple’s Set Flashlight action passed testing; the WhatsApp Meta AI action remains unresolved. Restart userspace after group changes."),
        OverrideGroup(title: "Screen recording", labels: ["com.apple.replaykitangel", "com.apple.replayd"], note: "Enable both, then respring before recording: SpringBoard retained a broken connection until respring in device tests. Screen capture/broadcast is separate from Camera photos and videos."),
        OverrideGroup(title: "Widget updates", labels: ["com.apple.chronod"], dependencies: ["com.apple.pluginkit.pkd"], note: "Stops widget timeline updates; does not remove configured widgets or disable every legacy widget path. Keep pkd on to avoid the reproduced CPU loop. Live Activities and Lock Screen playback are controlled by the separate media group."),
        OverrideGroup(title: "Apple Account and settings sync", labels: ["com.apple.appleaccountd", "com.apple.amsaccountsd", "com.apple.cloudsettingssyncagent", "com.apple.cloudd"], dependencies: ["com.apple.accountsd", "com.apple.akd", "com.apple.adid", "com.apple.absd", "com.apple.cdpd", "com.apple.followupd", "com.apple.identityservicesd", "com.apple.imagent", "com.apple.syncdefaultsd", "com.apple.apsd", "com.apple.protectedcloudstorage.protectedcloudkeysyncing", "com.apple.SecureBackupDaemon"], note: "Full Apple Account sign-in passed on the test phone with the listed authentication jobs restored, including imagent for SMS codes, and a userspace restart. The final cdpd/followupd/Identity Services set was tested together, not individually isolated. Group Off preserves Critical authentication jobs. Cloud sync needs separate verification. Restart userspace after changes."),
        OverrideGroup(title: "Messages and FaceTime", labels: ["com.apple.imagent", "com.apple.identityservicesd", "com.apple.avconferenced"], dependencies: ["com.apple.nehelper", "com.apple.apsd", "com.apple.accountsd", "com.apple.akd"], note: "Restoring imagent plus respring restored carrier SMS verification delivery. Group Off preserves imagent and Identity Services for SMS/account setup; their individual switches remain available. Nehelper restored Messages in earlier tests; FaceTime calls remain untested. Restart userspace after changes."),
        OverrideGroup(title: "iCloud Drive", labels: ["com.apple.bird", "com.apple.cloudd"], dependencies: ["com.apple.FileProvider", "com.apple.accountsd", "com.apple.akd", "com.apple.protectedcloudstorage.protectedcloudkeysyncing", "com.apple.SecureBackupDaemon"], note: "CloudDocs and CloudKit sync. Shared FileProvider remains available for local Files and sharing. Restoring the protected-key and secure-backup prerequisites repaired key recovery in logs; Drive listing, upload and web download passed on the test phone; one initial Save to Files attempt unexpectedly returned Home and was not isolated. Complete any Settings account verification and restart userspace after changes."),
        OverrideGroup(title: "Photos sharing and export", labels: ["com.apple.photos.ImageConversionService", "com.apple.photos.VideoConversionService"], dependencies: ["com.apple.assetsd", "com.apple.pluginkit.pkd", "com.apple.sharingd"], note: "Restoring ImageConversionService and respringing repaired Photos → WhatsApp image export. Restoring VideoConversionService separately and respringing then repaired the Camera video test. Both are Critical: group Off preserves them, so the group Off button is unavailable. Use individual switches when deliberately disabling export. Camera capture is separate from sharing conversion. Restart userspace after group changes."),
        OverrideGroup(title: "iCloud Photos", labels: ["com.apple.cloudphotod", "com.apple.assetsd.nebulad"], dependencies: ["com.apple.assetsd", "com.apple.cloudd", "com.apple.accountsd", "com.apple.akd", "com.apple.protectedcloudstorage.protectedcloudkeysyncing", "com.apple.SecureBackupDaemon", "com.apple.dasd", "com.apple.contextstored"], note: "Photos cloud-sync jobs; shared Photos storage remains available for local capture. Restoring the key/backup prerequisites and contextstored, then allowing the scheduled retry, synced two user-verified photos. Turning only contextstored back off and restarting reproduced a new upload stall: DAS rejected it on network-quality/data-budget policies while context reads failed. Group Off preserves these Critical prerequisites. Complete any Settings account verification and restart userspace after changes."),
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
