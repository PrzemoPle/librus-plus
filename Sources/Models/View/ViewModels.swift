import Foundation

// Joined, display-ready models produced by `DataRepository`.

// MARK: - Grades

enum GradeKind: String, Codable {
    case normal
    case semesterProposed, semesterFinal
    case yearProposed, yearFinal
}

struct GradeItem: Identifiable, Codable, Hashable {
    let id: Int
    let raw: String
    let value: Double?
    let weight: Double
    let semester: Int
    let kind: GradeKind
    let categoryName: String
    let teacherName: String
    let subjectId: Int
    let subjectName: String
    let date: Date?
    let comment: String?

    var countsToAverage: Bool { kind == .normal && value != nil && weight > 0 }
}

struct SubjectGrades: Identifiable, Codable, Hashable {
    var id: Int { subjectId }
    let subjectId: Int
    let subjectName: String
    var grades: [GradeItem]

    func filtered(_ filter: SemesterFilter, current: Int) -> [GradeItem] {
        grades.filter { filter.matches($0.semester, current: current) }
    }

    func normalGrades(_ filter: SemesterFilter, current: Int) -> [GradeItem] {
        filtered(filter, current: current).filter { $0.kind == .normal }
    }

    func average(_ filter: SemesterFilter, current: Int) -> Double? {
        GradeMath.weightedAverage(normalGrades(filter, current: current))
    }

    func proposedFinal(_ filter: SemesterFilter, current: Int) -> GradeItem? {
        filtered(filter, current: current).first { $0.kind == .yearProposed || $0.kind == .semesterProposed }
    }

    func finalGrade(_ filter: SemesterFilter, current: Int) -> GradeItem? {
        filtered(filter, current: current).first { $0.kind == .yearFinal || $0.kind == .semesterFinal }
    }
}

// MARK: - Timetable

struct TimetableEntry: Identifiable, Codable, Hashable {
    let id: String
    let lessonNo: Int
    let start: String
    let end: String
    let subject: String
    let teacher: String?
    let classroom: String?
    /// Set only when the room differs from the originally planned one.
    let originalClassroom: String?
    /// Set only for a substitution lesson moved here from a different day —
    /// i.e. `RawLesson.orgDate` differs from this entry's own day.
    let originalDate: Date?
    let isCancelled: Bool
    let isSubstitution: Bool
    let note: String?

    var roomChanged: Bool {
        guard let originalClassroom, let classroom else { return false }
        return !originalClassroom.isEmpty && originalClassroom != classroom
    }

    var isMoved: Bool { originalDate != nil }

    var startMinutes: Int? { LibrusDate.minutesOfDay(start) }
    var endMinutes: Int? { LibrusDate.minutesOfDay(end) }

    func isOngoing(nowMinutes: Int = LibrusDate.nowMinutesOfDay) -> Bool {
        guard let s = startMinutes, let e = endMinutes else { return false }
        return nowMinutes >= s && nowMinutes < e
    }

    func isUpcoming(nowMinutes: Int = LibrusDate.nowMinutesOfDay) -> Bool {
        guard let s = startMinutes else { return false }
        return s > nowMinutes
    }
}

struct TimetableDay: Identifiable, Codable, Hashable {
    var id: Date { date }
    let date: Date
    let entries: [TimetableEntry]

    var hasLessons: Bool { !entries.isEmpty }
}

// MARK: - Attendance

enum AttendanceKind: String, Codable, CaseIterable {
    case present, presentCustom, absent, absentExcused, belated, released

    var label: String {
        switch self {
        case .present: return "Obecność"
        case .presentCustom: return "Obecność (inne)"
        case .absent: return "Nieobecność"
        case .absentExcused: return "Nieob. usprawiedliwiona"
        case .belated: return "Spóźnienie"
        case .released: return "Zwolnienie"
        }
    }

    var countsAsAbsence: Bool { self == .absent }
}

struct AttendanceItem: Identifiable, Codable, Hashable {
    let id: Int
    let kind: AttendanceKind
    let typeName: String
    let typeShort: String
    let colorHex: String?
    let date: Date?
    let lessonNo: Int?
    let subjectName: String?
    let semester: Int?
}

struct AttendanceSummary: Codable, Hashable {
    var counts: [AttendanceKind: Int] = [:]

    var total: Int { counts.values.reduce(0, +) }
    var present: Int { (counts[.present] ?? 0) + (counts[.presentCustom] ?? 0) }
    var absent: Int { counts[.absent] ?? 0 }
    var absentExcused: Int { counts[.absentExcused] ?? 0 }
    var belated: Int { counts[.belated] ?? 0 }
    var released: Int { counts[.released] ?? 0 }

    /// Common PL-school rule: every 3 lates become one absence. The individual
    /// entries still show as lates — only these totals and the percentage change.
    var latesCountedAsAbsence: Int { belated / 3 }
    /// Recorded absences plus the ones converted from lates.
    var effectiveAbsent: Int { absent + latesCountedAsAbsence }

    /// (present + lates that didn't tip into an absence) / everything considered.
    var attendancePercent: Double? {
        let considered = present + absent + absentExcused + belated + released
        guard considered > 0 else { return nil }
        let latesStillPresent = belated - latesCountedAsAbsence
        return Double(present + latesStillPresent) / Double(considered) * 100
    }
}

// MARK: - Announcements / homework / lucky number

struct AnnouncementItem: Identifiable, Codable, Hashable {
    let id: String
    let subject: String
    let content: String
    let author: String?
    let date: Date?
    let wasReadOnServer: Bool
}

struct CalendarEvent: Identifiable, Codable, Hashable {
    let id: Int
    let date: Date?
    let content: String
    let category: String?
    let subject: String?
    let teacher: String?
    let lessonNo: Int?
    let time: String?

    var isPast: Bool {
        guard let date else { return false }
        return date < LibrusDate.today
    }
}

struct BellPeriod: Identifiable, Codable, Hashable {
    var id: Int { number }
    let number: Int
    let start: String
    let end: String
}

// MARK: - Behaviour notes (uwagi)

struct NoteItem: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case positive, negative, neutral }
    let id: Int
    let text: String
    let category: String?
    let teacher: String?
    let date: Date?
    let kind: Kind
}

// MARK: - School year / semester

struct SchoolYearInfo: Codable, Hashable {
    var className: String? = nil
    var tutor: String? = nil
    var yearStart: Date? = nil
    var secondSemesterStart: Date? = nil
    var yearEnd: Date? = nil

    /// Semester that contains `date`, using the real Librus boundary when known.
    func semester(on date: Date = Date()) -> Int {
        guard let boundary = secondSemesterStart else {
            // Fallback: Polish school year — Feb..Aug ≈ semester 2.
            let month = LibrusDate.calendar.component(.month, from: date)
            return (2...8).contains(month) ? 2 : 1
        }
        return date < boundary ? 1 : 2
    }
}

enum SemesterFilter: String, CaseIterable, Identifiable {
    case current, first, second, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .current: return "Bieżący"
        case .first: return "Sem. 1"
        case .second: return "Sem. 2"
        case .all: return "Całość"
        }
    }
    func matches(_ semester: Int, current: Int) -> Bool {
        switch self {
        case .current: return semester == current
        case .first: return semester == 1
        case .second: return semester == 2
        case .all: return true
        }
    }
}

// MARK: - Messages

struct MessageItem: Identifiable, Codable, Hashable {
    let id: Int
    let subject: String
    let correspondent: String
    let sentDate: Date?
    let readDateServer: Date?
    let hasAttachments: Bool
    var body: String?

    var isUnread: Bool { readDateServer == nil }
}
