import Foundation

/// One Synergia account (= one child) reachable through the parent's Konto LIBRUS.
struct SynergiaAccountCredentials: Codable, Equatable {
    var login: String
    var token: String
    /// Absolute expiry of `token` (seconds since 1970). `0` = never fetched yet.
    var expiry: Double
    var studentName: String?

    var isTokenValid: Bool {
        !token.isEmpty && Date().timeIntervalSince1970 < expiry - 120
    }
}

/// Everything needed to talk to Librus on behalf of a Konto LIBRUS and every
/// Synergia account linked to it. Persisted as one JSON blob in the keychain.
///
/// A parent's Konto LIBRUS carries one Synergia account per child. The portal
/// tokens are shared; each child has its own bearer token for `api.librus.pl/2.0`.
struct Credentials: Codable, Equatable {
    /// Portal login (a Librus e-mail).
    var login: String
    var password: String

    var portal: PortalTokens

    /// Every usable Synergia account the portal listed, in portal order.
    var accounts: [SynergiaAccountCredentials]
    /// Login of the child currently shown in the app.
    var selectedLogin: String

    var isPortalTokenValid: Bool {
        !portal.accessToken.isEmpty && Date().timeIntervalSince1970 < portal.expiry - 60
    }

    /// The chosen child, falling back to the first one if the stored choice is gone.
    var selected: SynergiaAccountCredentials? {
        account(login: selectedLogin) ?? accounts.first
    }

    func account(login: String) -> SynergiaAccountCredentials? {
        accounts.first { $0.login == login }
    }

    /// A copy with `login` as the active child, or nil when it is not one of ours.
    func selecting(_ login: String) -> Credentials? {
        guard account(login: login) != nil else { return nil }
        var copy = self
        copy.selectedLogin = login
        return copy
    }

    /// A copy with the account matching `account.login` replaced.
    func updating(_ account: SynergiaAccountCredentials) -> Credentials {
        var copy = self
        if let index = copy.accounts.firstIndex(where: { $0.login == account.login }) {
            copy.accounts[index] = account
        } else {
            copy.accounts.append(account)
        }
        return copy
    }

    // MARK: - Persistence

    static let keychainKey = "credentials.v3"
    private static let legacyV2Key = "credentials.v2"
    private static let legacyV1Key = "credentials.v1"

    static func load() -> Credentials? {
        if let current = Keychain.json(Credentials.self, for: keychainKey) {
            return current
        }
        // A build from before the child switcher stored a single account — carry
        // it over so an upgrade doesn't log the user out.
        if let legacy = Keychain.json(LegacyCredentialsV2.self, for: legacyV2Key) {
            let migrated = legacy.migrated
            migrated.save()
            Keychain.delete(legacyV2Key)
            return migrated
        }
        return nil
    }

    func save() {
        Keychain.setJSON(self, for: Credentials.keychainKey)
    }

    static func clear() {
        Keychain.delete(keychainKey)
        Keychain.delete(legacyV2Key)
        Keychain.delete(legacyV1Key)
    }
}

/// Layout of the single-account keychain blob written by builds before the
/// child switcher. Only used to migrate on first launch after an upgrade.
struct LegacyCredentialsV2: Codable {
    var login: String
    var password: String
    var portal: PortalTokens
    var synergiaLogin: String
    var synergiaToken: String
    var synergiaExpiry: Double
    var studentName: String?

    var migrated: Credentials {
        Credentials(
            login: login, password: password, portal: portal,
            accounts: [SynergiaAccountCredentials(
                login: synergiaLogin, token: synergiaToken,
                expiry: synergiaExpiry, studentName: studentName)],
            selectedLogin: synergiaLogin
        )
    }
}
