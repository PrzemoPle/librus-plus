import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch app.phase {
            case .loading:
                LaunchView()
                    .transition(.opacity)
            case .loggedOut:
                LoginView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .loggedIn:
                if let repo = app.repository {
                    // Keyed on the child: switching rebuilds the tabs with fresh
                    // navigation, so no detail view of the other child lingers.
                    MainTabView()
                        .environment(repo)
                        .id(repo.account.login)
                        .transition(switchTransition)
                } else {
                    LaunchView()
                }
            }
        }
        .animation(Theme.Motion.emphasized, value: app.phase)
        .animation(Theme.Motion.standard, value: app.repository?.account.login)
        .task {
            if case .loading = app.phase { await app.bootstrap() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Returning to the foreground (incl. from the app switcher) — refresh.
            guard phase == .active, case .loggedIn = app.phase,
                  let repo = app.repository else { return }
            app.normalizeTimetableWeek()
            Task { await repo.foregroundRefresh() }
        }
    }

    /// A swipe between children slides the tabs the way the finger moved; a pick
    /// from the menu cross-fades.
    private var switchTransition: AnyTransition {
        switch app.lastSwitch {
        case .menu:
            return .opacity
        case .forward:
            return .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        case .backward:
            return .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
        }
    }
}

private struct LaunchView: View {
    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}
