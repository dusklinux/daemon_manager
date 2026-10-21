# Focused SMS/contact and Settings repair — 2026-10-21

## Scope and provenance

Owner requested Background Sounds/hearing and drag-and-drop default On with
optional group controls, carrier SMS recovery, responsive information buttons,
and Apple Account sign-in. Existing optional account/cloud/store policy is retained.
No broad re-audit or Apply Defaults was performed.

Device: iPhone10,2, iOS 16.7.16/20H392, palera1n rootless. USB SSH uses existing
port 2222, mobile key authentication and interactive sudo. Direct root password
authentication failed; credentials were not modified. Only userspace was restarted.
Installed Daemon Manager was v1.0.33/build 34, source
`cd9896de940ca70220b419faff4c6baf6153c540`. Prepared source is v1.0.34/build 35;
it is not yet built/installed. App/source and relevant note diffs were recorded
before edits. The owner subsequently authorized publishing and installing these updates without repeated approval; build/deployment results will be recorded below.

## SMS/contact isolation

Before the diagnostic batch, CommCenter logged receipt of fresh regular SMS,
but the native Messages database remained at seven rows. No message bodies or
addresses are included here. The existing critical and account/SMS brokers were
enabled/registered; an enabled on-demand job without a PID was not treated as Off.

The owner requested batch testing and bisection. Twelve previously disabled jobs
were enabled together, followed by userspace restart:

* security.cloudkeychainproxy3, security.CircleJoinRequested,
  keychainsharingmessagingd, purplebuddy.budd, itunescloudd, cloudpaird;
* networkserviceproxy, captiveagent, cmfsyncagent, ind, and, DMHelper.

All labels above have the `com.apple.` prefix. Native overrides were verified
after each change. The test sequence was:

| Enabled diagnostic candidates | Owner's fresh functional result |
|---|---|
| All 12 | SMS and Wi-Fi info work; Apple sign-in remains stuck |
| Last six listed above | SMS and Wi-Fi info work |
| networkserviceproxy + captiveagent + cmfsyncagent | SMS and Wi-Fi info work |
| None, restoring original Off states | SMS missing again; recent-call/contact info button also fails |
| Only cmfsyncagent | SMS, recent-call/contact info and Wi-Fi info all work |

Thus cmfsyncagent was isolated as an addition needed for the tested SMS/contact
paths, with the other 11 candidates Off. CommunicationsFilter client/server logs
also show MobilePhone receiving replies from CMFSyncAgent in the restored profile.
This does not certify all blocked-contact synchronization or independently prove
the original intermittent Wi-Fi delay had the same cause. No RAM/battery gain
was measured. The other 11 candidate overrides were restored to their original
disabled values, preserving the owner's prior account/store and drag/drop choices.

## Source changes

Builtin/config Off-to-On: accessibility.heard, DragUI.druid and cmfsyncagent.
513 preset entries now comprise 328 Off / 185 On, including 58 Critical On;
aliases mean these are not unique installed-job counts. Critical policy is unchanged.

Background sounds and hearing and Drag and drop are separate optional Groups.
Both follow the existing userspace-restart path. cmfsyncagent is Recommended On
and a prerequisite restored by Calls and SMS, Messages and FaceTime, and Apple
Account and settings sync. Their Off actions preserve it for shared contact/filter
clients; the individual daemon switch remains available. Its description now records
the reproduced SMS/contact dependency. Explicit custom defaults remain authoritative;
the historical full-copy migration's original reference values are unchanged.

All 33 local Python tests passed. New native Swift policy assertions cover the
feature groups/defaults, legacy explicit-choice preservation and CommunicationsFilter
On/Off prerequisite handling. Native Swift execution and full IPA build require
the macOS build workflow and have not yet run for this source.

## Separate Apple sign-in UI fault

Authentication logs show successful SRP/password exchange and receipt of Apple's
next RemoteUI model. Settings then stalled presenting it. A three-second targeted
spindump, symbolicated on the device, found the main thread waiting for CA's render
queue. That queue was loading the Metal device bundle and waiting in
`_CFXNotificationPost` / `-[NSOperation waitUntilFinished]`.

Duskie's SettingsOrganizer registered NSBundleDidLoadNotification with a synchronous
main-operation-queue observer. This creates the captured circular wait when bundle
loading occurs on the rendering queue. A native regression fixture explicitly loads
the real Settings library with ordinary tweak injection disabled, posts that
notification on a worker, and bounds the main thread's wait at two seconds.
It fails with the exact installed library and passes with the corrected library.
The fix receives the notification on its posting thread and asynchronously schedules
the existing main-thread UI refresh; no service toggles are involved.

Original DuskieSettings SHA256:
`33184c5e362c1b0519590d5d9c1e7eb6d4b4073d25bbe4a322c41e26aff8f4c6`.
It matches the pre-existing signed development payload. The focused library was
cross-compiled with Clang 23.1.3 and the existing SDK (reports 16.4), signed on the
phone, installed with root:wheel/0755 and an atomic rename, then Settings was
terminated/reopened. Installed bytes match the signed candidate, SHA256:
`b272952fb1dfd9940941836009c842864f2587323c983c62915eb5868f364e12`.
This is a local Duskie library hotfix; Debian package metadata is unchanged, so
reinstalling an older package can replace it. Source and regression fixture reside
in the Duskie checkout. The owner confirmed the code-entry page appeared and Apple Account sign-in completed smoothly after this fix.
Apple had also reported excessive verification-code requests during earlier attempts.
Do not treat that server response as evidence of another disabled daemon.

## Private evidence and restoration

Original native overrides, app preferences and DuskieSettings library are preserved
on the phone under `/var/mobile/Documents/daemon-fixes-2026-10-21`.
Raw logs, samples and local before-file snapshots are private under
`/mnt/zram1/daemon-fixes-private-puuric3y`, outside this repository. They can contain
account or message metadata and must not be published as audit attachments.

Both owned relay captures were stopped and temporary diagnosticd was restored disabled/unregistered. The verified final semantic override difference from the immediate pre-batch backup is exactly cmfsyncagent enabled; override-file metadata remains root:wheel/0644. SMS database metadata advanced to row 16 after fresh delivery and sign-in tests. Raw message content was not inspected.
