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
        print("Feature group policy checks passed")
    }
}
