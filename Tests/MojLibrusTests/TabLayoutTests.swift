import XCTest
@testable import MojLibrus

@MainActor
final class TabLayoutTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TabLayoutTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultBarMatchesTheOriginalApp() {
        let layout = TabLayout(defaults: defaults)
        XCTAssertEqual(layout.bar, [.grades, .timetable, .attendance])
        XCTAssertEqual(layout.inMore, [.announcements, .events, .notes, .messages])
        XCTAssertTrue(layout.isDefault)
    }

    func testPlacingAScreenMovesTheOldOneToMore() {
        let layout = TabLayout(defaults: defaults)
        layout.set(slot: 2, to: .events)
        XCTAssertEqual(layout.bar, [.grades, .timetable, .events])
        XCTAssertTrue(layout.inMore.contains(.attendance))
        XCTAssertFalse(layout.inMore.contains(.events))
    }

    func testPlacingAScreenAlreadyInTheBarSwapsSlots() {
        let layout = TabLayout(defaults: defaults)
        layout.set(slot: 0, to: .attendance)
        XCTAssertEqual(layout.bar, [.attendance, .timetable, .grades])
        XCTAssertEqual(Set(layout.bar).count, 3, "no duplicates")
    }

    func testFixedTabsAndOutOfRangeSlotsAreIgnored() {
        let layout = TabLayout(defaults: defaults)
        layout.set(slot: 0, to: .dashboard)
        layout.set(slot: 7, to: .events)
        XCTAssertEqual(layout.bar, TabLayout.defaultBar)
    }

    func testLayoutSurvivesANewInstanceAndResetRestoresDefault() {
        TabLayout(defaults: defaults).set(slot: 1, to: .messages)
        let reloaded = TabLayout(defaults: defaults)
        XCTAssertEqual(reloaded.bar, [.grades, .messages, .attendance])
        reloaded.reset()
        XCTAssertEqual(TabLayout(defaults: defaults).bar, TabLayout.defaultBar)
    }

    func testCorruptStoredLayoutFallsBackToDefault() {
        defaults.set(["grades", "grades", "bogus"], forKey: "tabLayout.v1")
        XCTAssertEqual(TabLayout(defaults: defaults).bar, TabLayout.defaultBar)
        XCTAssertNil(TabLayout.validated([.grades, .grades, .events]))
        XCTAssertNil(TabLayout.validated([.grades, .events]))
        XCTAssertNil(TabLayout.validated([.grades, .events, .more]))
    }

    func testContainsCoversFixedTabs() {
        let layout = TabLayout(defaults: defaults)
        XCTAssertTrue(layout.contains(.dashboard))
        XCTAssertTrue(layout.contains(.more))
        XCTAssertTrue(layout.contains(.grades))
        XCTAssertFalse(layout.contains(.events))
    }
}
