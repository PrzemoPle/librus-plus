import Foundation
import Observation

/// Top-level app state: whether we have a session, which child is shown, and one
/// repository per child (created lazily, kept alive so switching back is instant).
@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case loading
        case loggedOut
        case loggedIn
    }

    private(set) var phase: Phase = .loading
    let session = LibrusSession()

    /// Repository of the child currently shown.
    private(set) var repository: DataRepository?
    /// Every child linked to the Konto LIBRUS, in portal order.
    private(set) var accounts: [AccountSummary] = []
    /// Konto LIBRUS e-mail, for the settings screen.
    private(set) var portalLogin: String?

    /// Survives a child switch, which rebuilds the tab view.
    var selectedTab: MainTab = .dashboard

    var loginError: String?
    var isLoggingIn = false
    /// True while a child switch is in flight — the switcher disables itself.
    private(set) var isSwitchingAccount = false

    @ObservationIgnored private var repositories: [String: DataRepository] = [:]

    func bootstrap() async {
        if await session.isLoggedIn {
            await activateSelectedAccount()
            phase = .loggedIn
            await repository?.refreshCore()
        } else {
            phase = .loggedOut
        }
    }

    func logIn(login: String, password: String) async {
        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }
        do {
            try await session.logIn(
                login: login.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            await activateSelectedAccount()
            phase = .loggedIn
            await repository?.refreshCore()
        } catch {
            loginError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func logOut() async {
        // Every child's cache lives in the same directory — one wipe covers all.
        repository?.clearLocal()
        await session.logOut()
        repositories = [:]
        repository = nil
        accounts = []
        portalLogin = nil
        phase = .loggedOut
    }

    /// Shows another child's data. Tabs are rebuilt by `RootView` (keyed on the
    /// account), so navigation starts fresh; the selected tab is kept.
    func switchAccount(to login: String) async {
        guard login != repository?.account.login, !isSwitchingAccount else { return }
        isSwitchingAccount = true
        defer { isSwitchingAccount = false }
        do {
            try await session.select(accountLogin: login)
        } catch {
            repository?.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }
        await activateSelectedAccount()
        await repository?.refreshCoreIfStale()
    }

    /// Called when a data request finds the session is truly dead (refresh + re-auth failed).
    /// Keeps the cached data so the user isn't staring at a blank screen after re-login.
    func handleSessionExpired() async {
        guard phase == .loggedIn else { return }
        await session.logOut()
        repositories = [:]
        repository = nil
        accounts = []
        phase = .loggedOut
        loginError = "Sesja Librusa wygasła lub zmieniło się hasło — zaloguj się ponownie."
    }

    private func activateSelectedAccount() async {
        accounts = await session.accounts
        portalLogin = await session.portalLogin
        guard let selected = await session.selectedAccount else {
            repository = nil
            return
        }
        let repo = repositories[selected.login] ?? makeRepository(for: selected)
        repositories[selected.login] = repo
        for (login, other) in repositories { other.isActive = login == selected.login }
        repo.calendarLabel = accounts.count > 1 ? selected.shortName : nil
        repo.adoptsLegacyCalendarEntries = selected.login == accounts.first?.login
        repository = repo
    }

    private func makeRepository(for account: AccountSummary) -> DataRepository {
        let repo = DataRepository(session: session, account: account)
        repo.onSessionExpired = { [weak self] in
            Task { await self?.handleSessionExpired() }
        }
        return repo
    }
}
