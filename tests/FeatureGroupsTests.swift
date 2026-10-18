import Foundation

@main
struct FeatureGroupsTests {
    static func main() {
        precondition(DaemonDescriptions.get(for: "com.apple.FileProvider") != nil)
        for label in ["com.apple.mDNSResponder.reloaded", "com.apple.mDNSResponderHelper.reloaded"] {
            precondition(SafetyManager.isCritical(label), "Actual DNS job labels must retain the legacy Critical policy")
            precondition(SafetyManager.warning(for: label) != nil)
            precondition(DefaultPresets.builtinDefaults[label] == false)
        }
        // Old inherited targets adopt this revision; explicit differing choices survive.
        let migrated = DefaultPresets.migratedLegacyDefaults([
            "com.apple.progressd": false, "com.apple.ndoagent": true,
            "com.apple.avconferenced": true, "com.apple.matd": true,
            "com.apple.logd_helper": false
        ])
        precondition(migrated["com.apple.progressd"] == nil)
        precondition(migrated["com.apple.avconferenced"] == nil)
        precondition(migrated["com.apple.ndoagent"] == true)
        precondition(migrated["com.apple.matd"] == true)
        precondition(migrated["com.apple.logd_helper"] == nil)
        precondition(DefaultPresets.builtinDefaults["com.apple.bootpd"] == true,
                     "Apply Defaults uses the plist's declared job label, not its filename")
        precondition(DefaultPresets.builtinDefaults["com.apple.avconferenced"] == false)
        precondition(SafetyManager.recommendation(for: "com.apple.avconferenced") != nil)
        precondition(!SafetyManager.isCritical("com.apple.avconferenced"))
        precondition(OverrideServices.menuTitles == OverrideServices.menuTitles.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        })
        precondition(OverrideServices.menuTitles.contains("SpringBoard interfaces"))
        precondition(Set(OverrideServices.menuTitles).count == OverrideServices.menuTitles.count)
        let dictation = OverrideServices.groups.first { $0.title == "Dictation" }!
        let siriOnly = OverrideServices.groups.first { $0.title == "Siri" }!
        let speech: Set<String> = ["com.apple.assistantd", "com.apple.corespeechd"]
        precondition(Set(dictation.labels) == speech)
        precondition(Set(siriOnly.actionLabels(enable: false)).isDisjoint(with: speech))
        precondition(Set(siriOnly.actionLabels(enable: true)).isSuperset(of: speech))
        let both = OverrideServices.actionLabels(for: [dictation, siriOnly, dictation], enable: true)
        precondition(Set(both).count == both.count, "Overlapping selected groups must apply a shared job once")
        let off = OverrideServices.actionLabels(for: [dictation, siriOnly], enable: false)
        precondition(Set(off).isSuperset(of: speech))
        precondition(off.allSatisfy { !SafetyManager.isCritical($0) })
        precondition(!off.contains("com.apple.TextInput.kbd"), "Bulk Off must preserve dependency-only keyboard service")
        precondition(speech.allSatisfy { DefaultPresets.builtinDefaults[$0] == true })
        let critical = "com.apple.searchd"
        precondition(!SafetyManager.isCritical("com.apple.appleaccountd"))
        precondition(SafetyManager.recommendation(for: "com.apple.appleaccountd") != nil)
        precondition(SafetyManager.recommendation(for: "appleaccountd") != nil)
        precondition(!SafetyManager.requiresWarning("com.apple.appleaccountd"))
        let logging = OverrideServices.groups.first { $0.title == "Core logging" }!
        let diagnostics = OverrideServices.groups.first { $0.title == "Analytics and diagnostics" }!
        precondition(Set(logging.actionLabels(enable: false)) == ["com.apple.logd", "com.apple.logd_helper"])
        precondition(Set(diagnostics.dependencies) == Set(logging.labels))
        precondition(Set(diagnostics.actionLabels(enable: false)).isDisjoint(with: Set(logging.labels)), "Collector Off must preserve core logging")
        precondition(Set(diagnostics.actionLabels(enable: true)).isSuperset(of: Set(logging.labels)))
        for label in diagnostics.labels {
            precondition(DefaultPresets.builtinDefaults[label] == true, "Collectors retain their existing Off defaults")
        }
        for label in logging.labels {
            precondition(DefaultPresets.builtinDefaults[label] == false, "Core logging retains its existing On defaults")
            precondition(!OverrideServices.labels.contains(label), "Untested logger jobs must not hot-unload")
        }
        let optional = "com.apple.cloudd"
        let dependency = "com.apple.accountsd"
        let group = OverrideGroup(title: "Fixture", labels: [critical, optional, optional], dependencies: [dependency, optional])
        precondition(group.allLabels == [critical, optional, dependency], "Shared labels must be applied once")
        precondition(Set(group.actionLabels(enable: false)) == [optional], "Off must preserve Critical and shared dependencies")
        precondition(group.actionLabels(enable: true) == [critical, optional, dependency], "On must restore every listed dependency")
        precondition(group.visibleLabels == [optional, dependency], "Critical services must not appear among a group's visible services")
        for group in OverrideServices.groups {
            let off = Set(group.actionLabels(enable: false))
            precondition(off.allSatisfy { !SafetyManager.isCritical($0) }, "Group Off included a Critical service: \(group.title)")
            precondition(Set(group.dependencies).subtracting(group.labels).isDisjoint(with: off), "Group Off included a shared prerequisite")
            precondition(Set(group.allLabels).count == group.allLabels.count)
            precondition(group.visibleLabels.allSatisfy { !SafetyManager.isCritical($0) }, "Groups must not display Critical services")
            precondition(group.labels.allSatisfy { !SafetyManager.isCritical($0) }, "Critical jobs belong only to prerequisite policy, not grouped feature membership")
            precondition(Set(group.visibleLabels).count == group.visibleLabels.count)
        }
        for title in ["Bluetooth", "Calls and SMS", "Wi-Fi", "Keyboard", "Safari services", "Location", "Siri"] {
            let feature = OverrideServices.groups.first { $0.title == title }!
            precondition(Set(feature.actionLabels(enable: false)) == Set(feature.labels), "Explicit feature Off must include every feature job")
            precondition(!feature.actionLabels(enable: false).contains("com.openssh.sshd"))
            precondition(!feature.actionLabels(enable: false).contains("com.apple.powerd"))
            precondition(!feature.actionLabels(enable: false).contains("com.apple.pluginkit.pkd"))
        }
        let siri = OverrideServices.groups.first { $0.title == "Siri" }!
        precondition(!siri.actionLabels(enable: false).contains("com.apple.searchd"), "Spotlight is not a Siri-only dependency")
        precondition(DefaultPresets.builtinDefaults["com.apple.siriactionsd"] == true)
        precondition(!SafetyManager.isCritical("com.apple.siriactionsd"))
        let search = OverrideServices.groups.first { $0.title == "Spotlight and search" }!
        precondition(!search.actionLabels(enable: false).contains("com.apple.searchd"), "A known CPU-loop dependency must survive group Off")
        precondition(!search.visibleLabels.contains("com.apple.searchd"))
        precondition(!search.labels.contains("com.apple.searchd"))
        precondition(search.dependencies.contains("com.apple.searchd"))
        precondition(search.actionLabels(enable: true).contains("com.apple.searchd"))
        precondition(Set(search.actionLabels(enable: false)) == Set(search.labels))
        precondition(Set(search.labels).isDisjoint(with: Set(siri.labels)))
        precondition(DefaultPresets.builtinDefaults["com.apple.searchd"] == false, "Preserve the Photos dependency default until verified")
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
        precondition(messages.actionLabels(enable: false).contains("com.apple.imagent"), "An explicit messaging opt-out must stop its SMS broker")
        precondition(messages.actionLabels(enable: false).contains("com.apple.identityservicesd"))
        let account = OverrideServices.groups.first { $0.title == "Apple Account and settings sync" }!
        for label in ["com.apple.absd", "com.apple.cdpd", "com.apple.followupd", "com.apple.identityservicesd", "com.apple.imagent", "com.apple.akd", "com.apple.adid", "com.apple.appleaccountd"] {
            precondition(account.actionLabels(enable: true).contains(label), "Account On omitted a tested prerequisite")
            precondition(account.actionLabels(enable: false).contains(label) == (label == "com.apple.appleaccountd"), "Account Off must stop its feature jobs and preserve prerequisite-only jobs")
        }
        let photos = OverrideServices.groups.first { $0.title == "Photos sharing and export" }!
        precondition(photos.actionLabels(enable: true).contains("com.apple.photos.ImageConversionService"))
        precondition(photos.actionLabels(enable: false).contains("com.apple.photos.ImageConversionService"))
        precondition(photos.actionLabels(enable: true).contains("com.apple.photos.VideoConversionService"))
        precondition(Set(photos.actionLabels(enable: false)) == Set(photos.labels), "Export opt-out must stop both conversion jobs")
        let wallet = OverrideServices.groups.first { $0.title == "Wallet" }!
        precondition(Set(wallet.actionLabels(enable: false)) == Set(wallet.labels), "Wallet opt-out also stops its shared PassKit backend")
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
