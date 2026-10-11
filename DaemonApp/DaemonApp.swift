import SwiftUI
import UIKit

@main
struct DaemonAppEntry: App {
    @StateObject private var model = AppModel()

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .secondarySystemBackground
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(model)
                .preferredColorScheme(model.isDarkTheme ? .dark : .light)
                .statusBarHidden(true)
        }
    }
}
