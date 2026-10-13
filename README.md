# Daemon Manager

Current **v1.0.26** retains a separate **Spotlight and search** group alongside Bluetooth, Calls/SMS, Wi-Fi, Keyboard, Safari services, Location, and Siri/dictation. Spotlight Off deliberately includes searchd, which also serves Photos/app-index queries; the search interface and app-local results can remain available. searchd stays builtin On: its isolated Off/restart test later reproduced a Photos background CPU loop at about 106% of one core, despite initially normal basic use. Essentials remain enabled by default; deliberate group Off can include their named Critical feature jobs while shared prerequisites remain protected. Existing tested groups retain their policies. New core-feature Off/restart/recovery cycles remain unverified; Safari service Off does not block the Safari/WebKit app processes.

The **Groups** tab (page title **Feature Groups**) replaces the old Overrides name. **Core logging** controls logd and its helper; **Analytics and diagnostics** controls optional collectors and preserves core logging during Off. Defaults remain unchanged. Complete logger-Off and full collector-group round trips remain unverified; adding a control is not a safe-disabling claim.

The [logging follow-up](audit/2026-10-13-logging.md) measures the small core-logging cost and records the scoped helper-Off test. Actual `.reloaded` DNS labels now share the legacy Critical classification; their On defaults are unchanged. No additional service is declared universally safe Off.

The [2026-10-13 audit](audit/2026-10-13.md) and [complete target inventory](audit/services-2026-10-13.csv) distinguish source findings, installed state, historical evidence and empirical limits. The isolated siriactionsd Off/userspace-restart test passed user basic-use checks without reproducing its old sustained CPU warning. It and ShortcutsUI now default Off; restore Shortcuts On when needed. Current targets: **512 entries, 315 Off / 197 On, 90 Critical enabled**. Actual messaging credential/attachment jobs and local Safari history/bookmarks default On. Installation does not apply defaults or override explicit custom choices. Dated sections below describe their historical revisions.

Root commands now pass credentials through stdin and forward commands unchanged; stale-state and overlapping-operation handling were corrected. A finite, read-only iOS sampler is available at `tools/sample_resources.py` (Python 3.9+). Run on the phone as root, for example `python3 sample_resources.py --interval 10 --samples 3`; capture its JSON lines privately. CPU uses the runtime Mach timebase, footprint is per process, and `/usr/bin/vm_stat` subtracts speculative pages in its printed physical-free line. The app uses host_statistics64, whose free_count includes speculative pages. Do not mix those counters or sum process footprints as a RAM-saving estimate.

SwiftUI service/preset manager for jailbroken iOS 16+, built with XcodeGen and installed with TrollStore Lite or AppSync Unified.

Known service descriptions are visible directly in Services, Defaults and Overrides. Tap the name or chevron for warnings, launchd plist/executable paths and related file metadata where verified. Contacts-related services show the address-book database paths, sizes, and modification dates without reading contact records. Uncertain private roles are omitted. The independent switch edits the saved launchd override; restart userspace for full loaded-process changes.

The tab bar has an opaque standard and scroll-edge appearance from initial launch. Search, the available-memory number (MiB, displayed without a unit or label), and the theme switch share one row. The filter is the second row; pinned category headings and the separate top memory bar are removed. Memory is kernel free memory including speculative pages, with each page counted once. Tap the number for the live memory sheet.

`daemon.cfg` matches all **512 builtin targets: 315 off, 197 on**. `yes` = disabled override; `no` = enabled override; uppercase `NO` = critical, keep enabled. All entries remain manually configurable. Critical includes measured CPU, repeated crashes and core dependency failures; it does not mean every member causes a bootloop. The classifications reflect 2026-10-11/12 iPhone 8 Plus tests:

- `searchd`: the new isolated Off/userspace-restart test reproduced a delayed locked-idle Photos CPU loop at about 106% of one core, with CoreSpotlight query-failure stacks. Earlier short checks missed this background trigger.
- `biomed`: SpringBoard/keyboard Biome metadata and lockfile errors with the service off.
- `syncdefaultsd`: provides `com.apple.kvsd`; multiple clients logged failed synchronized key-value-store access with it off.
- `imagent` and `identityservicesd`: keep enabled for Messages/iMessage/FaceTime.
- `nehelper` (plist filename alias `nehelper-embedded`): required by Identity Services to create its network interface. Its absence caused repeated identityservicesd aborts and a black Messages screen; enabling it restored conversations. It also serves other Network Extension clients.
- `mobile.lockdown`: paired USB tools failed when disabled and worked after restoration; keep enabled for pairing/computer backups.
- `pluginkit.pkd`: starting SpringBoard with it disabled reproduced continuous widget-extension discovery retries and about one CPU core of use. Restoring it and respringing returned idle SpringBoard to about 1.4% CPU. Its builtin target was already enabled; this was an additional manual disable.

Pkd, nehelper (including its filename alias), searchd, biomed, syncdefaultsd and mobile.lockdown are now Critical. The delayed searchd-Off Photos failure is now reproduced in an isolated comparison. Imagent, identityservicesd, absd, cdpd and followupd are also Critical after the account/SMS repair tests. Image/VideoConversionService, passd, ProtectedCloudKeySyncing, SecureBackupDaemon and contextstored are protected after the export, Store and cloud/scheduler comparisons. AccessibilityUIServer is optional and has no Recommended On badge. These classifications do not claim new bootloop risks. The earlier full-off profile passed user-confirmed basic usage after reboot, but logs were not clean and the >600 MiB physical-free idle target was not established. No broad performance or battery-life gain is claimed.

