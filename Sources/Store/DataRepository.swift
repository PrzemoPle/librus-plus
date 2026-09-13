import Foundation
import Observation

/// The single source of truth for all screens. Fetches every endpoint, joins by
/// id, caches results, exposes display-ready models.
@MainActor
@Observable
final class DataRepository {
    let session: LibrusSession
    private let api: LibrusAPI
    private let messages: MessagesClient

    // Published state -------------------------------------------------------
    var studentName: String = ""
    var schoolYear = SchoolYearInfo()

    var subjectGrades: [SubjectGrades] = []
    var attendanceSummary = AttendanceSummary()
    var attendanceItems: [AttendanceItem] = []
    var announcements: [AnnouncementItem] = []
    var events: [CalendarEvent] = []
    var notes: [NoteItem] = []
    var messagesInbox: [MessageItem] = []
    var messagesSent: [MessageItem] = []
    var bellSchedule: [BellPeriod] = []
    var schoolName: String?

    var currentSemester: Int { schoolYear.semester() }

    /// week-start (yyyy-MM-dd) -> day list
    var timetableWeeks: [String: [TimetableDay]] = [:]

    var lastSync: Date?
    var isRefreshing = false
    var lastError: String?
    var messagesError: String?
    var timetableError: String?

    /// Set by `AppState`; invoked when a request proves the session is dead.
    @ObservationIgnored var onSessionExpired: (@MainActor () -> Void)?

    // Last-known lookup tables, kept so a single blipping endpoint doesn't break joins.
    @ObservationIgnored private var rawSubjects: [RawSubject] = []
    @ObservationIgnored private var rawUsers: [RawUser] = []
    @ObservationIgnored private var rawCategories: [RawGradeCategory] = []
    @ObservationIgnored private var rawComments: [RawGradeComment] = []
    @ObservationIgnored private var rawLessons: [RawLessonDef] = []
    @ObservationIgnored private var rawAttTypes: [RawAttendanceType] = []
    @ObservationIgnored private var rawNoteCats: [RawNoteCategory] = []
    @ObservationIgnored private var rawEventCats: [RawEventCategory] = []
    /// Classroom id -> room name/number. The timetable often gives only `Classroom.Id`.
    @ObservationIgnored private var classroomNameByID: [Int: String] = [:]

    /// Last successful inbox scrape — gates `loadMessagesIfStale`.
    @ObservationIgnored private var messagesLastSync: Date?

    /// Locally-tracked "read" state (Librus has no student-side write for these).
    private var readAnnouncementIDs: Set<String> = []
    private var readMessageIDs: Set<Int> = []

    /// Bumped after every grade sync so the `SeenGrades`-backed views recompute.
    private var gradeSeenTick = 0

    /// Grades that appeared since the user last opened the Oceny tab. Empty on first sync.
    var unseenGradeCount: Int {
        _ = gradeSeenTick
        return SeenGrades.newIDs(in: allGradeIDs).count
    }

    func isGradeUnseen(_ grade: GradeItem) -> Bool {
        _ = gradeSeenTick
        return SeenGrades.newIDs(in: allGradeIDs).contains(grade.id)
    }

    func markGradesSeen() {
        SeenGrades.merge(allGradeIDs)
        gradeSeenTick &+= 1
    }

    private var allGradeIDs: Set<Int> {
        Set(subjectGrades.flatMap { $0.grades.map(\.id) })
    }

    init(session: LibrusSession) {
        self.session = session
        self.api = LibrusAPI(session: session)
        self.messages = MessagesClient(session: session)
        loadCache()
    }

    // MARK: - Cache

    private struct Snapshot: Codable {
        var studentName: String
        var schoolYear: SchoolYearInfo
        var subjectGrades: [SubjectGrades]
        var attendanceSummary: AttendanceSummary
        var attendanceItems: [AttendanceItem]
        var announcements: [AnnouncementItem]
        var events: [CalendarEvent]?
        var notes: [NoteItem]
        var messagesInbox: [MessageItem]
        var messagesSent: [MessageItem]?
        var bellSchedule: [BellPeriod]?
        var schoolName: String?
        var lastSync: Date?
        var readAnnouncementIDs: [String]
        var readMessageIDs: [Int]?
        var classroomNames: [Int: String]?
    }

