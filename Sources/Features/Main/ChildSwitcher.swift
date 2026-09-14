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