Custom target choices are stored separately from builtins. Legacy full-copy preferences migrate values differing from the old builtins as custom choices; inherited values adopt revised defaults. The old format cannot distinguish a deliberate choice equal to an inherited value.

General service batches save and verify native launchctl overrides, preserve root:wheel `0644` metadata and report failures; restart userspace for complete process changes. Single switches for the tested feature-host catalog also load/unload the selected feature job and verify its loaded state immediately. No polling worker or blanket dependency unloading is added.

## Build

On macOS with Xcode, XcodeGen, and ldid:

```sh
python3 -m unittest discover -s tests -v
xcodegen generate
xcodebuild -project DaemonApp.xcodeproj -scheme DaemonApp -configuration Release -sdk iphoneos -derivedDataPath build CODE_SIGNING_ALLOWED=NO
```

The GitHub Actions workflow builds and packages `DaemonApp.ipa`, embeds `DaemonManagerSourceCommit` in its Info.plist, uploads an artifact, and publishes the versioned release. Check the intended commit's successful run and the embedded revision before installing; do not assume a mutable release asset belongs to a particular source revision.

The app's embedded Python is compatible with the **Python 3.9.9** runtime verified on the target phone. Tests cover preset drift, critical defaults, rejected commands, verification mismatches, and timeouts. UIKit/SwiftUI compilation and device visuals require the macOS build and physical-phone verification.

## Install

Transfer the IPA to the phone using its current SSH address. On the tested rootless installation:

```sh
/var/jb/Applications/TrollStoreLite.app/trollstorehelper install force /path/to/DaemonApp.ipa
```

Discover the helper path on other installations. `appinst /path/to/DaemonApp.ipa` with AppSync Unified is an alternative. Neither installation nor launching the app automatically applies the presets. The emergency launchd reset resets overrides and needs a userspace restart; it is not an exact restoration of an earlier configuration.

## Service categories

**Critical** has a dedicated tab containing the installed services from the existing capital-`NO` classification, with disabled entries first. Membership is independent of override state; turning a critical service off never removes it from this category. Each description identifies the particular core functionality or stability risk; this category does not imply every service has a verified bootloop risk. Critical disables retain the existing confirmation, including when changing a default target.

The previous imagent/identityservicesd recommendations are now Critical under the tested SMS/account repair policy. No Recommended On entries remain in this revision. Critical means a documented core dependency/functionality concern, not necessarily a bootloop risk.

All 512 targets are compiled into the IPA. Defaults shows installed services plus missing builtin entries, clearly marked "Not found on this device"; applying targets acts only on installed services. Custom choices override the builtin targets. No config import is needed on a fresh installation; optional import/export remains available. Installation itself does not apply defaults or change the phone's saved overrides.

## Memory and list organization

Services groups non-critical entries first and critical entries at the bottom under every filter, including On. The separate Critical tab still retains its disabled-first ordering.

Tap the RAM indicator for system pressure, physical RAM, physical free, speculative, active/inactive/wired, purgeable, file-backed/anonymous memory, and compression statistics. Compressed occupancy is the physical RAM used by the compressor; original stored-page size and their ratio are shown separately. Overlapping categories are not additive. Values refresh on the existing two-second timer; failed reads show unavailable values.

