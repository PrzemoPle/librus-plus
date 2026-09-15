import WidgetKit
import SwiftUI

// MARK: - Timeline

struct TimetableEntryTL: TimelineEntry {
    let date: Date
    let day: SharedStore.WidgetTimetable.Day?
    let dayLabel: String
    let updated: Date?
    let stale: Bool
    /// Whose timetable this is — the child selected in the app.
    var student: String? = nil
}

struct TimetableProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimetableEntryTL {
        TimetableEntryTL(date: Date(), day: Self.sample, dayLabel: "Dziś", updated: Date(), stale: false, student: "Ania")
    }

    func getSnapshot(in context: Context, completion: @escaping (TimetableEntryTL) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimetableEntryTL>) -> Void) {
        let entry = makeEntry()
        // Refresh at the top of each hour, or in 30 min if we have no data yet.
        let next = entry.day == nil
            ? Date().addingTimeInterval(30 * 60)
            : Calendar.current.nextDate(after: Date(), matching: DateComponents(minute: 0),
                                       matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> TimetableEntryTL {
        let cal = Calendar.current
        let now = Date()
        let payload = SharedStore.loadTimetable()

        // Show today until its last lesson ends, then roll to the next day with lessons.
        let candidates = (payload?.days ?? []).sorted { $0.date < $1.date }
        var chosen: SharedStore.WidgetTimetable.Day?
        var label = "Plan"
        for d in candidates {
            if cal.isDateInToday(d.date) {
                let endMin = d.lessons.compactMap { minutes($0.end) }.max() ?? 0
                let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
                if nowMin < endMin {
                    chosen = d; label = "Dziś"; break
                }
            } else if d.date > now {
                chosen = d
                label = cal.isDateInTomorrow(d.date) ? "Jutro" : d.date.formatted(.dateTime.weekday(.wide))
                break
            }
        }
        if chosen == nil, let first = candidates.first(where: { cal.isDateInToday($0.date) }) {
            chosen = first; label = "Dziś"
        }

        let stale: Bool = {
            guard let u = payload?.updated else { return true }
            return now.timeIntervalSince(u) > 24 * 3600
        }()
        return TimetableEntryTL(date: now, day: chosen, dayLabel: label,
                                updated: payload?.updated, stale: stale, student: payload?.student)
    }

    private func minutes(_ hhmm: String) -> Int? {
        let p = hhmm.split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]) else { return nil }
        return h * 60 + m
    }

    static let sample = SharedStore.WidgetTimetable.Day(
        date: Date(),
        lessons: [
            .init(id: "1", lessonNo: 1, start: "08:00", end: "08:45", subject: "Matematyka",
                  room: "12", isCancelled: false, isSubstitution: false, roomChanged: false, note: nil),
            .init(id: "2", lessonNo: 2, start: "08:55", end: "09:40", subject: "Historia",
                  room: "8", isCancelled: false, isSubstitution: true, roomChanged: true, note: "Zastępstwo"),
            .init(id: "3", lessonNo: 3, start: "09:50", end: "10:35", subject: "WF",
                  room: "sala gimn.", isCancelled: true, isSubstitution: false, roomChanged: false,
                  note: "Lekcja odwołana"),
        ]
    )
}

// MARK: - Widget

struct TimetableWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MojLibrusTimetable", provider: TimetableProvider()) { entry in
            TimetableWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Plan lekcji")
        .description("Najbliższe lekcje wybranego dziecka, z zastępstwami i odwołaniami.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct TimetableWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TimetableEntryTL

    private var maxRows: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 4
        default: return 8
        }
    }

    private var lessons: [SharedStore.WidgetTimetable.Lesson] {
        let all = entry.day?.lessons.sorted { $0.lessonNo < $1.lessonNo } ?? []
        // On "today", drop lessons that already finished.
        guard entry.dayLabel == "Dziś" else { return Array(all.prefix(maxRows)) }
        let cal = Calendar.current
        let nowMin = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
        let upcoming = all.filter { (minutes($0.end) ?? 0) > nowMin }
        return Array((upcoming.isEmpty ? all : upcoming).prefix(maxRows))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(entry.dayLabel).font(.caption.bold())
                if let student = entry.student, !student.isEmpty {
                    Text("· \(student)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if entry.stale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            if lessons.isEmpty {
                Spacer()
                VStack(spacing: 4) {
                    Text(entry.day == nil ? "Otwórz aplikację i wejdź w Plan" : "Brak lekcji")
                        .font(.footnote).foregroundStyle(.secondary)
                    if entry.day == nil, family != .systemSmall {
                        Text(SharedStore.status)
                            .font(.caption2).foregroundStyle(.tertiary)
                            .lineLimit(2).multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(lessons) { lesson in
                    row(lesson)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(family == .systemSmall ? 2 : 4)
    }

    @ViewBuilder private func row(_ l: SharedStore.WidgetTimetable.Lesson) -> some View {
        HStack(spacing: 6) {
            Text(l.start)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(l.isCancelled ? .secondary : .primary)
                .frame(width: 38, alignment: .leading)
            Text(l.subject)
                .font(.caption2.weight(.medium))
                .strikethrough(l.isCancelled)
                .foregroundStyle(l.isCancelled ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 2)
            if l.isCancelled {
                Text("odw.").font(.caption2.bold()).foregroundStyle(.red)
            } else if l.isSubstitution {
                Text("zast.").font(.caption2.bold()).foregroundStyle(.orange)
            } else if family != .systemSmall, let room = l.room {
                Text(l.roomChanged ? "→\(room)" : room)
                    .font(.caption2)
                    .foregroundStyle(l.roomChanged ? .orange : .secondary)
            }
        }
    }

    private func minutes(_ hhmm: String) -> Int? {
        let p = hhmm.split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]) else { return nil }
        return h * 60 + m
    }
}
