import Foundation

/// A Synergia account (child) available in the current session — what the UI
/// lists in the child switcher.
struct AccountSummary: Identifiable, Hashable, Sendable {
    let login: String
    let studentName: String?

    var id: String { login }

    var displayName: String {
        let name = (studentName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? login : name
    }

    /// First name only, for compact toolbar labels.
    var shortName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }
}

/// Owns the Librus session: Portal OAuth tokens + one bearer token per Synergia
/// account (child), and performs authorized `api.librus.pl/2.0/*` requests.
///
/// An `actor` so token refresh is serialized. Requests default to the selected
/// child; pass `account:` to address a specific one (background checks do).
actor LibrusSession {
    private(set) var credentials: Credentials?
    private var portalRefreshTask: Task<PortalTokens, Error>?
    private var accountRefreshTasks: [String: Task<String, Error>] = [:]

    private let portalAuth = PortalAuth()
    private let urlSession: URLSession

    private static let synergiaTokenLifetime: TimeInterval = 6 * 3600

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["User-Agent": Librus.userAgent]
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        self.urlSession = URLSession(configuration: config)
        self.credentials = Credentials.load()
        // Re-persist once so an install upgraded from an older build immediately
        // picks up the current keychain accessibility (…ThisDeviceOnly) instead of
        // waiting for the next token refresh. Idempotent, sync, cheap.
        self.credentials?.save()
    }

    var isLoggedIn: Bool { credentials != nil }

    /// Konto LIBRUS e-mail the session was opened with.
    var portalLogin: String? { credentials?.login }

    var accounts: [AccountSummary] {
        credentials?.accounts.map { AccountSummary(login: $0.login, studentName: $0.studentName) } ?? []
    }

    var selectedAccount: AccountSummary? {
        credentials?.selected.map { AccountSummary(login: $0.login, studentName: $0.studentName) }
    }

    // MARK: - Login

    func logIn(login: String, password: String) async throws {
        let cleanLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)
        let portal = try await portalAuth.logIn(login: cleanLogin, password: password)
        let listed = try await portalAuth.synergiaAccounts(portalToken: portal.accessToken)

        let usable = Self.usableAccounts(listed)
        guard !usable.isEmpty else {
            if listed.contains(where: { $0.state == "requiring_an_action" }) {
                throw APIError.librus(code: "requiring_an_action",
                    message: "Konto Synergia wymaga ponownego połączenia na portal.librus.pl.")
            }
            throw APIError.librus(code: "no_accounts",
                message: "Portal nie zwrócił żadnego konta Synergia. Sprawdź, czy konto jest połączone na portal.librus.pl.")
        }

        let now = Date().timeIntervalSince1970
        var accounts = usable.map { account in
            SynergiaAccountCredentials(
                login: account.login, token: account.accessToken,
                expiry: account.accessToken.isEmpty ? 0 : now + Self.synergiaTokenLifetime,
                studentName: account.studentName
            )
        }

        // Re-logging into the same Konto LIBRUS keeps the child that was open.
        let previous = credentials?.selectedLogin
        let selectedLogin = accounts.first { $0.login == previous }?.login ?? accounts[0].login

        // Make sure the child we are about to show actually works — a failure here
        // surfaces on the login screen instead of as a broken dashboard.
        if let index = accounts.firstIndex(where: { $0.login == selectedLogin }),
           accounts[index].token.isEmpty {
            accounts[index].token = try await portalAuth.freshSynergiaToken(
                login: selectedLogin, portalToken: portal.accessToken)
            accounts[index].expiry = Date().timeIntervalSince1970 + Self.synergiaTokenLifetime
        }

        let creds = Credentials(
            login: cleanLogin, password: password, portal: portal,
            accounts: accounts, selectedLogin: selectedLogin
        )
        creds.save()
        credentials = creds
    }

    /// Accounts the portal reports as linked and usable. `state` is nil, empty or
    /// "active" on a healthy link; "requiring_an_action" needs a visit to the portal.
    nonisolated static func usableAccounts(_ accounts: [SynergiaAccount]) -> [SynergiaAccount] {
        accounts.filter { account in
            guard !account.login.isEmpty else { return false }
            return account.state == nil || account.state == "" || account.state == "active"
        }
    }

    /// Makes `accountLogin` the child shown in the app. Persists the choice.
    func select(accountLogin: String) throws {
        guard let next = credentials?.selecting(accountLogin) else {
            throw APIError.librus(code: "unknown_account", message: "Nie znam konta \(accountLogin).")
        }
        next.save()
        credentials = next
    }

    func logOut() {
        credentials = nil
        portalRefreshTask = nil
        accountRefreshTasks = [:]
        Credentials.clear()
    }

    // MARK: - Authorized requests

    /// `account` = Synergia login of the child to query; nil = the selected one.
    func authorizedData(
        path: String, method: String = "GET", body: Data? = nil, contentType: String? = nil,
        account: String? = nil
    ) async throws -> Data {
        let login = try resolveLogin(account)
        var token = try await validSynergiaToken(for: login)
        var (data, response) = try await send(
            path: path, token: token, method: method, body: body, contentType: contentType)

        if shouldRetryAfterAuth(data: data, response: response) {
            token = try await forceRefresh(for: login)
            (data, response) = try await send(
                path: path, token: token, method: method, body: body, contentType: contentType)
        }
        try Self.throwIfAPIError(data: data, response: response)
        return data
    }

    /// Current Synergia bearer token, refreshed on demand. Used by the messages bridge.
    func validAccessToken(account: String? = nil) async throws -> String {
        try await validSynergiaToken(for: resolveLogin(account))
    }

    private func resolveLogin(_ account: String?) throws -> String {
        if let account { return account }
        guard let login = credentials?.selected?.login else { throw APIError.tokenExpired }
        return login
    }

    // MARK: - Token lifecycle

    private func validSynergiaToken(for login: String) async throws -> String {
        guard let account = credentials?.account(login: login) else { throw APIError.tokenExpired }
        if account.isTokenValid { return account.token }
        return try await forceRefresh(for: login)
    }

    /// One refresh in flight per child; concurrent callers share it.
    private func forceRefresh(for login: String) async throws -> String {
        if let running = accountRefreshTasks[login] { return try await running.value }
        let task = Task<String, Error> { try await self.performRefresh(for: login) }
        accountRefreshTasks[login] = task
        defer { accountRefreshTasks[login] = nil }
        return try await task.value
    }

    private func performRefresh(for login: String) async throws -> String {
        try await ensureValidPortalToken()
        guard let creds = credentials, creds.account(login: login) != nil else {
            throw APIError.tokenExpired
        }

        let token: String
        do {
            token = try await portalAuth.freshSynergiaToken(
                login: login, portalToken: creds.portal.accessToken)
        } catch {
            // Portal token might have just died — one full re-login attempt.
            let portal = try await portalAuth.logIn(login: creds.login, password: creds.password)
            try updateCredentials { $0.portal = portal }
            token = try await portalAuth.freshSynergiaToken(login: login, portalToken: portal.accessToken)
        }

        let expiry = Date().timeIntervalSince1970 + Self.synergiaTokenLifetime
        try updateCredentials { current in
            guard var account = current.account(login: login) else { return }
            account.token = token
            account.expiry = expiry
            current = current.updating(account)
        }
        return token
    }

    /// Refreshes (or re-obtains) the portal token when it is stale. Shared by all
    /// children so two refreshes don't race over a single-use refresh token.
    private func ensureValidPortalToken() async throws {
        guard let creds = credentials else { throw APIError.tokenExpired }
        if creds.isPortalTokenValid { return }

        if let running = portalRefreshTask {
            _ = try await running.value
            return
        }
        let auth = portalAuth
        let task = Task<PortalTokens, Error> {
            do { return try await auth.refresh(refreshToken: creds.portal.refreshToken) }
            catch { return try await auth.logIn(login: creds.login, password: creds.password) }
        }
        portalRefreshTask = task
        defer { portalRefreshTask = nil }
        let portal = try await task.value
        try updateCredentials { $0.portal = portal }
    }

    /// Applies `change` to the *current* credentials and persists them. Always
    /// re-reads the stored value so a refresh for one child never clobbers a token
    /// another child's refresh wrote while this one was awaiting the network.
    private func updateCredentials(_ change: (inout Credentials) -> Void) throws {
        guard var current = credentials else { throw APIError.tokenExpired }
        change(&current)
        current.save()
        credentials = current
    }

    // MARK: - Request plumbing

    private func send(
        path: String, token: String, method: String = "GET",
        body: Data? = nil, contentType: String? = nil
    ) async throws -> (Data, URLResponse) {
        guard let url = URL(string: "\(Librus.apiBase.absoluteString)/\(path)") else {
            throw APIError.network("zły adres: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = body }
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        do {
            return try await urlSession.data(for: request)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    private func shouldRetryAfterAuth(data: Data, response: URLResponse) -> Bool {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { return true }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = obj["Code"] as? String, code == "TokenIsExpired" {
            return true
        }
        return false
    }

    private static func throwIfAPIError(data: Data, response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 503 { throw APIError.maintenance }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if status >= 400 {
                throw APIError.server(code: status, body: String(data: data, encoding: .utf8))
            }
            return
        }
        if let code = obj["Code"] as? String {
            throw APIError.fromAPICode(code, message: obj["Message"] as? String)
        }
        if status >= 400, (obj["Status"] as? String) == "Error" {
            throw APIError.server(code: status, body: obj["Message"] as? String)
        }
    }
}
