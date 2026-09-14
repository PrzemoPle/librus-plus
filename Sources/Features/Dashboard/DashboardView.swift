import SwiftUI

struct DashboardView: View {
    @Environment(DataRepository.self) private var repo

    private var todayEntries: [TimetableEntry] {
        let key = LibrusDate.ymdString(LibrusDate.weekStart())
        return repo.timetableWeeks[key]?
            .first { LibrusDate.isSameDay($0.date, Date()) }?
            .entries.filter { !$0.isCancelled } ?? []
    }

    private var currentLesson: TimetableEntry? {
        todayEntries.first { $0.isOngoing() }
    }

    private var nextLesson: TimetableEntry? {
        todayEntries.first { $0.isUpcoming() }
    }

    private var upcomingEntries: [TimetableEntry] {
        let now = LibrusDate.nowMinutesOfDay
        let relevant = todayEntries.filter { $0.isOngoing(nowMinutes: now) || $0.isUpcoming(nowMinutes: now) }
        return Array((relevant.isEmpty ? todayEntries : relevant).prefix(4))
    }

    private var recentGrades: [GradeItem] {
        repo.subjectGrades.flatMap(\.grades)
            .filter { $0.kind == .normal }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .prefix(6).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.lg) {
                if let error = repo.lastError {
                    ErrorBanner(message: error) { Task { await refresh() } }
                }

                nowCard
                todayCard
                if !recentGrades.isEmpty { recentGradesCard }
                nextEventCard
                countersRow

                if let sync = repo.lastSync {
                    Text("Zsynchronizowano \(sync.formattedPL("d MMM, HH:mm"))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Space.xs)
                }
            }
            .padding(Theme.Space.lg)
        }
        .screenBackground()
        .navigationTitle(repo.studentName.isEmpty ? "Pulpit" : repo.studentName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if repo.isRefreshing { ProgressView() }
            }
        }
        .childSwitcher()
        .refreshable { await refresh() }
        .task {
            await repo.refreshCoreIfStale()
            if repo.timetableWeeks.isEmpty {
                await repo.loadTimetable(weekStart: LibrusDate.weekStart())
            }
        }
    }

    private func refresh() async {
        await repo.refreshCore()
        await repo.loadTimetable(weekStart: LibrusDate.weekStart())
    }

    // MARK: Now / next

    private var nowCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                if let className = repo.schoolYear.className {
                    Text("Klasa \(className) · semestr \(repo.currentSemester)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                // Ticks every minute so the countdown updates and the card rolls
                // over from "Teraz" → "Następna" → "zakończone" on its own.
                TimelineView(.everyMinute) { _ in
                    nowLesson
                }
            }
        }
    }

    @ViewBuilder private var nowLesson: some View {
        let nowSec = LibrusDate.nowSecondsOfDay
        if let lesson = currentLesson {
            lessonHeadline(
                kicker: "Teraz · do \(lesson.end)", lesson: lesson, accent: true,
                countdown: lesson.endMinutes.map {
                    Countdown(minutesLeft: minutesCeil($0 * 60 - nowSec), caption: "do końca")
                }
            )
        } else if let lesson = nextLesson {
            let startsIn = (lesson.startMinutes ?? 0) * 60 - nowSec
            lessonHeadline(
                kicker: "Następna · \(lesson.start)", lesson: lesson, accent: false,
                countdown: lesson.startMinutes != nil && startsIn <= 90 * 60
                    ? Countdown(minutesLeft: minutesCeil(startsIn), caption: "do startu")
                    : nil
            )
        } else {
            HStack(spacing: Theme.Space.md) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(todayEntries.isEmpty ? "Dziś nie ma lekcji" : "Lekcje na dziś zakończone")
                        .font(.headline)
                    Text("Miłego dnia").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Seconds → whole minutes, rounded up, never negative.
    private func minutesCeil(_ seconds: Int) -> Int { max(0, (seconds + 59) / 60) }

    private func lessonHeadline(
        kicker: String, lesson: TimetableEntry, accent: Bool, countdown: Countdown? = nil
    ) -> some View {
        HStack(spacing: Theme.Space.md) {
            RoundedRectangle(cornerRadius: 3)
                .fill(accent ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.appHairline))
                .frame(width: 4)
                .frame(maxHeight: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary))
                Text(lesson.subject)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: Theme.Space.sm) {
                    if let t = lesson.teacher { Text(t) }
                    if let r = lesson.classroom {
                        Text(lesson.roomChanged ? "→ sala \(r)" : "sala \(r)")
                            .foregroundStyle(lesson.roomChanged ? Color.warning : .secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Space.sm)
            countdown
        }
    }

    /// Trailing minutes-remaining readout on the "now" card.
    private struct Countdown: View {
        let minutesLeft: Int
        let caption: String

        var body: some View {
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(minutesLeft) min")
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.tint)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Today's plan

    private var todayCard: some View {
        SectionCard("Plan na dziś", systemImage: "calendar") {
            NavigationLink {
                TimetableView()
            } label: {
                Text("Cały tydzień").font(.caption.weight(.semibold))
            }
        } content: {
            if todayEntries.isEmpty {
                Text("Brak lekcji w planie na dziś.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                // Same minute tick as the "now" card, so the list drops finished
                // lessons and re-highlights the current one without a refresh.
                TimelineView(.everyMinute) { _ in
                    VStack(spacing: Theme.Space.sm) {
                        ForEach(upcomingEntries) { entry in
                            let ongoing = entry.isOngoing()
                            HStack(spacing: Theme.Space.md) {
                                Text(entry.start)
                                    .font(.callout.monospacedDigit())
                                    .fontWeight(ongoing ? .semibold : .regular)
                                    .foregroundStyle(ongoing ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary))
                                    .frame(minWidth: 46, alignment: .leading)
                                Text(entry.subject)
                                    .font(.callout)
                                    .fontWeight(ongoing ? .medium : .regular)
                                    .strikethrough(entry.isCancelled)
                                Spacer(minLength: Theme.Space.sm)
                                if entry.roomChanged, let r = entry.classroom {
                                    Chip(text: "→ \(r)", tint: .warning)
                                } else if let r = entry.classroom {
                                    Text(r).font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Recent grades

    private var recentGradesCard: some View {
        SectionCard("Najnowsze oceny", systemImage: "checkmark.seal") {
            NavigationLink {
                GradesView()
            } label: {
                Text("Wszystkie").font(.caption.weight(.semibold))
            }
        } content: {
            VStack(spacing: Theme.Space.sm) {
                ForEach(recentGrades) { grade in
                    NavigationLink { GradeDetailView(grade: grade) } label: {
                        HStack(spacing: Theme.Space.md) {
                            Pill(text: grade.raw, color: gradeColor(for: grade.value))
                                .frame(minWidth: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: Theme.Space.xs) {
                                    Text(grade.subjectName).font(.callout).lineLimit(1)
                                    if repo.isGradeUnseen(grade) {
                                        Text("NOWE")
                                            .font(.system(size: 9, weight: .heavy))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                                            .background(.tint, in: Capsule())
                                    }
                                }
                                HStack(spacing: Theme.Space.sm) {
                                    if !grade.categoryName.isEmpty { Text(grade.categoryName).lineLimit(1) }
                                    if grade.weight > 0 { Text("waga \(GradeMath.format(grade.weight))") }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: Theme.Space.sm)
                            if let date = grade.date {
                                Text(date.dayMonthShort).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Next event

    @ViewBuilder private var nextEventCard: some View {
        if let ev = repo.nextEvent {
            Card {
                HStack(spacing: Theme.Space.md) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.title3)
                        .foregroundStyle(Color.warning)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Najbliższy wpis w terminarzu")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(ev.content.isEmpty ? (ev.category ?? "wydarzenie") : ev.content)
                            .font(.callout.weight(.medium))
                            .lineLimit(2)
                        HStack(spacing: Theme.Space.sm) {
                            if let subject = ev.subject { Text(subject) }
                            if let date = ev.date { Text(date.dayMonthShort) }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Counters

    private var countersRow: some View {
        HStack(spacing: Theme.Space.md) {
            NavigationLink {
                AnnouncementsView()
            } label: {
                StatTile(value: "\(repo.unreadAnnouncementCount)", label: "Ogłoszenia",
                         color: .accentColor, systemImage: "megaphone.fill")
            }
            NavigationLink {
                MessagesView()
            } label: {
                StatTile(value: "\(repo.unreadMessageCount)", label: "Wiadomości",
                         color: .accentColor, systemImage: "envelope.fill")
            }
        }
        .buttonStyle(.plain)
    }
}
