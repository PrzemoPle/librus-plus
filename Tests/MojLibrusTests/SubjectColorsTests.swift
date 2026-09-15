import XCTest
@testable import MojLibrus

@MainActor
final class SubjectColorsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SubjectColorsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testNothingIsColouredByDefault() {
        let store = SubjectColors(defaults: defaults)
        XCTAssertTrue(store.isEmpty)
        XCTAssertNil(store.color(for: "Matematyka"))
    }

    func testLookupIgnoresCaseAndWhitespace() {
        let store = SubjectColors(defaults: defaults)
        store.set(.teal, for: "Matematyka")
        XCTAssertEqual(store.palette(for: " matematyka "), .teal)
        XCTAssertEqual(store.palette(for: "MATEMATYKA"), .teal)
        XCTAssertNil(store.palette(for: "Fizyka"))
    }

    func testSettingNilRemovesTheColour() {
        let store = SubjectColors(defaults: defaults)
        store.set(.red, for: "Historia")
        store.set(nil, for: "Historia")
        XCTAssertNil(store.palette(for: "Historia"))
        XCTAssertTrue(store.isEmpty)
    }

    func testAssignmentsSurviveANewInstance() {
        SubjectColors(defaults: defaults).set(.indigo, for: "Język polski")
        let reloaded = SubjectColors(defaults: defaults)
        XCTAssertEqual(reloaded.palette(for: "język polski"), .indigo)
    }

    func testClearAllEmptiesStoreAndDefaults() {
        let store = SubjectColors(defaults: defaults)
        store.set(.green, for: "Przyroda")
        store.clearAll()
        XCTAssertTrue(store.isEmpty)
        XCTAssertTrue(SubjectColors(defaults: defaults).isEmpty)
    }

    func testEmptySubjectNameIsIgnored() {
        let store = SubjectColors(defaults: defaults)
        store.set(.pink, for: "   ")
        XCTAssertTrue(store.isEmpty)
    }
}
