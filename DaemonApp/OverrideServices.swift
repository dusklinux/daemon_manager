import Foundation

struct OverrideGroup: Identifiable {
    let title: String
    let labels: [String]
    var id: String { title }
}

enum OverrideServices {
    // Only the feature hosts exercised on the iOS 16 test phone.
    static let groups = [
        OverrideGroup(title: "Wallpaper", labels: ["com.apple.PosterBoard", "com.apple.PaperBoard"]),
        OverrideGroup(title: "Accessibility and captions", labels: ["com.apple.AccessibilityUIServer", "com.apple.livetranscriptionui"]),
        OverrideGroup(title: "AirDrop interface", labels: ["com.apple.sharing.airdropui"]),
        OverrideGroup(title: "Wallet interface", labels: ["com.apple.PassbookUISceneService"]),
        OverrideGroup(title: "Shortcuts interface", labels: ["com.apple.ShortcutsUI"]),
        OverrideGroup(title: "Screen recording", labels: ["com.apple.replaykitangel", "com.apple.replayd"]),
        OverrideGroup(title: "Widget updates and Live Activities", labels: ["com.apple.chronod", "com.apple.liveactivitiesd"])
    ]
    static let labels = Set(groups.flatMap(\.labels))
}
