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
            precondition(off.allSatisfy { !SafetyManager.isCritical($0) }, "Group Off included a Critical service: \(group.title)")
            precondition(Set(group.dependencies).subtracting(group.labels).isDisjoint(with: off), "Group Off included a shared prerequisite")
            precondition(Set(group.allLabels).count == group.allLabels.count)
        }
        let recording = OverrideServices.groups.first { $0.title == "Screen recording" }!
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
        print("Feature group policy checks passed")
    }
}