    private func loadCache() {
        guard let s = Cache.load(Snapshot.self, from: "snapshot") else { return }
        studentName = s.studentName
        schoolYear = s.schoolYear
        subjectGrades = s.subjectGrades
        attendanceSummary = s.attendanceSummary
        attendanceItems = s.attendanceItems
        announcements = s.announcements
        events = s.events ?? []
        notes = s.notes
        messagesInbox = s.messagesInbox
        messagesSent = s.messagesSent ?? []
        bellSchedule = s.bellSchedule ?? []
        schoolName = s.schoolName
        lastSync = s.lastSync
        readAnnouncementIDs = Set(s.readAnnouncementIDs)
        readMessageIDs = Set(s.readMessageIDs ?? [])
        classroomNameByID = s.classroomNames ?? [:]
        if let cachedWeeks = Cache.load([String: [TimetableDay]].self, from: "timetable") {
            timetableWeeks = cachedWeeks
        }
    }

    private func saveCache() {
        let snap = Snapshot(
            studentName: studentName, schoolYear: schoolYear,
            subjectGrades: subjectGrades, attendanceSummary: attendanceSummary,
            attendanceItems: attendanceItems, announcements: announcements,
            events: events, notes: notes, messagesInbox: messagesInbox,
            messagesSent: messagesSent,
            bellSchedule: bellSchedule, schoolName: schoolName,
            lastSync: lastSync, readAnnouncementIDs: Array(readAnnouncementIDs),
            readMessageIDs: Array(readMessageIDs),
            classroomNames: classroomNameByID
        )
        Cache.save(snap, as: "snapshot")
        Cache.save(timetableWeeks, as: "timetable")
    }

    func clearLocal() {
        Cache.clearAll()
        studentName = ""; schoolYear = .init(); subjectGrades = []
        attendanceSummary = .init(); attendanceItems = []
        announcements = []; events = []; notes = []; messagesInbox = []; messagesSent = []
        bellSchedule = []; schoolName = nil
        SeenGrades.reset()
        Seen.timetableChanges.reset()
        Seen.messageIDs.reset()
        SharedStore.clear()
        WidgetRefresher.reload()
        timetableWeeks = [:]; lastSync = nil
    }

    // MARK: - Notification "seen" tracking

    /// Signatures for every cancelled / substituted / room-changed lesson from
    /// today onward — the unit the timetable-change notification dedupes on.
    func upcomingChangeSignatures() -> Set<String> {
        let today = LibrusDate.today
        var out: Set<String> = []
        for day in timetableWeeks.values.flatMap({ $0 }) where day.date >= today {
            let dateKey = LibrusDate.ymdString(day.date)
            for e in day.entries where e.isCancelled || e.isSubstitution {
                let kind = e.isCancelled ? "C" : "S"
                out.insert("\(dateKey)#\(e.lessonNo)#\(kind)#\(e.subject)")
            }
        }
        return out
    }

    func markTimetableChangesSeen() {
        Seen.timetableChanges.merge(upcomingChangeSignatures())
    }

    func markMessagesSeen() {
        Seen.messageIDs.merge(Set(messagesInbox.map(\.id)))
    }

    // MARK: - Core refresh

