import XCTest
@testable import MojLibrus

final class DecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testDecodeGrades() throws {
        let json = """
        { "Grades": [
          { "Id": 111, "Grade": "5", "AddDate": "2026-09-01 10:00:00", "Semester": 1,
            "Category": { "Id": 7 }, "AddedBy": { "Id": 20 }, "Subject": { "Id": 3 },
            "IsConstituent": true, "Comments": [ { "Id": 5 } ] },
          { "Id": 112, "Grade": "4+", "Semester": 1, "Subject": { "Id": 3 },
            "IsSemester": false, "IsSemesterProposition": true }
        ] }
        """
        let resp = try decoder.decode(RawGradesResponse.self, from: Data(json.utf8))
        XCTAssertEqual(resp.grades.count, 2)
        XCTAssertEqual(resp.grades[0].id, 111)
        XCTAssertEqual(resp.grades[0].category?.id, 7)
        XCTAssertEqual(resp.grades[0].commentIds, [5])
        XCTAssertTrue(resp.grades[1].isSemesterProposition)
    }

    func testDecodeTimetableNesting() throws {
        let json = """
        { "Timetable": { "2026-09-01": [
            [ { "LessonNo": 1, "HourFrom": "08:00", "HourTo": "08:45",
                "Subject": { "Id": 3, "Name": "Matematyka" },
                "Teacher": { "Id": 9, "FirstName": "Anna", "LastName": "Nowak" },
                "Classroom": { "Id": 2, "Name": "12" },
                "IsSubstitutionClass": false, "IsCanceled": false } ],
            [ ]
        ] } }
        """
        let resp = try decoder.decode(RawTimetableResponse.self, from: Data(json.utf8))
        let day = try XCTUnwrap(resp.days["2026-09-01"])
        XCTAssertEqual(day.count, 2)
        XCTAssertEqual(day[0].first?.subject?.name, "Matematyka")
        XCTAssertEqual(day[0].first?.teacher?.displayName, "Anna Nowak")
        XCTAssertTrue(day[1].isEmpty)
    }

    func testTimetableSkipsMalformedDay() throws {
        // One valid day, one day whose value is not an array of arrays.
        let json = """
        { "Timetable": {
            "2026-09-01": [ [ { "LessonNo": 1, "HourFrom": "08:00", "HourTo": "08:45",
                                "Subject": { "Id": 3, "Name": "Matematyka" } } ] ],
            "2026-09-02": "przerwa techniczna"
        } }
        """
        let resp = try decoder.decode(RawTimetableResponse.self, from: Data(json.utf8))
        XCTAssertEqual(resp.days.count, 1)
        XCTAssertNotNil(resp.days["2026-09-01"])
        XCTAssertNil(resp.days["2026-09-02"])
    }

    func testTimetableEmptyWhenArray() throws {
        let resp = try decoder.decode(RawTimetableResponse.self, from: Data(#"{ "Timetable": [] }"#.utf8))
        XCTAssertTrue(resp.days.isEmpty)
    }

    func testDecodeSchoolBellSchedule() throws {
        let json = """
        { "School": { "Name": "SP 1", "Town": "warszawa", "LessonsRange": [
            { "From": "0:00", "To": "0:00" },
            { "From": "8:00", "To": "8:45" },
            { "From": "8:55", "To": "9:40" }
        ] } }
        """
        let resp = try decoder.decode(RawSchoolResponse.self, from: Data(json.utf8))
        XCTAssertEqual(resp.school?.lessonsRange.count, 3)
        XCTAssertEqual(resp.school?.lessonsRange[1].from, "8:00")
        XCTAssertEqual(resp.school?.name, "SP 1")
    }

    func testTimetableRoomChange() throws {
        let json = """
        { "Timetable": { "2026-09-01": [ [ {
          "LessonNo": 2, "HourFrom": "08:55", "HourTo": "09:40",
          "Subject": { "Id": 3, "Name": "Fizyka" },
          "Classroom": { "Id": 9, "Name": "204" },
          "OrgClassroom": { "Id": 4, "Name": "12" },
          "IsSubstitutionClass": true, "IsCanceled": false
        } ] ] } }
        """
        let resp = try decoder.decode(RawTimetableResponse.self, from: Data(json.utf8))
        let lesson = try XCTUnwrap(resp.days["2026-09-01"]?.first?.first)
        XCTAssertEqual(lesson.classroom?.name, "204")
        XCTAssertEqual(lesson.orgClassroom?.name, "12")
    }

    /// A lesson moved to a different day is still a "substitution" slot as far
    /// as Librus is concerned, but `OrgDate` points back at the original day
    /// rather than matching the slot's own date — that's what distinguishes a
    /// move from a same-day teacher/subject swap.
    func testTimetableOrgDateForMovedLesson() throws {
        let json = """
        { "Timetable": { "2026-09-05": [ [ {
          "LessonNo": 4, "HourFrom": "11:50", "HourTo": "12:35",
          "Subject": { "Id": 3, "Name": "Fizyka" },
          "OrgDate": "2026-09-01",
          "IsSubstitutionClass": true, "IsCanceled": false
        } ] ] } }
        """
        let resp = try decoder.decode(RawTimetableResponse.self, from: Data(json.utf8))
        let lesson = try XCTUnwrap(resp.days["2026-09-05"]?.first?.first)
        XCTAssertTrue(lesson.isSubstitution)
        XCTAssertEqual(lesson.orgDate, "2026-09-01")
    }

    func testDecodeAnnouncementsStringId() throws {
        let json = """
        { "SchoolNotices": [
          { "Id": "abc-123", "Subject": "Zebranie", "Content": "Treść",
            "StartDate": "2026-09-01", "CreationDate": "2026-08-30 12:00:00",
            "AddedBy": { "Id": 4 }, "WasRead": false }
        ] }
        """
        let resp = try decoder.decode(RawAnnouncementsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(resp.announcements.first?.id, "abc-123")
        XCTAssertEqual(resp.announcements.first?.subject, "Zebranie")
        XCTAssertFalse(resp.announcements.first!.wasRead)
    }

    func testDecodeAttendancesStringId() throws {
        let json = """
        { "Attendances": [
          { "Id": "987", "Lesson": { "Id": 55 }, "LessonNo": 3, "Date": "2026-09-01",
            "Type": { "Id": 1 }, "Semester": 1, "AddDate": "2026-09-01 09:00:00" }
        ] }
        """
        let resp = try decoder.decode(RawAttendancesResponse.self, from: Data(json.utf8))
        XCTAssertEqual(resp.attendances.first?.id, 987)
        XCTAssertEqual(resp.attendances.first?.lesson?.id, 55)
    }

    func testAttendanceTypeKindMapping() throws {
        let json = """
        { "Types": [
          { "Id": 1, "Name": "Nieobecność", "Short": "nb", "Standard": true, "StandardType": { "Id": 1 } },
          { "Id": 100, "Name": "Obecność", "Short": "", "Standard": true }
        ] }
        """
        let resp = try decoder.decode(RawAttendanceTypesResponse.self, from: Data(json.utf8))
        XCTAssertEqual(resp.types[0].kind, .absent)
        XCTAssertEqual(resp.types[1].kind, .present)
    }

    func testDecodeMe() throws {
        let json = """
        { "Me": { "Account": { "FirstName": "Jan", "LastName": "Kowalski", "GroupId": "2" },
                  "User": { "FirstName": "Jan", "LastName": "Kowalski" } } }
        """
        let resp = try decoder.decode(RawMeResponse.self, from: Data(json.utf8))
        XCTAssertEqual(resp.me.displayName, "Jan Kowalski")
    }

    func testXMLTreeParsing() throws {
        let xml = """
        <response><GetList><data>
          <ArrayItem><messageId>42</messageId><topic>Test</topic>
          <sendDate>2026-09-01 08:00:00</sendDate>
          <senderFirstName>Anna</senderFirstName><senderLastName>Nowak</senderLastName>
          <isAnyFileAttached>1</isAnyFileAttached></ArrayItem>
        </data></GetList></response>
        """
        let root = try XCTUnwrap(XMLTreeNode.parse(xml))
        let data = try XCTUnwrap(root.firstNode(path: ["GetList", "data"]))
        XCTAssertEqual(data.children.count, 1)
        XCTAssertEqual(data.children[0].childText("messageId"), "42")
        XCTAssertEqual(data.children[0].childText("topic"), "Test")
        XCTAssertEqual(data.children[0].childText("isAnyFileAttached"), "1")
    }
}
