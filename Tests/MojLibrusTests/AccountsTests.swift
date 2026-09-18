import XCTest
@testable import MojLibrus

final class AccountsTests: XCTestCase {
    private func portal() -> PortalTokens {
        PortalTokens(accessToken: "p-access", refreshToken: "p-refresh", expiry: 4_102_444_800)
    }

    private func credentials() -> Credentials {
        Credentials(
            login: "rodzic@example.com", password: "secret", portal: portal(),
            accounts: [
                SynergiaAccountCredentials(login: "1111111", token: "t1", expiry: 0, studentName: "Anna Kowalska"),
                SynergiaAccountCredentials(login: "2222222", token: "t2", expiry: 0, studentName: "Jan Kowalski"),
            ],
            selectedLogin: "1111111"
        )
    }

    // MARK: - Credentials

    func testLegacyBlobMigratesToOneAccount() throws {
        // Arrange — the exact JSON shape written by builds before the child switcher.
        let json = """
        { "login": "rodzic@example.com", "password": "secret",
          "portal": { "accessToken": "p", "refreshToken": "r", "expiry": 1 },
          "synergiaLogin": "1234567", "synergiaToken": "s", "synergiaExpiry": 2,
          "studentName": "Anna Kowalska" }
        """

        // Act
        let legacy = try JSONDecoder().decode(LegacyCredentialsV2.self, from: Data(json.utf8))
        let migrated = legacy.migrated

        // Assert
        XCTAssertEqual(migrated.accounts.count, 1)
        XCTAssertEqual(migrated.selectedLogin, "1234567")
        XCTAssertEqual(migrated.selected?.token, "s")
        XCTAssertEqual(migrated.selected?.expiry, 2)
        XCTAssertEqual(migrated.selected?.studentName, "Anna Kowalska")
        XCTAssertEqual(migrated.portal.refreshToken, "r")
    }

