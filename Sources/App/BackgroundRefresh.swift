import Foundation
import BackgroundTasks

/// Opt-in background checks (new grades / timetable changes / new messages).
/// iOS decides if/when this actually runs and throttles sideloaded apps heavily,
/// so it's best-effort — the in-app badges are the reliable path.
enum BackgroundRefresh {
    static let taskIdentifier = "eu.mojlibrus.app.refresh"

    enum Keys {
        static let grades = "notifyNewGrades"
        static let timetable = "notifyTimetableChanges"
        static let messages = "notifyNewMessages"
    }

    /// Back-compat alias for the original single toggle.
    static let enabledKey = Keys.grades

    static var anyEnabled: Bool {
        let d = UserDefaults.standard
        return d.bool(forKey: Keys.grades) || d.bool(forKey: Keys.timetable) || d.bool(forKey: Keys.messages)
    }

    /// iOS almost never runs `BGTaskScheduler` for sideloaded apps, so the same
    /// checks also run when the app is opened / returns to the foreground. Throttled
    /// so bouncing in and out doesn't re-hit every endpoint on each switch.
    private static let lastForegroundCheckKey = "lastForegroundNotificationCheck"

    static func runForegroundChecksIfDue(
        session: LibrusSession, minInterval: TimeInterval = 15 * 60
    ) async {
        guard anyEnabled else { return }
        let d = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        let last = d.double(forKey: lastForegroundCheckKey)
        if last > 0, now - last < minInterval { return }
        d.set(now, forKey: lastForegroundCheckKey)
        await runAllChecks(session: session)
    }

    private static var didRegister = false

    /// Call once, before the app finishes launching.
    static func register() {
        guard !didRegister else { return }
        didRegister = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func scheduleIfEnabled() {
        guard anyEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        scheduleIfEnabled() // chain the next run

        let work = Task {
            await runAllChecks()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    static func runAllChecks(session: LibrusSession? = nil) async {
        // One session for all three checks — a single token refresh, not three
        // separate ones hammering the portal on every background wake-up. The
        // foreground caller passes its live session so we don't spin up a second one.
        let session = session ?? LibrusSession()
        guard await session.isLoggedIn else { return }
        // Every child gets its own pass; with several children the notification
        // says whose grade / lesson / message it is.
        let accounts = await session.accounts
        for account in accounts {
            let label = accounts.count > 1 ? account.shortName : nil
            await runGradeCheck(session: session, account: account, label: label)
            await runTimetableCheck(session: session, account: account, label: label)
            await runMessageCheck(session: session, account: account, label: label)
        }
    }

    // MARK: - Grades

    /// Fetch grades, notify about any not yet seen, then mark them seen.
    static func runGradeCheck(session: LibrusSession, account: AccountSummary, label: String?) async {
        let seen = SeenStores(account: account.login)
        guard UserDefaults.standard.bool(forKey: Keys.grades), seen.grades.hasBaseline else { return }
        let api = LibrusAPI(session: session, account: account.login)

        guard let rawGrades = await api.grades() else { return }

        var subjectByID: [Int: RawSubject] = [:]
        if let subjects = await api.subjects() {
            subjectByID = Dictionary(subjects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }

        let allIDs = Set(rawGrades.map(\.id))
        let newIDs = seen.grades.newOnes(in: allIDs)
        guard !newIDs.isEmpty else { return }

        let newGrades: [GradeItem] = rawGrades
            .filter { newIDs.contains($0.id) }
            .map { g in
                GradeItem(
                    id: g.id, raw: g.grade, value: GradeMath.numericValue(of: g.grade),
                    weight: 0, semester: g.semester, kind: .normal, categoryName: "",
                    teacherName: "", subjectId: g.subject?.id ?? -1,
                    subjectName: g.subject.flatMap { subjectByID[$0.id]?.name } ?? "przedmiot",
                    date: nil, comment: nil
                )
            }

        await NotificationManager.notifyNewGrades(newGrades, student: label)
        seen.grades.merge(newIDs)
    }

    // MARK: - Timetable changes

    /// Scan this + next week for cancellations / substitutions, notify new ones.
    static func runTimetableCheck(session: LibrusSession, account: AccountSummary, label: String?) async {
        let seen = SeenStores(account: account.login)
        guard UserDefaults.standard.bool(forKey: Keys.timetable),
              seen.timetableChanges.hasBaseline else { return }
        let api = LibrusAPI(session: session, account: account.login)

        let today = LibrusDate.today
        var signatures: Set<String> = []
        var labelBySignature: [String: String] = [:]

        for offset in [0, 7] {
            let weekStart = LibrusDate.addDays(offset, to: LibrusDate.weekStart())
            guard let raw = try? await api.timetable(weekStart: weekStart) else { continue }
            for (dateStr, slots) in raw {
                guard let date = LibrusDate.fromYMD(dateStr), date >= today else { continue }
                for lesson in slots.flatMap({ $0 }) {
                    guard let no = lesson.lessonNo else { continue }
                    let kind: String
                    if lesson.isCancelled { kind = "C" }
                    else if lesson.isSubstitution { kind = "S" }
                    else { continue }
                    let subject = lesson.subject?.name ?? "lekcja"
                    let signature = "\(dateStr)#\(no)#\(kind)#\(subject)"
                    signatures.insert(signature)
                    labelBySignature[signature] =
                        "\(date.dayMonthShort): \(kind == "C" ? "odwołane" : "zastępstwo") — \(subject) (lekcja \(no))"
                }
            }
        }

        let new = seen.timetableChanges.newOnes(in: signatures)
        guard !new.isEmpty else { return }
        await NotificationManager.notifyTimetableChanges(
            new.compactMap { labelBySignature[$0] }.sorted(), student: label)
        seen.timetableChanges.merge(signatures)
    }

    // MARK: - Messages

    static func runMessageCheck(session: LibrusSession, account: AccountSummary, label: String?) async {
        guard UserDefaults.standard.bool(forKey: Keys.messages) else { return }
        let seen = SeenStores(account: account.login)
        let client = MessagesClient(session: session, account: account.login)
        guard let list = try? await client.inbox() else { return }

        let unread = list.filter(\.isUnread)
        let newIDs = seen.messageIDs.newOnes(in: Set(unread.map(\.id)))
        guard !newIDs.isEmpty else {
            seen.messageIDs.merge(Set(list.map(\.id)))
            return
        }
        await NotificationManager.notifyNewMessages(unread.filter { newIDs.contains($0.id) }, student: label)
        seen.messageIDs.merge(Set(list.map(\.id)))
    }
}
