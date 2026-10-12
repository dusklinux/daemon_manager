# Daemon Manager

SwiftUI service/preset manager for jailbroken iOS 16+, built with XcodeGen and installed with TrollStore Lite or AppSync Unified.

Known service descriptions are visible directly in Services, Defaults and Overrides. Tap the name or chevron for warnings, launchd plist/executable paths and related file metadata where verified. Contacts-related services show the address-book database paths, sizes, and modification dates without reading contact records. Uncertain private roles are omitted. The independent switch edits the saved launchd override; restart userspace for full loaded-process changes.

The tab bar has an opaque standard and scroll-edge appearance from initial launch. Search, the available-memory number (MiB, displayed without a unit or label), and the theme switch share one row. The filter is the second row; pinned category headings and the separate top memory bar are removed. Memory is kernel free memory including speculative pages, with each page counted once. Tap the number for the live memory sheet.

`daemon.cfg` matches all **512 builtin targets: 325 off, 187 on**. `yes` = disabled override; `no` = enabled override; uppercase `NO` = critical, keep enabled. All entries remain manually configurable. Critical includes measured CPU, repeated crashes and core dependency failures; it does not mean every member causes a bootloop. The classifications reflect 2026-10-11/12 iPhone 8 Plus tests:

- `searchd`: repeated Photos Spotlight retries and sustained CPU during broad live unloading; fresh boot and a short single-service comparison did not reproduce it, so causality remains unproven.
- `biomed`: SpringBoard/keyboard Biome metadata and lockfile errors with the service off.
- `syncdefaultsd`: provides `com.apple.kvsd`; multiple clients logged failed synchronized key-value-store access with it off.
- `imagent` and `identityservicesd`: keep enabled for Messages/iMessage/FaceTime.
- `nehelper` (plist filename alias `nehelper-embedded`): required by Identity Services to create its network interface. Its absence caused repeated identityservicesd aborts and a black Messages screen; enabling it restored conversations. It also serves other Network Extension clients.
- `mobile.lockdown`: paired USB tools failed when disabled and worked after restoration; keep enabled for pairing/computer backups.
- `pluginkit.pkd`: starting SpringBoard with it disabled reproduced continuous widget-extension discovery retries and about one CPU core of use. Restoring it and respringing returned idle SpringBoard to about 1.4% CPU. Its builtin target was already enabled; this was an additional manual disable.

Pkd, nehelper (including its filename alias), searchd, biomed, syncdefaultsd and mobile.lockdown are now Critical. Searchd retains its explicitly unproven single-service CPU causality. Imagent and identityservicesd remain optional-feature recommendations. AccessibilityUIServer is optional and has no Recommended On badge. These classifications do not claim new bootloop risks. The earlier full-off profile passed user-confirmed basic usage after reboot, but logs were not clean and the >600 MiB physical-free idle target was not established. No broad performance or battery-life gain is claimed.

Custom target choices are stored separately from builtins. Legacy full-copy preferences migrate values differing from the old builtins as custom choices; inherited values adopt revised defaults. The old format cannot distinguish a deliberate choice equal to an inherited value.

General service batches save and verify native launchctl overrides, preserve root:wheel `0644` metadata and report failures; restart userspace for complete process changes. Single switches for the tested Overrides catalog also load/unload the selected feature job and verify its loaded state immediately. No polling worker or blanket dependency unloading is added.

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

**Recommended On** services have orange guidance and toggle directly without the critical confirmation. Imagent and identityservicesd remain recommendations for optional Messages features. Nehelper is Critical because its absence reproduced repeated Identity Services crashes; this is not a bootloop claim.

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

Feature coverage remains limited: on-device checks cover Camera photos/video, the Photos Share Sheet including Save to Files and WhatsApp, a built-in Set Flashlight shortcut, Screen Recording restored after respring, native AirDrop policy toggling, and allocation/minus/Clear/sheet-close memory controls. Account sign-in, cloud sync, purchases, FaceTime and an exhaustive service-combination stress test have not passed device verification. Inspecting plists, passing build tests, and high-memory allocation are not equivalent to proving those features work. The WhatsApp Meta AI action remains unresolved.
