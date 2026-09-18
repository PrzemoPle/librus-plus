import SwiftUI

/// Leading toolbar menu for picking which child's data a screen shows.
/// Renders nothing when the Konto LIBRUS has a single Synergia account.
struct ChildSwitcherToolbar: ViewModifier {
    @Environment(AppState.self) private var app
    @Environment(DataRepository.self) private var repo

    func body(content: Content) -> some View {
        content.toolbar {
            if app.accounts.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(app.accounts) { account in
                            Button {
                                Haptics.selection()
                                Task { await app.switchAccount(to: account.login) }
                            } label: {
                                if account.login == repo.account.login {
                                    Label(account.displayName, systemImage: "checkmark")
                                } else {
                                    Text(account.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: Theme.Space.xs) {
                            Image(systemName: "person.crop.circle.fill")
                            Text(repo.account.shortName)
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                    }
                    .disabled(app.isSwitchingAccount)
                    .accessibilityLabel("Dziecko: \(repo.account.displayName)")
                    .accessibilityHint("Otwiera listę dzieci do przełączenia")
                }
            }
        }
    }
}

extension View {
    /// Adds the child switcher to a tab's root screen.
    func childSwitcher() -> some View {
        modifier(ChildSwitcherToolbar())
    }
}

/// A mostly-horizontal swipe across a tab's content shows the next / previous
/// child. Not applied to screens whose rows have their own swipe actions
/// (Wiadomości, Ogłoszenia) — the two gestures would fight.
struct ChildSwipeModifier: ViewModifier {
    @Environment(AppState.self) private var app
    @Environment(\.isPresented) private var isPresented

    private static let minimumTravel: CGFloat = 90
    /// How much wider than tall the drag must be to count as horizontal.
    private static let horizontalBias: CGFloat = 2.5
    /// Left strip reserved for the system back swipe on pushed screens.
    private static let backSwipeZone: CGFloat = 32

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { handle($0) }
        )
    }

    private func handle(_ value: DragGesture.Value) {
        guard app.accounts.count > 1, !app.isSwitchingAccount else { return }
        let dx = value.translation.width
        let dy = value.translation.height
        guard abs(dx) >= Self.minimumTravel, abs(dx) > abs(dy) * Self.horizontalBias else { return }
        // On a pushed screen a rightward drag from the left edge is "go back".
        if isPresented, dx > 0, value.startLocation.x < Self.backSwipeZone { return }
        Haptics.selection()
        Task { await app.switchToAdjacentAccount(forward: dx < 0) }
    }
}

extension View {
    /// Swipe left / right to move between children.
    func childSwipe() -> some View {
        modifier(ChildSwipeModifier())
    }
}
