# Daemon Manager

SwiftUI service/preset manager for jailbroken iOS 16+, built with XcodeGen and installed with TrollStore Lite or AppSync Unified.

Tap a service name or chevron for its known description, launchd plist and executable paths, and related file metadata where verified. Contacts-related services show the address-book database paths, sizes, and modification dates without reading contact records. Uncertain private roles are omitted. The independent switch edits the saved launchd override; restart userspace for full loaded-process changes.

The tab bar has an opaque standard and scroll-edge appearance from initial launch. RAM displays only the value and unit, for example **365 MiB**. The header is kernel free memory including speculative pages, with each page counted once. Tap it for a live memory sheet.

`daemon.cfg` matches all 506 builtin targets: **320 off, 186 on**. `yes` = disabled override; `no` = enabled override. All entries remain manually configurable. Existing critical warnings are retained; the following orange **RECOMMENDED ON** recommendations reflect a 2026-10-11 iPhone 8 Plus test:

- `searchd`: repeated Photos Spotlight retries and sustained CPU during broad live unloading; fresh boot and a short single-service comparison did not reproduce it, so causality remains unproven.
- `biomed`: SpringBoard/keyboard Biome metadata and lockfile errors with the service off.
- `syncdefaultsd`: provides `com.apple.kvsd`; multiple clients logged failed synchronized key-value-store access with it off.
- `imagent` and `identityservicesd`: keep enabled for Messages/iMessage/FaceTime.
- `nehelper` (plist filename alias `nehelper-embedded`): required by Identity Services to create its network interface. Its absence caused repeated identityservicesd aborts and a black Messages screen; enabling it restored conversations. It also serves other Network Extension clients.
- `mobile.lockdown`: paired USB tools failed when disabled and worked after restoration; keep enabled for pairing/computer backups.

These recommendations do not claim new bootloop risks. The earlier full-off profile passed user-confirmed basic usage after reboot, but logs were not clean and the >600 MiB physical-free idle target was not established. No broad performance or battery-life gain is claimed.

Custom target choices are stored separately from builtins. Legacy full-copy preferences migrate values differing from the old builtins as custom choices; inherited values adopt revised defaults. The old format cannot distinguish a deliberate choice equal to an inherited value.

Routine single and batch actions use and verify native launchctl overrides, preserve root:wheel `0644` metadata for the tested persistence workflow, and report failures. They do not rewrite the launchd database directly or hot-unload dependencies. Restart userspace to apply process changes fully.

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

**Recommended On** services have orange guidance and toggle directly without the critical confirmation. Messages dependencies are recommendations, not newly classified bootloop services. Their explanations document feature and dependency consequences, including repeated Identity Services crashes if nehelper is disabled while Identity Services is enabled.

All 506 targets are compiled into the IPA. Defaults shows installed services plus missing builtin entries, clearly marked "Not found on this device"; applying targets acts only on installed services. Custom choices override the builtin targets. No config import is needed on a fresh installation; optional import/export remains available. Installation itself does not apply defaults or change the phone's saved overrides.

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
