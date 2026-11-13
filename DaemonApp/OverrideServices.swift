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

    // Core prerequisites are restored by On but managed in the Critical tab.
    var visibleLabels: [String] {
        allLabels.filter { !SafetyManager.isCritical($0) }
    }

    func actionLabels(enable: Bool) -> [String] {
        enable ? allLabels : allLabels.filter {
            labels.contains($0) && !SafetyManager.isCritical($0)
        }
    }
}

enum OverrideServices {
    // Core OS services are assumed available; these are feature-specific jobs
    // and known shared prerequisites, not a complete OS dependency graph.
    static let groups = [
        OverrideGroup(
            title: "Accessibility and captions",
            labels: [
                "com.apple.AccessibilityUIServer",
                "com.apple.livetranscriptionui",
                "com.apple.assistivetouchd",
                "com.apple.VoiceOverTouch",
                "com.apple.accessibility.axassetsd",
                "com.apple.accessibility.axremoted",
                "com.apple.accessibility.motiontrackingd",
                "com.apple.commandandcontrol",
                "com.apple.fullkeyboardaccess",
                "com.apple.scrod",
                "com.apple.voiced"
            ],
            dependencies: ["com.apple.mediaserverd"],
            note: "Optional accessibility UI, AssistiveTouch, VoiceOver, Voice Control, keyboard access, recognition, remote accessibility and spoken-content jobs. These default Off. Shared services: assistivetouchd and AccessibilityUIServer are shared with 'AssistiveTouch'; voiced, accessibility.axassetsd and AccessibilityUIServer are shared with 'Speak Screen and spoken content'; fullkeyboardaccess is shared with 'Keyboard'; mediaserverd is a shared audio prerequisite. Background Sounds/heard is intentionally separate and stays On for regular sleep use. Use Apply Now to attempt loading/unloading in this session; clients can require reopening or a restart."
        ),
        OverrideGroup(
            title: "AirDrop",
            labels: ["com.apple.sharing.airdropui"],
            dependencies: ["com.apple.sharingd", "com.apple.pluginkit.pkd"],
            note: "On/Off also changes Allow AirDrop for sending and receiving. Shared prerequisites: sharingd is shared with 'Handoff' and 'Photos sharing and export'; pluginkit.pkd is shared with 'Photos sharing and export', 'Shortcuts', 'Siri' and 'Widget updates' and remains enabled on group Off.",
            controlsAirDrop: true
        ),
        OverrideGroup(
            title: "Analytics and diagnostics",
            labels: [
                "com.apple.analyticsd",
                "com.apple.aggregated",
                "com.apple.aggregated.addaily",
                "com.apple.diagnosticd",
                "com.apple.diagnosticextensionsd",
                "com.apple.iosdiagnosticsd",
                "com.apple.osanalytics.osanalyticshelper",
                "com.apple.powerlogHelperd",
                "com.apple.syslogd",
                "com.apple.sysdiagnose",
                "com.apple.sysdiagnose_helper",
                "com.apple.spindump",
                "com.apple.ReportCrash",
                "com.apple.ReportMemoryException",
                "com.apple.crash_mover"
            ],
            dependencies: ["com.apple.logd", "com.apple.logd_helper"],
            note: "Groups optional analytics, legacy logging, crash/resource reporting and diagnostic collectors. These collectors default Off in the tested profile. Shared prerequisites: logd and logd_helper are shared with 'Core logging' (On restores them for troubleshooting; Off preserves them). This does not control every kernel/app logging path or all network-specific diagnostics. Restart userspace after changes."
        ),
        OverrideGroup(
            title: "App Store and media purchases",
            labels: [
                "com.apple.appstored",
                "com.apple.appstorecomponentsd",
                "com.apple.itunesstored",
                "com.apple.amsaccountsd",
                "com.apple.amsengagementd"
            ],
            dependencies: [
                "com.apple.accountsd",
                "com.apple.akd",
                "com.apple.adid",
                "com.apple.passd",
                "com.apple.storekitd"
            ],
            note: "Store downloads and media accounts, separate from TrollStore installation. Shared services: amsaccountsd is shared in labels with 'Apple Account and settings sync' (toggling either group Off disables it); passd is shared with 'Wallet' (restored on On, preserved on Off); accountsd, akd and adid are shared authentication prerequisites with 'Apple Account and settings sync'. Note that passd, storekitd and adid default Off (yes) in daemon.cfg but are automatically restored when enabling this group. Restart userspace after changes."
        ),
        OverrideGroup(
            title: "Apple Account and settings sync",
            labels: [
                "com.apple.appleaccountd",
                "com.apple.amsaccountsd",
                "com.apple.cloudsettingssyncagent",
                "com.apple.cloudd"
            ],
            dependencies: [
                "com.apple.cmfsyncagent",
                "com.apple.accountsd",
                "com.apple.akd",
                "com.apple.adid",
                "com.apple.absd",
                "com.apple.cdpd",
                "com.apple.followupd",
                "com.apple.identityservicesd",
                "com.apple.imagent",
                "com.apple.syncdefaultsd",
                "com.apple.apsd",
                "com.apple.protectedcloudstorage.protectedcloudkeysyncing",
                "com.apple.SecureBackupDaemon"
            ],
            note: "Full Apple Account sign-in and settings sync. Shared labels: cloudd is shared with 'iCloud Drive' (and is a prerequisite for 'iCloud Photos'); amsaccountsd is shared with 'App Store and media purchases'. Shared prerequisites (restored on On, preserved on Off): cdpd, protectedcloudkeysyncing and SecureBackupDaemon are managed in 'Apple Cloud Security and Recovery'; followupd and syncdefaultsd are managed in 'Background Sync and Data Caches'; imagent and identityservicesd are managed in 'SMS and messaging' and 'Messages and FaceTime'; cmfsyncagent, accountsd, akd and apsd are shared with telephony and messaging groups. Restart userspace after changes."
        ),
        OverrideGroup(
            title: "Apple Cloud Security and Recovery",
            labels: [
                "com.apple.SecureBackupDaemon",
                "com.apple.protectedcloudstorage.protectedcloudkeysyncing",
                "com.apple.cdpd",
                "com.apple.transparencyd",
                "com.apple.transparencyStaticKey",
                "com.apple.online-auth-agent.xpc"
            ],
            note: "Controls cloud keychain recovery, Protected Cloud Storage end-to-end encryption keys, CoreCDP, online authentication XPC and iMessage Contact Key Verification (transparencyd). All default Off (yes) in daemon.cfg. Shared services: SecureBackupDaemon and protectedcloudkeysyncing are shared prerequisites with 'iCloud Drive', 'iCloud Photos' and 'Apple Account and settings sync'; cdpd is a shared prerequisite with 'Apple Account and settings sync'. Enabling those iCloud/Account groups automatically restores their required key-recovery daemons, while toggling this group Off directly disables all six services. Restart userspace after changes."
        ),
        OverrideGroup(
            title: "Apple Watch helpers",
            labels: [
                "com.apple.companion_proxy",
                "com.apple.companionauthd",
                "com.apple.nanobackupd",
                "com.apple.nanoprefsyncd",
                "com.apple.nanoprefsyncd.2",
                "com.apple.nanoregistrylaunchd",
                "com.apple.nanotimekitcompaniond",
                "com.apple.subridged",
                "com.apple.watchpresenced",
                "com.apple.wcd"
            ],
            dependencies: ["com.apple.nanoregistryd"],
            note: "Optional Watch pairing, backup, sync and app connectivity helpers, all default Off. The shared nanoregistryd prerequisite remains Critical because earlier evidence records a boot failure when disabled. System watchdogd is unrelated and stays enabled."
        ),
        OverrideGroup(
            title: "AssistiveTouch",
            labels: ["com.apple.assistivetouchd"],
            dependencies: ["com.apple.AccessibilityUIServer", "com.apple.backboardd"],
            note: "Restores the AssistiveTouch service and its accessibility UI host. Enable AssistiveTouch in Settings as well; a daemon override is separate from that feature switch. Defaults Off. Shared services: assistivetouchd and AccessibilityUIServer are shared with 'Accessibility and captions' (group Off disables assistivetouchd but preserves AccessibilityUIServer)."
        ),
        OverrideGroup(
            title: "Auto-Lock and configuration policy",
            labels: ["com.apple.managedconfiguration.profiled"],
            note: "Controls profiled for native Auto-Lock, Low Power Mode restrictions, configuration profiles and managed feature settings. Defaults Off (yes) in daemon.cfg; enable this group before changing Auto-Lock, as leaving profiled Off can leave Auto-Lock greyed out or stuck at a stale 30-second limit on iOS 16.7.16. This controls only profiled, not separate enrollment or passcode-prompt services. Restart userspace after either change."
        ),
        OverrideGroup(
            title: "Background sounds and hearing",
            labels: ["com.apple.accessibility.heard"],
            dependencies: ["com.apple.mediaserverd"],
            note: "HearingCore provides Background Sounds and other hearing features. Defaults On (no in daemon.cfg) for regular Background Sounds use. Off remains available and stops these features; Bluetooth alone does not provide them. Shared prerequisite: mediaserverd is shared with audio, dictation and accessibility groups and remains enabled on Off. Restart userspace after changes."
        ),
        OverrideGroup(
            title: "Background Sync and Data Caches",
            labels: [
                "com.apple.syncdefaultsd",
                "com.apple.contextstored",
                "com.apple.followupd",
                "com.apple.mobileassetd"
            ],
            note: "Controls NSUserDefaults cloud sync (syncdefaultsd), CoreDuet context engine (contextstored, reclaiming ~15MB RAM when Off), Settings follow-up notices (followupd), and background dictionary/voice asset downloads (mobileassetd). All default Off (yes) in daemon.cfg. Shared services: contextstored is a shared prerequisite with 'iCloud Photos' (enabling 'iCloud Photos' restores contextstored so DAS does not stall photo uploads); syncdefaultsd and followupd are shared prerequisites with 'Apple Account and settings sync'; mobileassetd is a shared prerequisite with 'Speak Screen and spoken content'. Restart userspace after changes."
        ),
        OverrideGroup(
            title: "Bluetooth helpers",
            labels: [
                "com.apple.bluetoothuserd",
                "com.apple.BluetoothUIService",
                "com.apple.BTServer.le",
                "com.apple.BTServer.avrcp",
                "com.apple.BTServer.map",
                "com.apple.BTServer.pbap"
            ],
            dependencies: [
                "com.apple.bluetoothd",
                "com.apple.BlueTool",
                "com.apple.WirelessRadioManager"
            ],
            note: "Controls optional Bluetooth user/UI and profile jobs. Shared services: BluetoothUIService is shared in labels with 'Reset and Hardware Maintenance' (toggling either group Off disables the AirPods/Bluetooth UI popup card); bluetoothd and BlueTool are Critical prerequisites shared with 'Nearby accessories and AirPods'; WirelessRadioManager is a shared radio coordinator with 'Calls and telephony' and 'Wi-Fi'. Use Settings > Bluetooth for ordinary Bluetooth On/Off. Restart userspace after changes."
        ),
        OverrideGroup(
            title: "Calls and telephony",
            labels: [
                "com.apple.CommCenterMobileHelper",
                "com.apple.CommCenterRootHelper",
                "com.apple.telephonyutilities.callservicesd",
                "com.apple.voicemail.vmd",
                "com.apple.avconferenced",
                "com.apple.CommCenter-noncellular"
            ],
            dependencies: [
                "com.apple.cmfsyncagent",
                "com.apple.CommCenter",
                "com.apple.nehelper",
                "com.apple.apsd",
                "com.apple.accountsd",
                "com.apple.akd",
                "com.apple.WirelessRadioManager"
            ],
            note: "Controls cellular call helpers, CallKit/VoIP (callservicesd), voicemail (vmd), AVConference and non-cellular telephony coordination (CommCenter-noncellular, which defaults Off in daemon.cfg). Carrier SMS and iMessage are independently managed under 'SMS and messaging'. Shared services: avconferenced is a shared prerequisite for 'Messages and FaceTime' (disabling this group turns avconferenced Off); cmfsyncagent, CommCenter, nehelper, apsd, accountsd and akd are shared prerequisites with 'SMS and messaging', 'Messages and FaceTime' and 'Apple Account and settings sync' and stay enabled on group Off; WirelessRadioManager is shared with 'Bluetooth helpers' and 'Wi-Fi'. Restart userspace after changes."
        ),
        OverrideGroup(
            title: "CarPlay",
            labels: ["com.apple.CarPlayApp", "com.apple.carkitd"],
            note: "CarPlay interface and vehicle integration, both default Off. Normal phone calling and core Bluetooth remain independent shared services."
        ),
        OverrideGroup(
            title: "Contacts and calendars",
            labels: [
                "com.apple.contactsd",
                "com.apple.calaccessd",
                "com.apple.dataaccess.dataaccessd"
            ],
            dependencies: ["com.apple.accountsd"],
            note: "Address book, calendar access and configured account sync. Shared prerequisite: accountsd is shared with Apple Account, iCloud, App Store and messaging groups and remains enabled on Off. Disabling affects apps using these stores. Restart userspace after changes."
        ),
        OverrideGroup(
            title: "Core logging",
            labels: ["com.apple.logd", "com.apple.logd_helper"],
            note: "Controls the unified logger and its maintenance helper. Both default On. Shared services: logd and logd_helper are shared prerequisites for 'Analytics and diagnostics' (enabling 'Analytics and diagnostics' restores both, while disabling this group turns both Off). Restart userspace after either change."
        ),
        OverrideGroup(
            title: "Dictation",
            labels: ["com.apple.assistantd", "com.apple.corespeechd"],
            dependencies: ["com.apple.TextInput.kbd", "com.apple.mediaserverd"],
            note: "Keyboard microphone dictation. Both default Off. Shared services: assistantd and corespeechd are shared prerequisites for 'Siri' (turning 'Siri' On restores them; turning 'Dictation' Off disables them for both Dictation and Siri); TextInput.kbd is shared with 'Keyboard'; mediaserverd is shared with audio/accessibility groups. Turn on Settings > General > Keyboard > Enable Dictation. Restart userspace if a keyboard client retains a failed connection."
        ),
        OverrideGroup(
            title: "Drag and drop",
            labels: ["com.apple.DragUI.druid"],
            note: "Controls the drag-and-drop broker for source, destination and paste-announcement services. Defaults Off (yes in daemon.cfg); manual On/Off remains available. Restart userspace after changes."
        ),
        OverrideGroup(
            title: "Handoff",
            labels: ["com.apple.coreservices.useractivityd"],
            dependencies: ["com.apple.rapportd", "com.apple.sharingd"],
            note: "NSUserActivity/Handoff support defaults Off. Shared prerequisites: sharingd is shared with 'AirDrop' and 'Photos sharing and export' and stays available on group Off. The Settings Handoff switch is separate."
        ),
        OverrideGroup(
            title: "iCloud Drive",
            labels: ["com.apple.bird", "com.apple.cloudd"],
            dependencies: [
                "com.apple.FileProvider",
                "com.apple.accountsd",
                "com.apple.akd",
                "com.apple.protectedcloudstorage.protectedcloudkeysyncing",
                "com.apple.SecureBackupDaemon"
            ],
            note: "CloudDocs and CloudKit sync. Shared label: cloudd is shared in labels with 'Apple Account and settings sync' and is a prerequisite for 'iCloud Photos' (turning this group Off disables cloudd). Shared prerequisites: protectedcloudkeysyncing and SecureBackupDaemon are managed in 'Apple Cloud Security and Recovery' and restored when enabling this group; FileProvider, accountsd and akd remain available on group Off. Complete any Settings account verification and restart userspace after changes."
        ),
        OverrideGroup(
            title: "iCloud Photos",
            labels: ["com.apple.cloudphotod", "com.apple.assetsd.nebulad"],
            dependencies: [
                "com.apple.assetsd",
                "com.apple.cloudd",
                "com.apple.accountsd",
                "com.apple.akd",
                "com.apple.protectedcloudstorage.protectedcloudkeysyncing",
                "com.apple.SecureBackupDaemon",
                "com.apple.dasd",
                "com.apple.contextstored"
            ],
            note: "Photos cloud-sync jobs. Shared prerequisites (restored on On, preserved on Off): cloudd is shared with 'iCloud Drive' and 'Apple Account and settings sync'; protectedcloudkeysyncing and SecureBackupDaemon are shared with 'Apple Cloud Security and Recovery'; contextstored is shared with 'Background Sync and Data Caches' (required so DAS does not stall photo uploads); assetsd is shared with 'Photos sharing and export'. Complete any Settings account verification and restart userspace after changes."
        ),
        OverrideGroup(
            title: "Keyboard",
            labels: [
                "com.apple.TextInput.kbd",
                "com.apple.handwritingd",
                "com.apple.naturallanguaged",
                "com.apple.fullkeyboardaccess"
            ],
            dependencies: ["com.apple.biomed", "com.apple.cfprefsd.xpc.daemon"],
            note: "Off deliberately disables text-input services after userspace restart. Shared services: fullkeyboardaccess is shared in labels with 'Accessibility and captions'; TextInput.kbd is a shared prerequisite for 'Dictation'. Typing, AutoFill, text replacement and keyboard clients can fail when Off; restore On locally without relying on keyboard entry."
        ),
        OverrideGroup(
            title: "Location",
            labels: [
                "com.apple.locationd",
                "com.apple.gpsd",
                "com.apple.geod",
                "com.apple.navd",
                "com.apple.locationpushd",
                "com.apple.routined",
                "com.apple.maps.destinationd",
                "com.apple.Maps.geocorrectiond",
                "com.apple.Maps.mapspushd"
            ],
            note: "Off includes Core Location and GPS, geocoding/navigation, location push and routine services. Location-dependent apps and automatic location features can fail. On restores the listed jobs; restart userspace in either direction."
        ),
        OverrideGroup(
            title: "Lock Screen media controls",
            labels: ["com.apple.PosterBoard", "com.apple.liveactivitiesd"],
            note: "Both default Off and remain freely switchable. On restores the tested Lock Screen and Notification Center playback panel; Off disables both hosts. Shared label: PosterBoard is shared in labels with 'Wallpaper' (toggling either group Off disables PosterBoard). liveactivitiesd also supports Live Activities. Control Center playback controls worked with both off. Restart userspace after changes."
        ),
        OverrideGroup(
            title: "Messages and FaceTime",
            labels: ["com.apple.imagent", "com.apple.identityservicesd"],
            dependencies: [
                "com.apple.cmfsyncagent",
                "com.apple.avconferenced",
                "com.apple.nehelper",
                "com.apple.apsd",
                "com.apple.accountsd",
                "com.apple.akd"
            ],
            note: "Controls core iMessage/FaceTime identity and messaging agents. Shared labels: imagent and identityservicesd are shared in labels with 'SMS and messaging' and are prerequisites for 'Apple Account and settings sync' (disabling this group also disables carrier SMS and iMessage in 'SMS and messaging'). Shared prerequisites: avconferenced is managed in 'Calls and telephony'; cmfsyncagent, nehelper, apsd, accountsd and akd are shared with 'SMS and messaging' and 'Calls and telephony' and stay enabled on group Off. Restart userspace after changes."
        ),
        OverrideGroup(
            title: "Nearby accessories and AirPods",
            labels: ["com.apple.proximitycontrold", "com.apple.cloudpaird"],
            dependencies: ["com.apple.bluetoothd", "com.apple.BlueTool"],
            note: "Optional proximity interfaces and iCloud Bluetooth pairing support, both default Off. Shared prerequisites: bluetoothd and BlueTool are Critical services shared with 'Bluetooth helpers' and remain enabled; see 'Reset and Hardware Maintenance' or 'Bluetooth helpers' for BluetoothUIService popup cards."
        ),
        OverrideGroup(
            title: "Photos sharing and export",
            labels: [
                "com.apple.photos.ImageConversionService",
                "com.apple.photos.VideoConversionService"
            ],
            dependencies: [
                "com.apple.assetsd",
                "com.apple.pluginkit.pkd",
                "com.apple.sharingd"
            ],
            note: "Controls media conversion services required when exporting or sharing photos and videos (e.g., Photos to WhatsApp or Camera video export). Both default On (no in daemon.cfg), but can be manually toggled Off if media export conversion is not needed. Shared prerequisites: assetsd is shared with 'iCloud Photos'; pluginkit.pkd is shared with 'AirDrop', 'Shortcuts', 'Siri' and 'Widget updates'; sharingd is shared with 'AirDrop' and 'Handoff'. Restart userspace after group changes."
        ),
        OverrideGroup(
            title: "Reset and Hardware Maintenance",
            labels: [
                "com.apple.BluetoothUIService",
                "com.apple.devicedataresetd",
                "com.apple.mobilecheckpoint.checkpointd",
                "com.apple.mobile.cache_delete_mobile_backup",
                "com.apple.SepUpdateTimer",
                "com.apple.MTLAssetUpgraderD"
            ],
            note: "Controls the AirPods popup card (BluetoothUIService), Erase All Content reset broker (devicedataresetd), post-restore checkpoints (checkpointd), backup cache cleaner (cache_delete_mobile_backup), OTA SEP update timer (SepUpdateTimer), and Metal shader upgrade checks (MTLAssetUpgraderD). All default Off (yes in daemon.cfg) and are safe to keep disabled on permanent jailbreak setups where OTA updates and factory resets are never performed. Shared label: BluetoothUIService is shared in labels with 'Bluetooth helpers' (toggling either group Off disables it). Restart userspace after changes."
        ),
        OverrideGroup(
            title: "Safari services",
            labels: [
                "com.apple.WebBookmarks.webbookmarksd",
                "com.apple.Safari.History",
                "com.apple.Safari.SafeBrowsing.Service",
                "com.apple.Safari.passwordbreachd",
                "com.apple.SafariBookmarksSyncAgent",
                "com.apple.safarifetcherd",
                "com.apple.webkit.webpushd",
                "com.apple.webkit.adattributiond"
            ],
            dependencies: ["com.apple.nsurlsessiond", "com.apple.security.swcagent"],
            note: "Groups Safari bookmarks/history (webbookmarksd and Safari.History default Off/yes in daemon.cfg), sync, website checks, Reading List, web push and attribution. The Safari app and WebKit content/network/GPU processes are app/XPC processes, not these launchd jobs: Off does not block browsing. Shared networking and associated-domain prerequisites stay enabled. Restart userspace after changes."
        ),
        OverrideGroup(
            title: "Screen recording",
            labels: ["com.apple.replaykitangel", "com.apple.replayd"],
            note: "Enable both, then respring before recording: SpringBoard retained a broken connection until respring in device tests. Screen capture/broadcast is separate from Camera photos and videos."
        ),
        OverrideGroup(
            title: "Shortcuts",
            labels: ["com.apple.ShortcutsUI", "com.apple.linkd"],
            dependencies: ["com.apple.siriactionsd", "com.apple.pluginkit.pkd"],
            note: "Includes interactive UI and the app-action broker. Shared services: ShortcutsUI is shared in labels with 'Siri' (disabling either group turns ShortcutsUI Off); linkd and pluginkit.pkd are shared prerequisites with 'Siri'; siriactionsd is managed in 'Siri' and restored when 'Shortcuts' is turned On. Restart userspace after group changes."
        ),
        OverrideGroup(
            title: "Siri",
            labels: [
                "com.apple.assistant_service",
                "com.apple.assistant_cdmd",
                "com.apple.siriinferenced",
                "com.apple.siriknowledged",
                "com.apple.sirittsd",
                "com.apple.speechmodeltrainingd",
                "com.apple.siriactionsd",
                "com.apple.ShortcutsUI",
                "com.apple.triald"
            ],
            dependencies: [
                "com.apple.assistantd",
                "com.apple.corespeechd",
                "com.apple.linkd",
                "com.apple.pluginkit.pkd"
            ],
            note: "Voice assistance, Siri context, speech output/training, Trial asset delivery and the shared VoiceShortcuts broker. Shared labels: ShortcutsUI is shared in labels with 'Shortcuts'; siriactionsd is a prerequisite for 'Shortcuts'; sirittsd and triald are shared prerequisites for 'Speak Screen and spoken content'. Shared prerequisites: assistantd and corespeechd are shared with 'Dictation' (preserved on Siri Off so Dictation can remain On); linkd is shared with 'Shortcuts'; pluginkit.pkd is shared with 'AirDrop', 'Photos sharing and export', 'Shortcuts' and 'Widget updates'. Restart userspace after changes."
        ),
        OverrideGroup(
            title: "SMS and messaging",
            labels: [
                "com.apple.imagent",
                "com.apple.identityservicesd",
                "com.apple.imcore.imtransferagent",
                "com.apple.ids.IDSCredentialsAgent",
                "com.apple.idsfoundation.IDSRemoteURLConnectionAgent"
            ],
            dependencies: [
                "com.apple.cmfsyncagent",
                "com.apple.CommCenter",
                "com.apple.nehelper",
                "com.apple.apsd",
                "com.apple.accountsd",
                "com.apple.akd"
            ],
            note: "Controls carrier SMS, iMessage transfer/credential helpers and Identity Services (IDS) brokers, separated from cellular voice calling ('Calls and telephony'). Shared labels: imagent and identityservicesd are shared in labels with 'Messages and FaceTime' and are prerequisites for 'Apple Account and settings sync' (disabling this group stops carrier SMS verification codes and iMessage). Shared prerequisites (restored on On, preserved on Off): cmfsyncagent, CommCenter, nehelper, apsd, accountsd and akd are shared with 'Calls and telephony', 'Messages and FaceTime' and 'Apple Account and settings sync'. Restart userspace after changes."
        ),
        OverrideGroup(
            title: "Speak Screen and spoken content",
            labels: ["com.apple.voiced", "com.apple.accessibility.axassetsd"],
            dependencies: [
                "com.apple.AccessibilityUIServer",
                "com.apple.sirittsd",
                "com.apple.triald",
                "com.apple.mobileassetd",
                "com.apple.mediaserverd"
            ],
            note: "On-demand spoken content, speech output and voice asset support. Defaults Off. Shared labels: voiced and accessibility.axassetsd are shared in labels with 'Accessibility and captions'. Shared prerequisites (restored on On, preserved on Off): AccessibilityUIServer is shared with 'Accessibility and captions' and 'AssistiveTouch'; sirittsd and triald are shared with 'Siri'; mobileassetd is shared with 'Background Sync and Data Caches'; mediaserverd is shared with audio/accessibility groups."
        ),
        OverrideGroup(
            title: "Spotlight and search",
            labels: [
                "com.apple.corespotlightservice",
                "com.apple.spotlight.IndexAgent",
                "com.apple.spotlightknowledged",
                "com.apple.parsecd",
                "com.apple.parsec-fbf",
                "com.apple.knowledgeconstructiond"
            ],
            dependencies: ["com.apple.searchd"],
            note: "Controls optional search, indexing and knowledge helpers, separately from Siri and dictation. Turning them off can reduce indexed or suggested results; the Spotlight interface and app-local search can remain available. Shared system prerequisites remain managed in Critical. Restart userspace after changes."
        ),
        OverrideGroup(
            title: "USB and wired accessories",
            labels: [
                "com.apple.afcd",
                "com.apple.mobile.house_arrest",
                "com.apple.mobile.notification_proxy",
                "com.apple.mobile.insecure_notification_proxy",
                "com.apple.accessoryd",
                "com.apple.iapd",
                "com.apple.iap2d",
                "com.apple.iapauthd",
                "com.apple.usb.networking.addNetworkInterface"
            ],
            dependencies: ["com.apple.mobile.lockdown", "com.openssh.sshd"],
            note: "Groups computer file access, host notifications, wired accessory protocols and USB network setup. On restores these jobs plus shared pairing and SSH prerequisites; Off preserves the shared lockdownd and OpenSSH prerequisites. These jobs are not all required for USB SSH, and Off does not disable the USB controller or wall charging. Restart userspace after changes."
        ),
        OverrideGroup(
            title: "Wallet",
            labels: ["com.apple.PassbookUISceneService", "com.apple.passd"],
            note: "Wallet interface and shared PassKit backend. Both default Off (yes in daemon.cfg). Shared service: passd is a shared prerequisite for 'App Store and media purchases' (disabling 'Wallet' turns passd Off, which also breaks the App Store confirmation prompt until either 'Wallet' or 'App Store and media purchases' is turned back On)."
        ),
        OverrideGroup(
            title: "Wallpaper",
            labels: ["com.apple.PosterBoard", "com.apple.PaperBoard"],
            note: "Controls wallpaper and Lock Screen hosts. Shared label: PosterBoard is shared in labels with 'Lock Screen media controls' (turning 'Wallpaper' Off also disables Lock Screen media controls rendering even if liveactivitiesd is On). Restart userspace after changes."
        ),
        OverrideGroup(
            title: "Wi-Fi",
            labels: [
                "com.apple.wifid",
                "com.apple.wifiFirmwareLoader",
                "com.apple.wifip2pd",
                "com.apple.wifi.hostapd",
                "com.apple.wifi.wapic",
                "com.apple.wifianalyticsd",
                "com.apple.wifivelocityd"
            ],
            dependencies: ["com.apple.configd", "com.apple.WirelessRadioManager"],
            note: "Off disables Wi-Fi service jobs after userspace restart and can disconnect Wi-Fi SSH. Restore On locally in this app or through working USB SSH. Shared prerequisites: configd and WirelessRadioManager (shared with 'Bluetooth helpers' and 'Calls and telephony') stay enabled for other transports."
        ),
        OverrideGroup(
            title: "Widget updates",
            labels: ["com.apple.chronod"],
            dependencies: ["com.apple.pluginkit.pkd"],
            note: "Stops widget timeline updates; does not remove configured widgets or disable every legacy widget path. Shared prerequisite: pluginkit.pkd is shared with 'AirDrop', 'Photos sharing and export', 'Shortcuts' and 'Siri' and stays enabled to avoid the reproduced CPU loop. Live Activities and Lock Screen playback are controlled by 'Lock Screen media controls'."
        )
    ].sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

    static let springBoardInterfacesTitle = "SpringBoard interfaces"
    static let menuTitles = (groups.map(\.title) + [springBoardInterfacesTitle]).sorted {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }

    static func actionLabels(for groups: [OverrideGroup], enable: Bool) -> [String] {
        var seen = Set<String>()
        return groups.flatMap { $0.actionLabels(enable: enable) }.filter { seen.insert($0).inserted }
    }

    // Only these jobs are automatically loaded/unloaded after a toggle. Other jobs
    // save overrides first; explicit Apply Now attempts their session change.
    static let labels: Set<String> = [
        "com.apple.PosterBoard", "com.apple.PaperBoard", "com.apple.AccessibilityUIServer",
        "com.apple.livetranscriptionui", "com.apple.sharing.airdropui", "com.apple.PassbookUISceneService",
        "com.apple.ShortcutsUI", "com.apple.replaykitangel", "com.apple.replayd",
        "com.apple.chronod", "com.apple.liveactivitiesd"
    ]
}