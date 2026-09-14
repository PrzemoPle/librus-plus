import Foundation

/// Typed wrappers over `LibrusSession.authorizedData` — one method per endpoint,
/// each returning decoded raw models. No joining happens here.
///
/// Only `me()` throws (a missing student is fatal). Every other call returns an
/// optional: `nil` means "the request failed" (keep whatever we cached), while an
/// empty array means "Librus genuinely has nothing here".
struct LibrusAPI {
    let session: LibrusSession
    /// Synergia login of the child this instance queries; nil = the selected one.
    let account: String?

    init(session: LibrusSession, account: String? = nil) {
        self.session = session
        self.account = account
    }

    private static let decoder = JSONDecoder()

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let data = try await session.authorizedData(path: path, account: account)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding("\(path): \(error)")
        }
    }

    private func soft<T: Decodable>(_ path: String, as type: T.Type) async -> T? {
        do { return try await get(path, as: type) }
        catch { return nil }
    }

    func me() async throws -> RawMe {
        try await get(Librus.Path.me, as: RawMeResponse.self).me
    }

    func subjects() async -> [RawSubject]? {
        await soft(Librus.Path.subjects, as: RawSubjectsResponse.self)?.subjects
    }

    func users() async -> [RawUser]? {
        await soft(Librus.Path.users, as: RawUsersResponse.self)?.users
    }

    func classrooms() async -> [RawClassroom]? {
        await soft(Librus.Path.classrooms, as: RawClassroomsResponse.self)?.classrooms
    }

    func grades() async -> [RawGrade]? {
        await soft(Librus.Path.grades, as: RawGradesResponse.self)?.grades
    }

    func gradeCategories() async -> [RawGradeCategory]? {
        await soft(Librus.Path.gradeCategories, as: RawGradeCategoriesResponse.self)?.categories
    }

    func gradeComments() async -> [RawGradeComment]? {
        await soft(Librus.Path.gradeComments, as: RawGradeCommentsResponse.self)?.comments
    }

    func lessons() async -> [RawLessonDef]? {
        await soft(Librus.Path.lessons, as: RawLessonsResponse.self)?.lessons
    }

    func attendances() async -> [RawAttendance]? {
        await soft(Librus.Path.attendances, as: RawAttendancesResponse.self)?.attendances
    }

    func attendanceTypes() async -> [RawAttendanceType]? {
        await soft(Librus.Path.attendanceTypes, as: RawAttendanceTypesResponse.self)?.types
    }

    func announcements() async -> [RawAnnouncement]? {
        await soft(Librus.Path.schoolNotices, as: RawAnnouncementsResponse.self)?.announcements
    }

    func school() async -> RawSchool? {
        await soft(Librus.Path.schools, as: RawSchoolResponse.self)?.school
    }

    /// nil = keep the previous value (request failed or no class data).
    func classes() async -> RawStudentClass? {
        await soft(Librus.Path.classes, as: RawClassesResponse.self)?.studentClass
    }

    func notes() async -> [RawNote]? {
        await soft(Librus.Path.notes, as: RawNotesResponse.self)?.notes
    }

    func noteCategories() async -> [RawNoteCategory]? {
        await soft(Librus.Path.noteCategories, as: RawNoteCategoriesResponse.self)?.categories
    }

    func events() async -> [RawEvent]? {
        await soft(Librus.Path.events, as: RawEventsResponse.self)?.events
    }

    func eventCategories() async -> [RawEventCategory]? {
        await soft(Librus.Path.eventCategories, as: RawEventCategoriesResponse.self)?.categories
    }

    func timetable(weekStart: Date) async throws -> [String: [[RawLesson]]] {
        let path = Librus.Path.timetable(weekStart: LibrusDate.ymdString(weekStart))
        return try await get(path, as: RawTimetableResponse.self).days
    }

    /// Best-effort: tell Librus a school notice was read so the website reflects it
    /// too. Tries the dedicated marker, then falls back to fetching the detail
    /// (which marks it read on some Synergia instances). Never throws.
    func markAnnouncementReadOnServer(id: String) async {
        let marker = "\(Librus.Path.schoolNotices)/MarkAsRead/\(id)"
        if (try? await session.authorizedData(path: marker, method: "POST", account: account)) != nil { return }
        _ = try? await session.authorizedData(path: "\(Librus.Path.schoolNotices)/\(id)", account: account)
    }
}