    func testCredentialsRoundTripThroughJSON() throws {
        let original = credentials()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Credentials.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testSelectingKnownAccountChangesOnlySelection() {
        let creds = credentials()
        let switched = creds.selecting("2222222")
        XCTAssertEqual(switched?.selectedLogin, "2222222")
        XCTAssertEqual(switched?.selected?.studentName, "Jan Kowalski")
        XCTAssertEqual(switched?.accounts, creds.accounts)
    }

    func testSelectingUnknownAccountReturnsNil() {
        XCTAssertNil(credentials().selecting("9999999"))
    }

    func testSelectedFallsBackToFirstWhenStoredChoiceIsGone() {
        var creds = credentials()
        creds.selectedLogin = "gone"
        XCTAssertEqual(creds.selected?.login, "1111111")
    }

    func testUpdatingReplacesTokenOfOneChildOnly() {
        let creds = credentials()
        let fresh = SynergiaAccountCredentials(login: "2222222", token: "new", expiry: 99, studentName: "Jan Kowalski")
        let updated = creds.updating(fresh)
        XCTAssertEqual(updated.account(login: "2222222")?.token, "new")
        XCTAssertEqual(updated.account(login: "1111111")?.token, "t1")
        XCTAssertEqual(updated.accounts.count, 2)
    }

    func testTokenValidityHonoursExpiry() {
        let valid = SynergiaAccountCredentials(login: "1", token: "t", expiry: Date().timeIntervalSince1970 + 3600, studentName: nil)
        let stale = SynergiaAccountCredentials(login: "1", token: "t", expiry: Date().timeIntervalSince1970 + 60, studentName: nil)
        let never = SynergiaAccountCredentials(login: "1", token: "", expiry: 0, studentName: nil)
        XCTAssertTrue(valid.isTokenValid)
        XCTAssertFalse(stale.isTokenValid, "inside the 120 s safety margin counts as expired")
        XCTAssertFalse(never.isTokenValid)
    }

    // MARK: - Portal account list

    func testUsableAccountsKeepsActiveAndDropsBrokenLinks() throws {
        let json = """
        [ { "id": 1, "login": "1111111", "accessToken": "a", "studentName": "Anna", "state": "active" },
          { "id": 2, "login": "2222222", "accessToken": "", "studentName": "Jan" },
          { "id": 3, "login": "3333333", "accessToken": "c", "studentName": "Ola", "state": "requiring_an_action" },
          { "id": 4, "login": "", "accessToken": "d", "studentName": "Bez loginu" } ]
        """
        let listed = try JSONDecoder().decode([SynergiaAccount].self, from: Data(json.utf8))

        let usable = LibrusSession.usableAccounts(listed)

        XCTAssertEqual(usable.map(\.login), ["1111111", "2222222"])
    }

    // MARK: - Account summary

    func testShortNameIsFirstWordAndFallsBackToLogin() {
        XCTAssertEqual(AccountSummary(login: "1111111", studentName: "Anna Maria Kowalska").shortName, "Anna")
        XCTAssertEqual(AccountSummary(login: "1111111", studentName: "  ").displayName, "1111111")
        XCTAssertEqual(AccountSummary(login: "1111111", studentName: nil).shortName, "1111111")
    }

    // MARK: - Swiping between children

    func testAdjacentLoginMovesForwardBackwardAndWraps() {
        let kids = [AccountSummary(login: "1", studentName: "Anna"),
                    AccountSummary(login: "2", studentName: "Jan"),
                    AccountSummary(login: "3", studentName: "Ola")]
        XCTAssertEqual(AppState.adjacentLogin(in: kids, current: "1", forward: true), "2")
        XCTAssertEqual(AppState.adjacentLogin(in: kids, current: "3", forward: true), "1")
        XCTAssertEqual(AppState.adjacentLogin(in: kids, current: "1", forward: false), "3")
        XCTAssertEqual(AppState.adjacentLogin(in: kids, current: "2", forward: false), "1")
    }

    func testAdjacentLoginWithTwoChildrenTogglesEitherWay() {
        let kids = [AccountSummary(login: "1", studentName: "Anna"),
                    AccountSummary(login: "2", studentName: "Jan")]
        XCTAssertEqual(AppState.adjacentLogin(in: kids, current: "1", forward: true), "2")
        XCTAssertEqual(AppState.adjacentLogin(in: kids, current: "1", forward: false), "2")
    }

    func testAdjacentLoginIsNilForOneChildOrUnknownCurrent() {
        let one = [AccountSummary(login: "1", studentName: "Anna")]
        XCTAssertNil(AppState.adjacentLogin(in: one, current: "1", forward: true))
        let two = one + [AccountSummary(login: "2", studentName: "Jan")]
        XCTAssertNil(AppState.adjacentLogin(in: two, current: "9", forward: true))
        XCTAssertNil(AppState.adjacentLogin(in: two, current: nil, forward: true))
    }

    // MARK: - Per-child stores

    func testSeenStoresAreScopedPerAccount() {
        let anna = SeenStores(account: "1111111")
        let jan = SeenStores(account: "2222222")
        XCTAssertNotEqual(anna.grades.name, jan.grades.name)
        XCTAssertNotEqual(anna.messageIDs.name, jan.messageIDs.name)
        XCTAssertNotEqual(anna.timetableChanges.name, jan.timetableChanges.name)
    }

    func testCacheSafeNameStripsPathCharacters() {
        XCTAssertEqual(Cache.safeName("1234567u"), "1234567u")
        XCTAssertEqual(Cache.safeName("a/b c"), "a_b_c")
        XCTAssertEqual(Cache.safeName(""), "default")
    }

    // MARK: - Calendar keys

    func testCalendarEventKeyRoundTripsAndReadsLegacyURLs() {
        let url = CalendarSync.eventURL(account: "1111111", id: 42)
        let key = CalendarSync.eventKey(from: url)
        XCTAssertEqual(key?.account, "1111111")
        XCTAssertEqual(key?.id, 42)

        let legacy = CalendarSync.eventKey(from: URL(string: "librus-event://42"))
        XCTAssertNil(legacy?.account)
        XCTAssertEqual(legacy?.id, 42)

        XCTAssertNil(CalendarSync.eventKey(from: URL(string: "https://example.com/42")))
        XCTAssertNil(CalendarSync.eventKey(from: nil))
    }
}