    func refreshCore() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await withOneRetry { try await self.performCoreFetch() }
            lastError = nil
            // Sideload can't rely on the background task firing — also surface new
            // grades / timetable changes / messages as notifications on open.
            await BackgroundRefresh.runForegroundChecksIfDue(session: session)
            await syncCalendarIfEnabled()
        } catch {
            handle(error, into: \.lastError)
        }
    }

    /// Mirror the freshly-fetched Terminarz into the system Calendar. Idempotent —
    /// an unchanged entry is not re-saved, so running it after every refresh is cheap.
    @discardableResult
    func syncCalendarIfEnabled() async -> CalendarSync.SyncResult? {
        guard CalendarSync.isEnabled else { return nil }
        return await CalendarSync.sync(events: events, bellSchedule: bellSchedule)
    }

    /// Refresh only when the last successful sync is older than `maxAge`. Used when
    /// entering a screen / returning to the foreground so tapping around doesn't
    /// re-hit every endpoint.
    func refreshCoreIfStale(maxAge: TimeInterval = 90) async {
        if let last = lastSync, Date().timeIntervalSince(last) < maxAge { return }
        await refreshCore()
    }

    /// App came back to the foreground — one stale-gated pass over everything.
    func foregroundRefresh() async {
        guard !isRefreshing else { return } // a sync (e.g. from launch) is already running
        let stale = lastSync.map { Date().timeIntervalSince($0) >= 90 } ?? true
        guard stale else { return }
        await refreshCore()
        await loadTimetable(weekStart: LibrusDate.weekStart())
        await loadMessagesIfStale()
    }

    /// One automatic retry after a short pause for transient failures. Auth-dead
    /// errors are not retried — they need a re-login, not another attempt.
    private func withOneRetry(_ op: () async throws -> Void) async throws {
        do { try await op() }
        catch {
            guard Self.isRetryable(error) else { throw error }
            try? await Task.sleep(for: .seconds(2))
            try await op()
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return true }
        switch api {
        case .tokenExpired, .invalidCredentials, .captchaNeeded: return false
        default: return true
        }
    }

    private func performCoreFetch() async throws {
        do {
            // Dictionaries + primary data, fetched concurrently.
            let api = self.api
            async let meT = api.me()
            async let subjectsT = api.subjects()
            async let usersT = api.users()
            async let categoriesT = api.gradeCategories()
            async let commentsT = api.gradeComments()
            async let gradesT = api.grades()
            async let lessonsT = api.lessons()
            async let attTypesT = api.attendanceTypes()
            async let attsT = api.attendances()
            async let announcementsT = api.announcements()
            async let classesT = api.classes()
            async let notesT = api.notes()
            async let noteCategoriesT = api.noteCategories()
            async let eventsT = api.events()
            async let eventCategoriesT = api.eventCategories()
            async let schoolT = api.school()
            async let classroomsT = api.classrooms()

            let me = try await meT

            // Refresh lookup tables in place; keep the old ones on failure.
            if let v = await subjectsT { rawSubjects = v }
            if let v = await usersT { rawUsers = v }
            if let v = await categoriesT { rawCategories = v }
            if let v = await commentsT { rawComments = v }
            if let v = await lessonsT { rawLessons = v }
            if let v = await attTypesT { rawAttTypes = v }
            if let v = await noteCategoriesT { rawNoteCats = v }
            if let v = await eventCategoriesT { rawEventCats = v }
            let hadClassrooms = !classroomNameByID.isEmpty
            if let v = await classroomsT, !v.isEmpty {
                classroomNameByID = Dictionary(v.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
            }
            let gainedClassrooms = !hadClassrooms && !classroomNameByID.isEmpty

            let subjectByID = Dictionary(rawSubjects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let userByID = Dictionary(rawUsers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let categoryByID = Dictionary(rawCategories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let commentByID = Dictionary(rawComments.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let lessonByID = Dictionary(rawLessons.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let attTypeByID = Dictionary(rawAttTypes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let noteCatByID = Dictionary(rawNoteCats.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let eventCatByID = Dictionary(rawEventCats.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

            studentName = me.displayName

            if let sc = await classesT {
                schoolYear = SchoolYearInfo(
                    className: sc.name.isEmpty ? nil : sc.name,
                    tutor: sc.classTutor.flatMap { userByID[$0.id]?.displayName },
                    yearStart: LibrusDate.fromYMD(sc.beginSchoolYear),
                    secondSemesterStart: LibrusDate.fromYMD(sc.endFirstSemester),
                    yearEnd: LibrusDate.fromYMD(sc.endSchoolYear)
                )
            }

            if let rawNotes = await notesT {
                notes = rawNotes.map { n in
                    NoteItem(
                        id: n.id, text: n.text,
                        category: n.category.flatMap { noteCatByID[$0.id]?.name },
                        teacher: n.teacher.flatMap { userByID[$0.id]?.displayName },
                        date: LibrusDate.fromYMD(n.date),
                        kind: n.positive == 1 ? .positive : (n.positive == 0 ? .negative : .neutral)
                    )
                }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            }

            if let grades = await gradesT {
                subjectGrades = Self.joinGrades(
                    grades, subjectByID: subjectByID, userByID: userByID,
                    categoryByID: categoryByID, commentByID: commentByID
                )
                if !SeenGrades.hasBaseline {
                    SeenGrades.establishBaseline(allGradeIDs)
                }
                gradeSeenTick &+= 1
            }

            if let school = await schoolT {
                schoolName = [school.name, school.town?.capitalized].compactMap { $0 }
                    .filter { !$0.isEmpty }.joined(separator: ", ")
                bellSchedule = school.lessonsRange.enumerated().compactMap { index, r in
                    guard let from = r.from, let to = r.to else { return nil }
                    return BellPeriod(number: index, start: from, end: to)
                }
            }

            if let atts = await attsT {
                (attendanceSummary, attendanceItems) = Self.joinAttendance(
                    atts, typeByID: attTypeByID, lessonDefByID: lessonByID, subjectByID: subjectByID
                )
            }

            if let anns = await announcementsT {
                announcements = anns.map { a in
                    AnnouncementItem(
                        id: a.id, subject: a.subject, content: a.content,
                        author: a.addedBy.flatMap { userByID[$0.id]?.displayName },
                        date: LibrusDate.fromISO(a.creationDate) ?? LibrusDate.fromYMD(a.startDate),
                        wasReadOnServer: a.wasRead
                    )
                }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            }

            if let rawEvents = await eventsT {
                events = rawEvents.map { e in
                    CalendarEvent(
                        id: e.id, date: LibrusDate.fromYMD(e.date), content: e.content,
                        category: e.category.flatMap { eventCatByID[$0.id]?.name },
                        subject: e.subject.flatMap { subjectByID[$0.id]?.name },
                        teacher: e.createdBy.flatMap { userByID[$0.id]?.displayName },
                        lessonNo: e.lessonNo,
                        time: e.timeFrom
                    )
                }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
            }

            lastSync = Date()
            saveCache()

            // First sync that learned the classroom names: re-pull the visible week
            // so room numbers show up without waiting for the next manual refresh.
            if gainedClassrooms {
                await loadTimetable(weekStart: LibrusDate.weekStart())
            }
        } catch {
            // Nothing was persisted — surface it to the retry/handling in refreshCore().
            throw error
        }
    }

    /// Records the message and, for a dead session, notifies `AppState`.
    private func handle(_ error: Error, into keyPath: ReferenceWritableKeyPath<DataRepository, String?>) {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        self[keyPath: keyPath] = text
        // A silent re-login that comes back with `.invalidCredentials` means the
        // stored password no longer works (user changed it) — the session is just
        // as dead as an expired token, and retrying it on every refresh risks a
        // Librus account lockout. Both cases: hand off to a clean re-login.
        if let apiError = error as? APIError {
            switch apiError {
            case .tokenExpired, .invalidCredentials: onSessionExpired?()
            default: break
            }
        }
    }

    // MARK: - Timetable

    func loadTimetable(weekStart: Date) async {
        let key = LibrusDate.ymdString(weekStart)
        do {
            try await withOneRetry { try await self.fetchTimetable(weekStart: weekStart, key: key) }
            timetableError = nil
        } catch {
            // Keep timetable failures out of the app-wide error banner.
            handle(error, into: \.timetableError)
        }
    }

    private func fetchTimetable(weekStart: Date, key: String) async throws {
        let raw = try await api.timetable(weekStart: weekStart)
        let days: [TimetableDay] = raw.keys.sorted().compactMap { dateStr in
            guard let date = LibrusDate.fromYMD(dateStr) else { return nil }
            let slots = raw[dateStr] ?? []
            let entries: [TimetableEntry] = slots.flatMap { $0 }
                .compactMap { self.mapLesson($0, date: date) }
                .sorted { $0.lessonNo < $1.lessonNo }
            return TimetableDay(date: date, entries: entries)
        }
        timetableWeeks[key] = days
        if !Seen.timetableChanges.hasBaseline {
            Seen.timetableChanges.establishBaseline(upcomingChangeSignatures())
        }
        saveCache()
        SharedStore.publishTimetable(upcomingDays())
        WidgetRefresher.reload()
    }

    // MARK: - Messages

    func loadMessages() async {
        messagesError = nil
        var ok = false
        do {
            try await withOneRetry { try await self.fetchInbox() }
            ok = true
        } catch {
            handle(error, into: \.messagesError)
        }
        // Sent messages are a bonus — never let them break the inbox.
        if let sent = try? await messages.messages(in: .sent) {
            messagesSent = sent.sorted { ($0.sentDate ?? .distantPast) > ($1.sentDate ?? .distantPast) }
            saveCache()
        }
        if ok { messagesLastSync = Date() }
    }

    /// Reload the inbox only if the last successful scrape is older than `maxAge`.
    func loadMessagesIfStale(maxAge: TimeInterval = 120) async {
        if let last = messagesLastSync, Date().timeIntervalSince(last) < maxAge { return }
        await loadMessages()
    }

    private func fetchInbox() async throws {
        let list = try await messages.messages(in: .received)
        messagesInbox = list.sorted { ($0.sentDate ?? .distantPast) > ($1.sentDate ?? .distantPast) }
        if !Seen.messageIDs.hasBaseline {
            Seen.messageIDs.establishBaseline(Set(list.map(\.id)))
        }
        saveCache()
    }

    func loadMessageContent(_ id: Int, folder: MessagesClient.Folder = .received)
        async -> MessagesClient.MessageContent? {
        do {
            let content = try await messages.content(messageId: id, folder: folder)
            if folder == .received, !readMessageIDs.contains(id) {
                readMessageIDs.insert(id)
                saveCache()
            }
            return content
        } catch {
            handle(error, into: \.messagesError)
            return nil
        }
    }

    /// Sends a reply. Returns nil on success, or an error message to show the user.
    func sendReply(to recipientLoginId: String, subject: String, body: String) async -> String? {
        await sendMessage(to: [recipientLoginId], subject: subject, body: body, category: nil)
    }

    /// Sends a new message. Returns nil on success, or an error message to show.
    func sendMessage(to recipientIDs: [String], subject: String, body: String,
                     category: MessagesClient.RecipientCategory?) async -> String? {
        do {
            let cat = category.map { (field: "adresat", id: $0.id) }
            try await messages.send(recipientLoginIds: recipientIDs, subject: subject, body: body,
                                    recipientField: "DoKogo[]", category: cat)
            await loadMessages()
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Step 1 of composing: recipient categories (Nauczyciele, Wychowawcy…).
    func loadRecipientCategories() async
        -> (categories: [MessagesClient.RecipientCategory], error: String?) {
        do {
            return (try await messages.recipientCategories(), nil)
        } catch {
            return ([], (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Step 2: the people inside a category.
    func loadRecipients(in category: MessagesClient.RecipientCategory)
        async -> (list: MessagesClient.RecipientList?, error: String?) {
        do {
            return (try await messages.recipients(in: category), nil)
        } catch {
            return (nil, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    // MARK: - Read tracking (announcements)

    func isAnnouncementRead(_ item: AnnouncementItem) -> Bool {
        item.wasReadOnServer || readAnnouncementIDs.contains(item.id)
    }

    func markAnnouncementRead(_ item: AnnouncementItem) {
        setAnnouncementRead(item, read: true)
    }

    func setAnnouncementRead(_ item: AnnouncementItem, read: Bool) {
        if read { readAnnouncementIDs.insert(item.id) } else { readAnnouncementIDs.remove(item.id) }
        saveCache()
        // Mirror the "read" flag to Librus so the website agrees. Best-effort:
        // a failure just leaves it read locally (the previous behaviour).
        if read, !item.wasReadOnServer {
            Task { await api.markAnnouncementReadOnServer(id: item.id) }
        }
    }

    var unreadAnnouncementCount: Int {
        announcements.filter { !isAnnouncementRead($0) }.count
    }

    var unreadMessageCount: Int { unreadMessageCountLocal }

    var upcomingEventCount: Int {
        events.filter { !$0.isPast }.count
    }

    /// Nearest not-yet-past event, for the dashboard.
    var nextEvent: CalendarEvent? {
        events.filter { !$0.isPast }.min { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    // MARK: - Joining helpers

    private static func joinGrades(
        _ grades: [RawGrade],
        subjectByID: [Int: RawSubject],
        userByID: [Int: RawUser],
        categoryByID: [Int: RawGradeCategory],
        commentByID: [Int: RawGradeComment]
    ) -> [SubjectGrades] {
        var bySubject: [Int: SubjectGrades] = [:]
        for g in grades {
            let subjId = g.subject?.id ?? -1
            let subjName = subjectByID[subjId]?.name ?? "Inne"
            let category = g.category.flatMap { categoryByID[$0.id] }
            let kind: GradeKind
            if g.isSemesterProposition { kind = .semesterProposed }
            else if g.isSemester { kind = .semesterFinal }
            else if g.isFinalProposition { kind = .yearProposed }
            else if g.isFinal { kind = .yearFinal }
            else { kind = .normal }

            let value = GradeMath.numericValue(of: g.grade)
            let weight: Double = {
                let s = g.grade.trimmingCharacters(in: .whitespaces).lowercased()
                if ["+", "-", "np", "bz"].contains(s) { return 0 }
                return category?.effectiveWeight ?? 0
            }()

            let comment = g.commentIds.compactMap { commentByID[$0]?.text }
                .filter { !$0.isEmpty }.joined(separator: " • ")

            let item = GradeItem(
                id: g.id, raw: g.grade, value: value, weight: weight,
                semester: g.semester, kind: kind,
                categoryName: category?.name ?? "",
                teacherName: g.addedBy.flatMap { userByID[$0.id]?.displayName } ?? "",
                subjectId: subjId, subjectName: subjName,
                date: LibrusDate.fromISO(g.addDate),
                comment: comment.isEmpty ? nil : comment
            )
            bySubject[subjId, default: SubjectGrades(subjectId: subjId, subjectName: subjName, grades: [])]
                .grades.append(item)
        }
        return bySubject.values
            .map { var s = $0; s.grades.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }; return s }
            .sorted { $0.subjectName.localizedCaseInsensitiveCompare($1.subjectName) == .orderedAscending }
    }

    private static func joinAttendance(
        _ atts: [RawAttendance],
        typeByID: [Int: RawAttendanceType],
        lessonDefByID: [Int: RawLessonDef],
        subjectByID: [Int: RawSubject]
    ) -> (AttendanceSummary, [AttendanceItem]) {
        var summary = AttendanceSummary()
        var items: [AttendanceItem] = []
        for a in atts {
            let type = a.type.flatMap { typeByID[$0.id] }
            let kind = type?.kind ?? .presentCustom
            summary.counts[kind, default: 0] += 1

            let subjName: String? = {
                guard let lessonId = a.lesson?.id, let def = lessonDefByID[lessonId],
                      let sid = def.subject?.id else { return nil }
                return subjectByID[sid]?.name
            }()

            items.append(AttendanceItem(
                id: a.id, kind: kind,
                typeName: type?.name ?? "Nieznany",
                typeShort: type?.short ?? "?",
                colorHex: type?.colorRGB,
                date: LibrusDate.fromYMD(a.date),
                lessonNo: a.lessonNo,
                subjectName: subjName,
                semester: a.semester
            ))
        }
        items.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return (summary, items)
    }

    private func mapLesson(_ l: RawLesson, date: Date) -> TimetableEntry? {
        guard let no = l.lessonNo, let from = l.hourFrom, let to = l.hourTo else { return nil }
        // Librus usually inlines `Classroom.Name`, but some schools return only
        // `Classroom.Id` — fall back to the `Classrooms` lookup table then.
        let room = roomName(l.classroom)
        let orgRoom = roomName(l.orgClassroom)
        // A substitution whose `OrgDate` is a different day is really a lesson
        // moved from that day, not a same-day teacher/subject swap.
        let orgDate = LibrusDate.fromYMD(l.orgDate)
        let moved = l.isSubstitution && orgDate != nil && !LibrusDate.isSameDay(orgDate!, date)

        var note: String?
        if l.isCancelled {
            note = "Lekcja odwołana"
        } else if l.isSubstitution {
            var parts = [moved ? "Przeniesiona" : "Zastępstwo"]
            if moved, let orgDate {
                parts.append("(było: \(orgDate.weekdayName.capitalized) \(orgDate.dayMonthShort))")
            }
            if let orgName = l.orgSubject?.name, !orgName.isEmpty, orgName != l.subject?.name {
                parts.append(moved ? "— \(orgName)" : "(było: \(orgName))")
            }
            if let orgTeacher = l.orgTeacher?.displayName { parts.append(orgTeacher) }
            note = parts.joined(separator: " ")
        }
        return TimetableEntry(
            id: "\(no)-\(from)", lessonNo: no, start: from, end: to,
            subject: l.subject?.name ?? "—",
            teacher: l.teacher?.displayName,
            classroom: room,
            originalClassroom: orgRoom,
            originalDate: moved ? orgDate : nil,
            isCancelled: l.isCancelled,
            isSubstitution: l.isSubstitution,
            note: note
        )
    }

    /// Room label for a timetable classroom ref: inline name first, then the
    /// `Classrooms` lookup by id.
    private func roomName(_ ref: NamedRef?) -> String? {
        guard let ref else { return nil }
        if let name = ref.name, !name.isEmpty { return name }
        if let mapped = classroomNameByID[ref.id], !mapped.isEmpty { return mapped }
        return nil
    }

    // MARK: - Widget feed

    private func upcomingDays() -> [SharedStore.WidgetTimetable.Day] {
        let today = LibrusDate.today
        let allDays = timetableWeeks.values.flatMap { $0 }
            .filter { $0.date >= today && $0.date < LibrusDate.addDays(7, to: today) }
            .sorted { $0.date < $1.date }
        return allDays.prefix(5).map { day in
            SharedStore.WidgetTimetable.Day(
                date: day.date,
                lessons: day.entries.map { e in
                    SharedStore.WidgetTimetable.Lesson(
                        id: e.id, lessonNo: e.lessonNo, start: e.start, end: e.end,
                        subject: e.subject, room: e.classroom,
                        isCancelled: e.isCancelled, isSubstitution: e.isSubstitution,
                        roomChanged: e.roomChanged, note: e.note
                    )
                }
            )
        }
    }

    // MARK: - Message read tracking

    func isMessageRead(_ m: MessageItem) -> Bool {
        m.readDateServer != nil || readMessageIDs.contains(m.id)
    }

    func setMessageRead(_ m: MessageItem, read: Bool) {
        if read { readMessageIDs.insert(m.id) } else { readMessageIDs.remove(m.id) }
        saveCache()
    }

    var unreadMessageCountLocal: Int {
        messagesInbox.filter { !isMessageRead($0) }.count
    }
}
