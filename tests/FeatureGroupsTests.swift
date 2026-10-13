import Foundation

@main
struct FeatureGroupsTests {
    static func main() {
        precondition(DaemonDescriptions.get(for: "com.apple.FileProvider") != nil)
        let critical = "com.apple.appleaccountd"
        let optional = "com.apple.cloudd"
        let dependency = "com.apple.accountsd"
        let group = OverrideGroup(title: "Fixture", labels: [critical, optional, optional], dependencies: [dependency, optional])
        precondition(group.allLabels == [critical, optional, dependency], "Shared labels must be applied once")
        precondition(Set(group.actionLabels(enable: false)) == [optional], "Off must preserve Critical and shared dependencies")
        precondition(group.actionLabels(enable: true) == [critical, optional, dependency], "On must restore every listed dependency")
        for group in OverrideServices.groups {
            let off = Set(group.actionLabels(enable: false))
            precondition(off.allSatisfy { !SafetyManager.isCritical($0) || group.criticalOffLabels.contains($0) }, "Group Off included an unlisted Critical service: \(group.title)")
            precondition(group.criticalOffLabels.isSubset(of: Set(group.labels)), "An exception cannot disable a prerequisite-only job")
            precondition(Set(group.dependencies).subtracting(group.labels).isDisjoint(with: off), "Group Off included a shared prerequisite")
            precondition(Set(group.allLabels).count == group.allLabels.count)
        }
        for title in ["Bluetooth", "Calls and SMS", "Wi-Fi", "Keyboard", "Safari services", "Location", "Siri and dictation"] {
            let feature = OverrideServices.groups.first { $0.title == title }!
            precondition(Set(feature.actionLabels(enable: false)) == Set(feature.labels), "Explicit feature Off must include every feature job")
            precondition(!feature.actionLabels(enable: false).contains("com.openssh.sshd"))
            precondition(!feature.actionLabels(enable: false).contains("com.apple.powerd"))
            precondition(!feature.actionLabels(enable: false).contains("com.apple.pluginkit.pkd"))
        }
        let siri = OverrideServices.groups.first { $0.title == "Siri and dictation" }!
        precondition(!siri.actionLabels(enable: false).contains("com.apple.searchd"), "Spotlight is not a Siri-only dependency")
        precondition(DefaultPresets.builtinDefaults["com.apple.siriactionsd"] == true)
        precondition(!SafetyManager.isCritical("com.apple.siriactionsd"))
        let recording = OverrideServices.groups.first { $0.title == "Screen recording" }!
        let usb = OverrideServices.groups.first { $0.title == "USB and wired accessories" }!
        precondition(Set(usb.actionLabels(enable: true)) == Set(usb.labels + ["com.apple.mobile.lockdown", "com.openssh.sshd"]), "USB On must restore host jobs and shared prerequisites")
        precondition(Set(usb.actionLabels(enable: false)) == Set(usb.labels), "USB Off must retain every optional host job as a toggle")
        precondition(!usb.actionLabels(enable: false).contains("com.apple.mobile.lockdown"))
        precondition(!usb.actionLabels(enable: false).contains("com.openssh.sshd"), "USB Off must preserve remote access")
        let media = OverrideServices.groups.first { $0.title == "Lock Screen media controls" }!
        precondition(Set(media.actionLabels(enable: true)) == ["com.apple.PosterBoard", "com.apple.liveactivitiesd"])
        precondition(Set(media.actionLabels(enable: false)) == Set(media.actionLabels(enable: true)), "Optional media group must support complete Off")
        let widgets = OverrideServices.groups.first { $0.title == "Widget updates" }!
        precondition(!widgets.allLabels.contains("com.apple.liveactivitiesd"), "Widget updates must not disable Lock Screen playback")
        precondition(Set(recording.actionLabels(enable: true)) == ["com.apple.replaykitangel", "com.apple.replayd"])
        precondition(OverrideServices.groups.filter(\.controlsAirDrop).count == 1)
        precondition(OverrideServices.groups.first { $0.controlsAirDrop }!.actionLabels(enable: false) == ["com.apple.sharing.airdropui"])
        let messages = OverrideServices.groups.first { $0.title == "Messages and FaceTime" }!
        precondition(!messages.actionLabels(enable: false).contains("com.apple.imagent"), "Group Off must preserve the tested SMS dependency")
        precondition(!messages.actionLabels(enable: false).contains("com.apple.identityservicesd"))
        let account = OverrideServices.groups.first { $0.title == "Apple Account and settings sync" }!
        for label in ["com.apple.absd", "com.apple.cdpd", "com.apple.followupd", "com.apple.identityservicesd", "com.apple.imagent", "com.apple.akd", "com.apple.adid", "com.apple.appleaccountd"] {
            precondition(account.actionLabels(enable: true).contains(label), "Account On omitted a tested prerequisite")
            precondition(!account.actionLabels(enable: false).contains(label), "Account Off disabled a protected prerequisite")
        }
        let photos = OverrideServices.groups.first { $0.title == "Photos sharing and export" }!
        precondition(photos.actionLabels(enable: true).contains("com.apple.photos.ImageConversionService"))
        precondition(!photos.actionLabels(enable: false).contains("com.apple.photos.ImageConversionService"))
        precondition(photos.actionLabels(enable: true).contains("com.apple.photos.VideoConversionService"))
        precondition(photos.actionLabels(enable: false).isEmpty, "Group Off must preserve both tested conversion dependencies")
        let wallet = OverrideServices.groups.first { $0.title == "Wallet" }!
        precondition(wallet.actionLabels(enable: false) == ["com.apple.PassbookUISceneService"])
        let store = OverrideServices.groups.first { $0.title == "App Store and media purchases" }!
        precondition(store.actionLabels(enable: true).contains("com.apple.passd"))
        precondition(!store.actionLabels(enable: false).contains("com.apple.passd"))
        for title in ["Apple Account and settings sync", "iCloud Drive", "iCloud Photos"] {
            let cloud = OverrideServices.groups.first { $0.title == title }!
            precondition(cloud.actionLabels(enable: true).contains("com.apple.protectedcloudstorage.protectedcloudkeysyncing"))
            precondition(!cloud.actionLabels(enable: false).contains("com.apple.protectedcloudstorage.protectedcloudkeysyncing"))
            precondition(cloud.actionLabels(enable: true).contains("com.apple.SecureBackupDaemon"))
            precondition(!cloud.actionLabels(enable: false).contains("com.apple.SecureBackupDaemon"))
        }
        let photoSync = OverrideServices.groups.first { $0.title == "iCloud Photos" }!
        for label in ["com.apple.contextstored", "com.apple.dasd"] {
            precondition(photoSync.actionLabels(enable: true).contains(label))
            precondition(!photoSync.actionLabels(enable: false).contains(label))
        }
        print("Feature group policy checks passed")
    }
}
