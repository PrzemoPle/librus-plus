import XCTest
@testable import MojLibrus

final class MessagesParsingTests: XCTestCase {
    func testParsesBasicRow() {
        let html = """
        <table class="decorated stretch"><tbody>
        <tr>
          <td><input type="checkbox"></td>
          <td></td>
          <td><a href="/wiadomosci/1/5/555/f0">Anna Nowak</a></td>
          <td><a href="/wiadomosci/1/5/555/f0">Wycieczka</a></td>
          <td>2026-09-07 12:00:00</td>
        </tr>
        </tbody></table>
        """
        let items = MessagesClient.parseMessageList(html)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, 555)
        XCTAssertEqual(items.first?.correspondent, "Anna Nowak")
        XCTAssertEqual(items.first?.subject, "Wycieczka")
        XCTAssertFalse(items.first?.isUnread ?? true) // no inline style → read
    }

    func testStripsRoleWordAppendedToSender() {
        let html = """
        <table class="decorated stretch"><tbody>
        <tr>
          <td><input type="checkbox"></td>
          <td></td>
          <td style="font-weight:bold"><a href="/wiadomosci/1/5/12345/f0">Jan Kowalski nadawca</a></td>
          <td><a href="/wiadomosci/1/5/12345/f0">Zebranie z rodzicami</a></td>
          <td>2026-09-08 09:15:00</td>
        </tr>
        </tbody></table>
        """
        let items = MessagesClient.parseMessageList(html)
        XCTAssertEqual(items.first?.correspondent, "Jan Kowalski")
        XCTAssertTrue(items.first?.isUnread ?? false) // inline style → unread
    }

    func testExtraLeadingCellStillYieldsDateSenderAndSubject() {
        // A fresh message row with one more cell at the front (a "new" flag) used
        // to shift every column: the date came out nil and the message sank to
        // the bottom of the inbox.
        let html = """
        <table class="decorated stretch"><tbody>
        <tr>
          <td><input type="checkbox"></td>
          <td><span class="new">NOWA</span></td>
          <td><img src="/images/attachment.png"></td>
          <td style="font-weight:bold"><a href="/wiadomosci/1/5/901/f0">Ewa Nowak</a></td>
          <td style="font-weight:bold"><a href="/wiadomosci/1/5/901/f0">Zebranie 24 września</a></td>
          <td>2026-09-15 07:45:12</td>
        </tr>
        </tbody></table>
        """
        let items = MessagesClient.parseMessageList(html)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.correspondent, "Ewa Nowak")
        XCTAssertEqual(items.first?.subject, "Zebranie 24 września")
        XCTAssertNotNil(items.first?.sentDate)
        XCTAssertTrue(items.first?.isUnread ?? false)
        XCTAssertTrue(items.first?.hasAttachments ?? false)
    }

    func testParsesDottedPolishDateAndIgnoresDateLikeSubject() {
        let html = """
        <table class="decorated stretch"><tbody>
        <tr>
          <td><input type="checkbox"></td>
          <td></td>
          <td><a href="/wiadomosci/1/5/902/f0">Sekretariat</a></td>
          <td><a href="/wiadomosci/1/5/902/f0">Składka do 30.09.2026</a></td>
          <td>15.09.2026 08:10</td>
        </tr>
        </tbody></table>
        """
        let items = MessagesClient.parseMessageList(html)
        let date = items.first?.sentDate
        XCTAssertNotNil(date)
        let comps = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "Europe/Warsaw")!, from: date!)
        XCTAssertEqual(comps.day, 15)
        XCTAssertEqual(comps.month, 9)
        XCTAssertEqual(items.first?.subject, "Składka do 30.09.2026")
    }

    func testScrapedCellDateFormats() {
        XCTAssertNotNil(LibrusDate.fromScrapedCell("2026-09-15 07:45:12"))
        XCTAssertNotNil(LibrusDate.fromScrapedCell("2026-09-15 07:45"))
        XCTAssertNotNil(LibrusDate.fromScrapedCell("  15.09.2026 07:45 (nowa)  "))
        XCTAssertNotNil(LibrusDate.fromScrapedCell("15.09.2026"))
        XCTAssertNil(LibrusDate.fromScrapedCell("Nadawca"))
        XCTAssertNil(LibrusDate.fromScrapedCell(nil))
    }

    func testRecoversWhenSenderCellIsAHeaderLabel() {
        // Shifted layout: cell[2] parsed out as the literal column header.
        let html = """
        <table class="decorated stretch"><tbody>
        <tr>
          <td><input type="checkbox"></td>
          <td>Anna Nowak</td>
          <td>Nadawca</td>
          <td><a href="/wiadomosci/1/5/777/f0">Wywiadówka</a></td>
          <td>2026-09-07 12:00:00</td>
        </tr>
        </tbody></table>
        """
        let items = MessagesClient.parseMessageList(html)
        XCTAssertEqual(items.first?.correspondent, "Anna Nowak")
        XCTAssertEqual(items.first?.subject, "Wywiadówka")
    }
}
