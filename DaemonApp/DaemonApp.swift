import SwiftUI

@main
struct DaemonAppEntry: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(model)
                .preferredColorScheme(model.isDarkTheme ? .dark : .light)
        }
    }
}