The old header added speculative pages twice: XNU's `free_count` already includes them. It now displays `free_count`, while physical free is `free_count - speculative_count`. This corrects accounting and does not represent a performance change. See [Apple's iOS 16 kernel implementation](https://github.com/apple-oss-distributions/xnu/blob/xnu-8796.141.3/osfmk/kern/host.c) and [VM counter definitions](https://github.com/apple-oss-distributions/xnu/blob/xnu-8796.141.3/osfmk/mach/vm_statistics.h).

Pressure uses [Dispatch memory-pressure events](https://developer.apple.com/documentation/dispatch/dispatchsource/makememorypressuresource%28eventmask%3Aqueue%3A%29), seeded on opening/refresh by `kern.memorystatus_vm_pressure_level`. The current sysctl requires privilege on the tested iOS 16 phone, so the existing root credential is used once when needed. This is not periodic privileged polling. Returned flags are Normal=1, Warning=2, Critical=4; [the kernel exports dispatch flags, not its internal enum](https://github.com/apple-oss-distributions/xnu/blob/xnu-8796.141.3/bsd/kern/kern_memorystatus_notify.c). Unknown readings stay unknown; no pressure percentage is fabricated. The header color reflects the reported pressure instead of hardcoded free-RAM thresholds. Opening memory details never changes a daemon override.

## Wallpaper host and storage (v1.0.4)

The verified PosterBoard job is `/System/Library/LaunchAngels/com.apple.PosterBoard.plist`, label `com.apple.PosterBoard`, domain `user/501` on this phone (the app discovers the mobile UID). Killing its PID does not save an override. Native disable plus bootout stopped it and most associated poster extensions in the observed window. A userspace reboot preserved the off override; the user confirmed unlock, Home, Notes, and Messages work. The app exposes this job under Tools → Background UI and in Services, together with the tested AccessibilityUIServer host. Other untested LaunchAngels remain excluded. The compiled default keeps it enabled for other users; manual disabling remains available, and userspace restart fully applies it. Wallpaper control installs no auto-kill daemon, polling loop, file renaming, or arbitrary app blacklist.

Speculative pages are reclaimable kernel filesystem cache, not a separately disableable SysMain service. Disabling predictive daemons does not eliminate all speculative pages. No useful verified force-compress control was found; no induced memory pressure or forced app eviction is implemented. Core account daemons and siriactionsd retain their existing critical warnings; feature names alone do not establish safe disabling.

The storage driver advertises NVMe SMART capability, but read-only IOCreatePlugInInterfaceForService returned `0xe00002c7` on this device; lifetime writes/endurance/wear could not be obtained. The v1.0.4 capacity section was removed in v1.0.5. No terabyte-write lifetime or rated endurance is invented.

## System transitions and NAND diagnostics (v1.0.5)

Animation tweaks are installed and managed independently; v1.0.6 has no tweak-dependent animation controls.

The RAM panel now contains memory only. Tools → Disk diagnostics can read the latest completed sysdiagnose or collect a new one with `sysdiagnose -f /var/tmp/daemon-manager-diagnostics -n`. Collection takes several minutes; keep the app open. It temporarily enables/loads only sysdiagnose and its helper when necessary, restores originally disabled overrides afterward, and stops those originally disabled jobs. No reports upload automatically. Results remain on the phone; collection is on demand, never scheduled or performed during launch.

NAND health comes from `ASPSnapshots/asptool_snapshot.log`, including NUL-padded text. Exact field names are parsed; missing fields stay unavailable, and a failed collection never substitutes an older snapshot. The tested fresh report exposed `percentUsed=9`, average TLC cycles 92, native endurance cycles 1000, SLC cycles 8278 of 45000, and zero critical warning flags, grown bad blocks, retired blocks, and uncorrectable reads. These are driver counters, not a lifetime guarantee. Host/NAND writes remain raw counters because their byte units were not independently established for this controller. No conversion to TB, rated TBW, or remaining-years estimate is fabricated. Existing archived reports may also be read without collecting again. Both the new-report collection and restoration of all prior overrides were exercised on the phone.

The app icon uses the supplied frog sticker as a square, opaque 1024×1024 asset. Built-in imagegen edit prompt: “Center the original frog sticker on matching beige paper in a square canvas; preserve the frog, sunglasses, hoodie, teddy bear, white sticker border and colors; no text or rounded corners.” Source asset: `DaemonApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png`. Xcode generates the device sizes from this single-size catalog.

## Audit follow-up and app revision (v1.0.6)

Tools → Background UI now exposes PosterBoard and AccessibilityUIServer only. AccessibilityUIServer is **KEEP / Recommended On**, not capital NO; its builtin target is enabled. It remains freely switchable, including in Services. The tested phone retains its manual off override. Re-enable and restart userspace before using accessibility features. Installation never applies defaults. The config and IPA contain **506 targets: 320 off, 186 on**; biomed, syncdefaultsd and Messages dependencies remain enabled by default.

Basic usage passed on the tested phone after host disabling and reboot. Remaining CoreDuet, graphics, preferences and account errors were not eliminated; no battery-life or net RAM improvement was established. See the iOS reference for the measured audit and its limits.

Animation controls and their helper were removed from the app. The independently installed animation tweak is left active and managed outside this app. RAM remains memory-only. Disk write counters use grouped raw numbers and can be tapped for their meaning and conversion status. GB conversion remains unavailable: the ASP snapshot and installed diagnostic parser did not establish bytes per count; page size or generic NVMe units cannot substitute for that evidence. No guessed conversion is shipped.

The unsupported absd Contacts description and related database links were removed. Its actual plist exports com.apple.absinthed and com.apple.absd; the broader private role remains undocumented here. Verified Contacts database links remain for contactsd and ABDatabaseDoctor.

## SpringBoard CPU dependency fix (v1.0.7)

On 2026-10-12, the iPhone 8 Plus running iOS 16.7.16 had `com.apple.pluginkit.pkd` manually disabled and unloaded. SpringBoard PID 7778 consumed 5.153 CPU seconds in a 5.00-second targeted spindump (103.1% of one core). The hot stacks repeatedly entered `WGWidgetDataSourceManager _beginContinuousPlugInDiscovery`, ExtensionFoundation and PlugInKit, with `pkd_client` replies formatting errors and hundreds of discovery-driver queues. The shell's `ps` reported zero CPU/time for this process, so it was not used as the measurement.

Enabling and bootstrapping pkd alone left the existing SpringBoard retry loop running. After starting pkd in its observed `user/501` domain and respringing, a settled 15-second sample used 0.209 CPU seconds (1.4%), and the retry stacks disappeared. Unloading pkd from this already initialized SpringBoard did not reproduce the loop in a short sample. Disabling/unloading it and then respringing did: the new SpringBoard used 11.434 CPU seconds in 10.00 seconds (114.3%) with the same widget-discovery stacks. Pkd was restored and SpringBoard resprung again. The sole saved override changed was pkd; other manual choices and tweaks were retained.

This establishes the missing dependency as the trigger for the observed startup retry loop on this installation. It does not establish that every iOS version or tweak configuration behaves identically. Thermal pressure was still elevated during the immediate samples; no temperature decrease or battery-life gain is claimed. Unified log relay was unavailable, but the CPU counters and symbolicated client stacks were collected directly with spindump.

Version 1.0.7 marked pkd **Recommended On**; v1.0.8 promotes it to **Critical**. Its builtin/config target remains enabled. Explicit custom off choices remain editable; installation does not apply defaults or repair a live dependency automatically. Re-enable pkd and restart userspace to apply the process change fully. The repair on this phone loaded pkd and resprung SpringBoard; it did not reset the launchd database.

## Optional feature overrides (v1.0.8)

Overrides replaces the Config tab. Tools → Import / Export Config retains import, apply and export. Service descriptions appear without expanding rows; private roles without verified descriptions remain omitted. Installed labels that use the same verified executable/endpoints as known entries resolve through explicit description aliases. Critical enabled targets/exported entries use uppercase `NO`, which the importer already handles as enabled.

The tab exposes PosterBoard, PaperBoard, AccessibilityUIServer, LiveTranscriptionUI, AirDropUI, PassbookUISceneService, ShortcutsUI, ReplayKitAngel/replayd, and the existing chronod/liveactivitiesd controls. InputUI, shared OverlayUI, ClockAngel and MediaRemoteUI remain excluded. AccessibilityUIServer has no recommendation or critical badge; its existing default target stays enabled and it remains freely switchable. The six new host targets are optional-off except ShortcutsUI, which defaults On. The config/IPA now contain 512 targets, 325 Off and 187 On.

ReplayKit records/broadcasts the screen; Camera photos and Camera video recording use separate services. Enable both ReplayKitAngel and replayd for Screen Recording, and turn them off afterward when unused. Pkd remains Critical even with widget updates disabled because it brokers other app extensions too.

AirDropUI alone is not a complete AirDrop disable. The separate Allow AirDrop switch changes the native `allowAirDrop` feature setting and verifies `isAirDropAllowed`, keeping sharingd enabled for the normal Share Sheet. The signed on-demand helper has the feature-specific entitlement required by the observed profiled error; it runs only when reading/changing this switch. The wrapper temporarily enables/loads profiled when needed and restores its original saved override and loaded state on success, helper failure or timeout. No profile is installed and no managed-policy database is edited directly. The native API and entitlement were exercised on iOS 16.7.16; absent APIs and verification failures are reported rather than claimed as success.

Device testing disabled/unloaded AirDropUI, PassbookUISceneService, LiveTranscriptionUI and PaperBoard, then resprung and restarted userspace. Camera photos/videos passed user checks. The first Share Sheet lacked app extensions and Save to Files despite pkd/FileProvider running; a userspace restart restored them while these optional hosts remained off. A 10-second sample with the hosts off and Camera active used 0.348 SpringBoard CPU seconds, with thermal pressure 0. These workload-specific numbers are not a net RAM or battery-life gain. Initially the additional hosts had no running process and zero launches to reclaim.

The WhatsApp “Open Meta AI” Auto Shortcut separately returned NSCocoaErrorDomain 4097 from its application endpoint through linkd. Pkd, linkd, siriactionsd and ShortcutsUI were enabled. A userspace restart and restoring the four new optional UI hosts did not fix that action. The user verified Apple's Set Flashlight action works. The remaining WhatsApp failure has not been traced to a disabled service.

For manual packaging after the Xcode build, compile `helpers/airdrop-policy.m` with the iphoneos SDK, arm64, iOS 16 minimum, ARC and Foundation; place it as `airdrop-policy` inside DaemonApp.app and sign it with `helpers/airdrop-entitlements.plist`. The GitHub workflow performs these steps before packaging/signing the main app. Do not install a build missing this helper and expect the AirDrop policy control to work.

## Feature groups (v1.0.9)

Overrides now has group On/Off buttons for Wallpaper, Accessibility/captions, AirDrop, Wallet, Shortcuts, Screen Recording, Widget updates/Live Activities, Apple Account/settings sync, Messages/FaceTime, iCloud Drive, iCloud Photos, App Store/media purchases, and Contacts/calendars. All 40 listed job labels were found in this phone’s installed launchd plists. Jobs shared by several features appear in each relevant group, with one underlying saved override. Group status uses saved overrides, not proof of feature functionality. Missing jobs and mixed states remain visible.

Group On enables the feature jobs and disabled listed prerequisites. Group Off leaves Critical services and shared prerequisite-only jobs untouched. This preserves account authentication when optional account/sync jobs are turned off. Individual switches, including Critical services with the existing confirmation, remain available. The Swift policy checks verify Critical protection, shared prerequisites, deduplication, the recording pair, and the AirDrop policy group. Group actions do not change builtin/custom default targets.

The AirDrop group also changes and verifies the native Allow AirDrop setting after successful override commands. Groups consisting entirely of the 11 tested live jobs load/unload immediately; broader groups save overrides and explicitly require userspace restart. Shared prerequisites are never blanket hot-unloaded. Account sign-in, purchases, FaceTime calls and cloud sync were not functionally tested; these groups identify checked service roles and known prerequisites, not every OS dependency or a universal guarantee that enabling them is sufficient.

Screen Recording failed after restoring its jobs because SpringBoard retained an uninitialized ReplayKit client (`isAvailable=1`, `isInitialized=0`, connection error 4099). Explicitly starting replayd did not repair that client. Respringing with ReplayKitAngel/replayd enabled changed initialization to 1, and recording started and saved successfully. The user then repeated recording and the Photos Share Sheet with the eight unrelated optional jobs disabled; recording, Save to Files and WhatsApp sharing all passed. The recording group therefore tells users to enable both jobs and respring. Camera capture remained working separately. Both recording jobs were left disabled afterward, as requested.

TrollStore installation of v1.0.8 preserved the AirDrop helper’s feature entitlement. The packaged helper/wrapper completed read → on → off, verifying policy 0 → 1 → 0 and restoring profiled disabled/unloaded after every action. The user confirmed the new tab, inline descriptions and Tools file picker. Final SpringBoard sampling with recording/optional hosts off measured 0.004 CPU seconds over 5 seconds (0.08%), thermal pressure 0. No net RAM or battery-life gain is established. Widget-update controls do not remove configured widgets or disable every legacy widget path; pkd must remain enabled for other extensions and to avoid the reproduced CPU loop.

## Launch repair and compact header (v1.0.10)

v1.0.9 compiled and passed group checks but crashed when service descriptions initialized: a newly added FileProvider entry duplicated an existing dictionary key. v1.0.10 removes it. Python checks now reject duplicate description keys, and the Swift group test initializes the actual description dictionary. A successful uiopen request is not proof that an app stayed running; device launch verification follows installation.

Search and the memory number/theme switch now share one row in Services and Critical. The filter occupies the next row. Memory stays tappable for details and is displayed as the MiB number without a unit/label, circle or chevron. Critical red styling and individual confirmations remain; the pinned category headings and separate top bar are removed.

## Manual memory stress test (v1.0.11)

The Memory sheet provides +100 MiB, −100 MiB and Clear. Each plus maps a separate anonymous 100 MiB block and fills every byte with fresh arc4random_buf data in 1 MiB chunks on a serial worker. The varied content resists compression; it is not a repeated page or zero-fill. Between chunks the worker yields briefly, and cancellation checks let Clear or closing/backgrounding interrupt an unfinished fill. Held allocations are not continuously rewritten. Minus/Clear unmap blocks directly rather than retaining malloc caches. No root helper, permanent worker, memory-limit entitlement or Jetsam immunity is added.

App footprint is measured using TASK_VM_INFO.phys_footprint. App allocation headroom comes from os_proc_available_memory through the SDK os/proc.h interface, is advisory and is independent of device free memory. Values update while the Memory sheet is open, with the existing two-second memory sampling. An allocation syscall failure is shown; iOS can still terminate the app while committing pages. Clear, Done, sheet dismissal and backgrounding release test allocations. This feature creates memory pressure; it does not add RAM or establish a performance/battery benefit.

Focused Swift tests check different block contents, compression resistance, add/minus/clear accounting, cancelled partial mappings, invalid requests and live footprint reads. Native iPhone allocation/lifecycle behavior must also be verified after installation.

## Overrides subpages (v1.0.12)

Overrides is a compact navigation menu with one entry and saved-state summary per feature group. Each subpage contains that group’s On/Off controls, explanations, services and restart actions. AirDrop policy controls appear only on the AirDrop page. Individual Critical disables retain the MainView confirmation. Subpage navigation does not change service defaults or saved overrides.

As of v1.0.12, feature coverage remained limited: on-device checks covered Camera photos/video, the Photos Share Sheet including Save to Files and WhatsApp, a built-in Set Flashlight shortcut, Screen Recording restored after respring, native AirDrop policy toggling, and allocation/minus/Clear/sheet-close memory controls. At that revision, account sign-in, cloud sync, purchases, FaceTime and an exhaustive service-combination stress test had not passed device verification. Inspecting plists, passing build tests, and high-memory allocation are not equivalent to proving those features work. The WhatsApp Meta AI action remains unresolved.

## Apple Account and SMS repair (v1.0.13)

The user’s post-disable profile blocked Settings at the Apple ID Next step. Logs named a missing com.apple.ak.auth.xpc endpoint; akd/adid were saved enabled but unloaded, while appleaccountd was disabled. Enabling these jobs and restarting userspace restored the password/two-factor stage. Thus a saved On state alone was insufficient; the loaded jobs and fresh clients mattered.

CommCenter received carrier SMS while imagent was disabled, but verification delivery failed. Enabling/loading imagent and respringing restored the user-confirmed SMS code. With absd disabled, AppleAccount logged NAC/Absinthe -44303/-4403 and an iCloud login request returned HTTP 400. This job exports com.apple.absinthed. Enabling/loading only absd and respringing changed NAC initialization to success. Its verified description now covers this authentication dependency; the old Contacts attribution remains removed.

The user still saw a later server/verification error. AuthKit logged unavailable CoreCDP, CoreFollowUp and Identity Services connections, plus SRP network resets/timeouts. Restoring cdpd, followupd and identityservicesd together and restarting userspace was followed by user-confirmed successful sign-in. AppleAccount logged LoginAndUpdateAccount Authenticated=1/error=0; Messages and FaceTime service sign-ins also logged success. This proves the repaired profile completed sign-in, not that any one of the final three services caused the preceding network error. No individual causal isolation or actual FaceTime call is claimed.

The tested account group now includes appleaccountd/accountsd, akd, adid, absd, cdpd, followupd, identityservicesd, imagent (for SMS codes), syncdefaultsd and apsd, plus its optional sync/media jobs. On restores the listed jobs; a userspace restart is required after saved batch changes. Off preserves Critical account/SMS dependencies. Each individual Critical switch remains editable with its warning. Absd, cdpd and followupd now default On; the matching config contains 512 targets, 322 Off and 190 On, with uppercase NO for all Critical enabled entries. Explicit custom Off choices remain explicit, so installation does not silently override them.

The user confirmed v1.0.12 subpages and Back navigation. After account repair, the user reported WhatsApp closing from the Photos Share Sheet chat picker; investigation is ongoing, so the earlier sharing pass does not establish current reliability. Other functional checks remain separate from account sign-in: iCloud file/photo sync, App Store downloads and real FaceTime calls must still be exercised. No exhaustive combination stress test or net RAM/battery gain is claimed. A pre-repair memory sample found larger suspended apps (Sudoku ~295 MB, Sileo ~108 MB, WhatsApp ~101 MB) and mostly small remaining optional helpers; it did not establish another safe daemon disable.

## Photos sharing repair (v1.0.14)

After account sign-in, a Photos → WhatsApp attempt displayed Unable to Share while preparing the attachment. Logs explicitly named unavailable com.apple.photos.ImageConversionService (XPC lookup error 3, NSCocoaErrorDomain 4099), followed by failed image conversion and asset export. Restoring only this job and respringing was followed by user-confirmed successful sharing for the Camera photo/screenshot test. It is now Critical and defaults On; explicit custom choices remain editable. Photos sharing and export has a separate Overrides subpage, whose Off policy preserves both conversion dependencies. With the image repair retained, a Camera video independently failed with an explicit missing VideoConversionService XPC error. Restoring only the video job and respringing restored user-confirmed video sharing. VideoConversionService is therefore also Critical/default On. The group Off button is unavailable when all feature jobs are Critical; individual warned toggles remain available. This does not establish the cause of the earlier chat-picker disappearance or prove every format works. Current config: 512 targets, 320 Off / 192 On.

## App Store confirmation repair (v1.0.15)

Get briefly spun and returned without downloading. Logs showed HTTP 200 followed by Payment Sheet Failed. Restoring amsengagementd alone and respringing did not fix it: PassKit then explicitly failed lookup of com.apple.passd.in-app-payment. Restoring only passd and respringing restored the password/confirmation sheet, download, installation and user-confirmed launch of a free app. The Wallet interface override remained disabled; the separately launched PassbookUIService handled the download confirmation. Turning amsengagementd back off and respringing still allowed a second new free app to download and open. Its missing engagement messages therefore do not by themselves establish a failed download. It remains optional, with a corrected description of its actual exported endpoints.

Passd is now Critical/default On and included as a shared App Store prerequisite. Wallet group Off preserves it and can still disable PassbookUISceneService. Individual disabling remains available. Paid purchases, Apple Pay and Wallet passes were not exercised. Current config: 512 targets, 319 Off / 193 On. FaceTime calls could not be tested because no contact was available; avconferenced was returned to its original Off state. iCloud sync testing is ongoing.

Overrides feature-menu rows also have direct On/Off buttons alongside the navigation link, using the same batch policy as the subpage. Groups with no noncritical feature jobs have their Off button disabled; individual Critical switches remain available inside. ProtectedCloudKeySyncing is now Critical and included in the account, Drive and Photos groups after explicit CloudDocs user-key/zone preparation failure with its endpoint disabled. Its builtin target was already On; this was another manual disable. Full cloud sync is still being verified after restoring the job and restarting userspace.

The protected-cloud-key service became reachable after restoration/userspace restart but initially rate-limited another attempt for two hours. For diagnosis, only its nextRegistrySync retry deadline was removed using mobile-user CFPreferences, then the job was restarted; no cloud keys, credentials or account stores were deleted. That immediate attempt reached FetchMetaData and explicitly failed because com.apple.SecureBackupDaemon was disabled/unavailable. SecureBackupDaemon is now also Critical/default On and a shared account/Drive/Photos prerequisite. The account notice continued to request sign-in despite user retries before this second dependency was restored. Restoring SecureBackupDaemon and requesting another key-sync retry changed SynchronizeKeys completion to success in logs. The user then completed the account verification prompt and confirmed its notice cleared; Drive/Photos still appeared stalled, and the user started another userspace reboot. Full file/photo sync remains pending verification. Current config: 512 targets, 318 Off / 194 On. The retry-deadline diagnostic is not an automatic app operation.

## Photos scheduler dependency (v1.0.16)

After protected key recovery and account verification, Drive displayed existing files and a photo saved into Drive was visible on the web and downloaded intact. The initial Save to Files attempt unexpectedly returned Home; a second attempt passed, and that transient failure remains unisolated. Photos still stalled in setup with CoreDuet context errors. The endpoint com.apple.coreduetd.context belongs to contextstored, not duetexpertd. Restoring only contextstored and restarting userspace removed the context failures; after the scheduled retry, the user confirmed two fresh photos synced and were present on iCloud.com.

Turning only contextstored back off and restarting userspace reproduced a new photo upload stall. DAS logged failed context reads and Must Not Proceed from DataBudgetPolicy and NetworkQualityPolicy, with observed Wi-Fi quality 0 and insufficient budget; the restart-related ThunderingHerdPolicy was no longer listed as a blocker. Contextstored is now Critical/default On, and the Photos group includes it and the existing Critical dasd. It is not merely a Siri suggestions backend. Contextstored is restored for the final recovery comparison. Current config: 512 targets, 317 Off / 195 On. The user requested Drive/Photos sync jobs be returned Off after tests, while the repaired Critical dependencies remain enabled. These staged checks do not prove every service combination, paid purchase, FaceTime call or net RAM saving.

## Final device verification — v1.0.16

Restoring contextstored again and restarting userspace completed the same third photo’s upload after the queued retry. A further Save to Files → iCloud Drive test succeeded and was visible on the web. The user then enabled Drive and Photos using the direct menu On buttons, restarted userspace through Tools, and reported the fresh-restart cloud checks passed. Finally, both direct menu Off actions followed by userspace restart left bird, cloudd, cloudphotod and assetsd.nebulad disabled/unloaded, while account, key-recovery, context and scheduling prerequisites stayed enabled/loaded. The earlier isolated return to Home did not recur in these subsequent checks; its exact cause was not isolated.

AirDrop policy remained false. ReplayKit recording, widgets/Live Activities, wallpaper/captions/Wallet interface hosts, amsengagementd and avconferenced stayed Off. Temporary diagnosticd/ReportCrash jobs and the on-demand profiled check were restored disabled/unloaded. Compared with the pre-test saved profile, the only retained changes enable these 12 repaired Critical jobs: appleaccountd, absd, cdpd, followupd, identityservicesd, imagent, ImageConversionService, VideoConversionService, passd, ProtectedCloudKeySyncing, SecureBackupDaemon and contextstored. Akd/adid were already saved On and were reloaded earlier.

A settled 15.00-second spindump measured SpringBoard at 0.015 CPU seconds (0.10% of one core), normal thermal pressure 0, and contextstored at 0.008 CPU seconds with a 6,880 KB footprint. This is a short settled sample, not a battery-life or net-RAM benchmark. FaceTime calls, paid purchases/Apple Pay, complete service-combination stress coverage and the WhatsApp Meta AI shortcut remain unverified or unresolved. Earlier memory tests verified allocation/minus/Clear/sheet-close controls; high allocation did not establish full-system reliability.

Installed package: v1.0.16/build 17, source 0f730f88a1e417af877dc53e23084103b2656b74. Actions run 38229538314 passed 20 Python checks, Swift memory/stress/group checks and iOS compilation/packaging. IPA SHA256 67024e577f83ce2e62c08d24d405619edd40f1234b771ee44d2c50f7aeb1a284 matched the release digest and embedded version; TrollStore installation returned 0, installed Info.plist matched, launch was verified and both menu button directions were used on-device.


## Lock Screen media controls (v1.0.17)

On the tested iOS 16.7.16 phone, Control Center playback controls worked with PosterBoard, PaperBoard and liveactivitiesd off, but the Lock Screen/Notification Center playback panel was absent in VLC and Pocket Casts. Restoring PosterBoard or PaperBoard individually with liveactivitiesd still off did not recover it. Restoring profiled alone and restarting mediaremoted also did not recover it; mediaremoted and MediaRemoteUI were already enabled.

Restoring liveactivitiesd brought the panel back. Turning it off again and respringing removed it. With liveactivitiesd on and PosterBoard off, the panel flashed/turned grey; MediaRemoteUI repeatedly terminated with CALayerInvalidGeometry in MRUArtworkView, including during Pocket Casts audio playback. Restoring PosterBoard together with liveactivitiesd and restarting userspace produced clear, user-confirmed controls; MediaRemoteUI remained running with one launch and no captured rendering exception. PaperBoard remained off. The invalid geometry is the recorded exception, not an explanation of Apple's internal rendering implementation.

Overrides → Lock Screen media controls groups PosterBoard and liveactivitiesd with complete On/Off buttons on the menu and its subpage. Both remain optional and default Off, as requested. PosterBoard is shared with Wallpaper; disabling that group can also break media rendering. Widget updates now controls chronod separately and preserves pkd. Restart userspace after changing the media group: resprings did not consistently clear the repeated UI failures. Turning this feature off intentionally removes its panel; keeping liveactivitiesd on while PosterBoard is off produced repeated UI crashes in this test profile.


The installed v1.0.17/build 18 menu controls passed an Off → userspace restart → absent panel test, followed by On → userspace restart → clear working panel, with PaperBoard still Off and MediaRemoteUI running with one launch. A final menu Off and restart returned all three hosts disabled/unloaded. Temporary diagnostics were restored Off; the final system/user-501 disabled maps exactly matched the saved profile from before this investigation. A 5.00-second final sample measured SpringBoard CPU at 0.015 seconds (0.30% of one core), footprint 60.92 MB; this is not a comparative net-RAM or battery benchmark.

Build source: 345755614b69698b222f8deb13affc510369b964; Actions run 38235699744 passed the 20 Python checks, Swift group/memory/stress checks and iOS compilation/packaging. IPA SHA256 8d04b27e62cd4463828392659e21f41323003f81ecafef263c6e42ca7c3a39a4 matched the release digest and embedded source/version. TrollStore installation returned 0 and the installed version/source matched. App and notes configs match 512 targets, 318 Off / 194 On. Notes were left unstaged for user review.


## SpringBoard interface controls (v1.0.20)

Overrides → SpringBoard interfaces exposes menu On/Off buttons, an individual-switch subpage and removal. A small rootless SpringBoard-only companion blocks Control Center presentation/gestures and App Library capability checks. These are UI access controls, not separate launchd jobs; reduction in allocated RAM has not been established. Respring after changes. The page compares saved flags with the companion’s report for the current SpringBoard PID.

The companion loads settings once per SpringBoard launch, installs only selected hooks and adds no timer, worker process or per-app injection. Private method names/types were verified on the actual iPhone 8 Plus running iOS 16.7.16 with ElleKit 1.2. Missing/mismatched methods are reported unsupported. Remove interface controls deletes its filter/library and saves both interfaces On; respring clears existing hooks. All 512 daemon targets remain unchanged.

The original prototype passed Off/On phone checks. The packaged v1.0.18 wrote to the bootstrap account home `/var/jb/var/mobile`, while SpringBoard used the native `/var/mobile`, so its Off button did not apply. The corrected script writes/reads the native path, using the account database only for ownership. With that correction and a respring, the device report showed every requested hook active and the user confirmed the interfaces were gone. A regression test uses different native and bootstrap homes.

Dock and status-bar switches and their layout hooks were removed at the user’s request because they only hid views. Today View’s attempted hooks did not remove its far-left page; they were removed too. Keep pkd enabled to avoid the previously measured extension-discovery CPU loop. The memory allocator remains a stress-test tool, not a persistent RAM booster.


The installed v1.0.20/build 21 app passed All On → respring → both interfaces available, followed by Off → respring → both inaccessible, confirmed by the user. Dock/status bar were restored and their switches removed. Final saved settings and current-PID runtime report both have Control Center/App Library disabled. CI run 38244546744 passed 23 Python tests, Swift memory/stress/group checks and iOS build/package. Source ca663064295eb14b72a669ececcfcf37eeda7277; IPA SHA256 35e71d9caee42bc50b7e251d69633b10420ebf44ca925c2fbb101d33c6d4bdca matched the release digest and embedded source/version; TrollStore returned 0 and the app process was observed running. Both saved launchd domains matched the pre-interface profile exactly. A settled 10-second sample measured SpringBoard at 0.010 CPU seconds (0.10% of one core), footprint 64.13 MB. That is not a comparative RAM/battery benchmark or exhaustive stress proof.


## USB and wired accessories (v1.0.21)

Overrides adds a menu/subpage group for AFC file access, app-container file sharing, host notification proxies, accessory/iAP protocols and USB network-interface setup. On restores nine optional jobs and shared Critical lockdownd/OpenSSH prerequisites; Off preserves the latter two. Defaults and daemon.cfg remain unchanged. Restart userspace after group changes. The grouped jobs are related host features, not a claim that every one is needed for USB SSH. Backup/restore, wired audio and every accessory protocol are not fully tested.

On 2026-10-13, the computer initially saw no Apple USB device, and the phone did not charge from the computer. Rebuilding the previous USB daemon did not restore detection. The user reset native overrides and restarted userspace; USB enumeration and authenticated SSH then worked. Lockdownd was already running before the reset. The reset's complete disabled.backup contains 344 entries; the reset/restart changed many jobs at once, so it does not isolate a single failing service. A subsequent comparison disabled all nine optional group jobs, restarted userspace and still passed USB SSH plus paired ProductType/ProductVersion queries, with all nine jobs unloaded and lockdownd/OpenSSH loaded.

### Original Linux USB tunnel commands

The original host daemon could not load libplist-2.0.so.4 while the installed libplist provided .12. These recorded commands rebuilt upstream revision 3ded00c9985a5108cfc7591a309f9a23d57a8cba against the installed libraries, without installing over the packaged daemon:

```sh
git clone --depth 1 https://github.com/libimobiledevice/usbmuxd.git /mnt/zram1/daemon-manager-usbmuxd-src
cd /mnt/zram1/daemon-manager-usbmuxd-src
./autogen.sh --without-preflight --without-systemd
make -j4
sudo ./src/usbmuxd -f -v -U usbmux
```

Leave the foreground daemon running. In another terminal the original port-forward command was:

```sh
iproxy 2222:22
```

The original authenticated SSH command was:

```sh
ssh -p 2222 -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
  -o ControlMaster=yes -o ControlPath=/mnt/zram1/daemon-manager-usb-ssh.sock \
  -o ControlPersist=600 root@127.0.0.1
```

Passwords are entered at prompts. The temporary directory disappears when zram storage is recreated. On the 2026-10-13 replay, the packaged daemon was already running, so it was stopped with `sudo systemctl stop usbmuxd.service` before starting the foreground build. The existing `iproxy -s 127.0.0.1 2222:22` was reused. The rebuilt daemon initially reported 0 devices and SSH reset; after the user's reset/restart, authenticated USB SSH succeeded. These host commands cannot restore a phone that never enumerates on the USB bus.

Installed-menu validation completed: On → userspace restart loaded all nine jobs, preserved lockdownd/OpenSSH and passed authenticated USB SSH, paired ProductType queries and BatteryIsCharging=true. Menu Off → restart then unloaded all nine, with the same SSH/paired queries and charging still working. The user also confirmed charging in the Off state. Final system and user/501 maps differ from the post-reset baseline only by those nine optional Off entries. Other reset-era service choices were left unchanged. Group Off is the final tested state; builtin targets/config were not changed. These checks do not test every accessory or backup protocol and do not identify the original missing-enumeration cause.

Deployment: v1.0.21/build 22, source 7e00c5a03d7b22955a952cde7343bad7b92d3c4f, Actions 38381048707 passed 23 Python checks, Swift feature/memory/stress checks and iOS compilation/packaging. IPA SHA256 abb7db08b10703d0b7e4e5d96f897507152ece02b579b3615095b5fbaaac345b matched release digest and embedded source/version. TrollStore returned 0, installed version/source matched, and installed group menu actions were verified through saved and loaded job states after restarts.
