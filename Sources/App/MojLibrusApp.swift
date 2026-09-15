import SwiftUI

@main
struct MojLibrusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(SubjectColors.shared)
                .environment(TabLayout.shared)
                .tint(.accentColor)
                .preferredColorScheme(appearance.colorScheme)
                .task { BackgroundRefresh.scheduleIfEnabled() }
        }
    }
}
