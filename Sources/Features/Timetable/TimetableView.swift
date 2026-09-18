import SwiftUI
import Foundation

struct TimetableView: View {
    @Environment(DataRepository.self) private var repo
    @Environment(AppState.self) private var app

    /// Kept in `AppState` so the same week stays on screen when switching children.
    private var weekStart: Date { app.timetableWeekStart }
    @State private var isLoading = false
    @State private var jumpTick = 0
    @State private var selection: LessonSelection?

    /// A tapped lesson plus the day it belongs to — the entry alone has no date.
    struct LessonSelection: Identifiable {
        let entry: TimetableEntry
        let date: Date
        var id: String { entry.id }
    }

    private var weekKey: String { LibrusDate.ymdString(weekStart) }
    private var days: [TimetableDay] { repo.timetableWeeks[weekKey] ?? [] }
    private var isCurrentWeek: Bool { LibrusDate.isSameDay(weekStart, LibrusDate.weekStart()) }

    /// `id` of today's day card, when the shown week actually contains today.
    private var todayID: Date? {
        days.first { LibrusDate.isSameDay($0.date, Date()) }?.date
    }

    var body: some View {
        VStack(spacing: 0) {
            weekSwitcher
            Divider().opacity(0.5)

            if days.isEmpty {
                if isLoading {
                    ProgressView().frame(maxHeight: .infinity)
                } else if let error = repo.timetableError {
                    VStack {
                        ErrorBanner(message: error) { Task { await load() } }
                            .padding(Theme.Space.lg)
                        Spacer()
                    }
                } else {
                    EmptyStateView(systemImage: "calendar", title: "Brak planu",
                                   message: "Dla tego tygodnia nie ma danych.")
                        .frame(maxHeight: .infinity)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: Theme.Space.lg) {
                            ForEach(days) { day in
                                dayCard(day).id(day.date)
                            }
                        }
                        .padding(Theme.Space.lg)
                    }
                    // The week header has its own swipe (previous / next week), so
                    // the child swipe covers only the lesson list.
                    .childSwipe()
                    .onAppear { jumpToToday(proxy, animated: false) }
                    .onChange(of: weekKey) { jumpToToday(proxy, animated: false) }
                    .onChange(of: days.count) { jumpToToday(proxy, animated: false) }
                    .onChange(of: jumpTick) { jumpToToday(proxy, animated: true) }
                }
            }
        }
        .screenBackground()
        .navigationTitle("Plan lekcji")
        .navigationBarTitleDisplayMode(.inline)
        .childSwitcher()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Dziś") {
                    Haptics.tap()
                    withAnimation(Theme.Motion.standard) { app.timetableWeekStart = LibrusDate.weekStart() }
                    jumpTick &+= 1
                }
            }
        }
        .task(id: weekKey) { await loadIfNeeded() }
        .refreshable { await load() }
        .onDisappear { repo.markTimetableChangesSeen() }
        .sheet(item: $selection) { picked in
            LessonDetailView(entry: picked.entry, date: picked.date)
        }
    }

    private func jumpToToday(_ proxy: ScrollViewProxy, animated: Bool) {
        let id = todayID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let id else { return }
            if animated {
                withAnimation(Theme.Motion.standard) { proxy.scrollTo(id, anchor: .top) }
            } else {
                proxy.scrollTo(id, anchor: .top)
            }
        }
    }

    private var weekSwitcher: some View {
        HStack {
            Button { shift(-7) } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold))
            }
            .frame(width: 44, height: 44)
            .glassControlStyle()
            .accessibilityLabel("Poprzedni tydzień")

            Spacer()
            VStack(spacing: 1) {
                Text("\(weekStart.dayMonthShort) – \(LibrusDate.addDays(6, to: weekStart).dayMonthShort)")
                    .font(.subheadline.weight(.semibold))
                if isCurrentWeek {
                    Text("bieżący tydzień").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()

            Button { shift(7) } label: {
                Image(systemName: "chevron.right").font(.body.weight(.semibold))
            }
            .frame(width: 44, height: 44)
            .glassControlStyle()
            .accessibilityLabel("Następny tydzień")
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, Theme.Space.xs)
        // Swipe the switcher itself — attaching this to the scroll area below would
        // fight the vertical scroll gesture.
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -40 { shift(7) }
                    else if value.translation.width > 40 { shift(-7) }
                }
        )
    }

    private func dayCard(_ day: TimetableDay) -> some View {
        let isToday = LibrusDate.isSameDay(day.date, Date())
        return Card(padding: Theme.Space.md) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.sm) {
                    Text(day.date.weekdayName.capitalized)
                        .font(.subheadline.weight(.semibold))
                    Text(day.date.dayMonthShort)
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if isToday {
                        Text("dziś")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Space.sm).padding(.vertical, 2)
                            .background(.tint, in: Capsule())
                    }
                }

                if day.entries.isEmpty {
                    Text("Brak lekcji").font(.subheadline).foregroundStyle(.secondary)
                        .padding(.vertical, Theme.Space.xs)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(day.entries.enumerated()), id: \.element.id) { idx, entry in
                            Button {
                                Haptics.tap()
                                selection = LessonSelection(entry: entry, date: day.date)
                            } label: {
                                LessonRow(entry: entry, highlight: isToday && entry.isOngoing())
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if idx < day.entries.count - 1 {
                                Divider().padding(.leading, 58).opacity(0.4)
                            }
                        }
                    }
                }
            }
        }
    }

    private func shift(_ d: Int) {
        Haptics.selection()
        withAnimation(Theme.Motion.standard) { app.timetableWeekStart = LibrusDate.addDays(d, to: weekStart) }
    }

    private func loadIfNeeded() async {
        if repo.timetableWeeks[weekKey] == nil { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        await repo.loadTimetable(weekStart: weekStart)
    }
}

struct LessonRow: View {
    @Environment(SubjectColors.self) private var subjectColors
    let entry: TimetableEntry
    var highlight: Bool = false

    /// Optional user-picked colour; the ongoing lesson keeps the accent.
    private var subjectColor: Color? {
        highlight ? nil : subjectColors.color(for: entry.subject)
    }

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            VStack(spacing: 1) {
                Text("\(entry.lessonNo)")
                    .font(.headline.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(highlight ? AnyShapeStyle(.tint)
                                     : AnyShapeStyle(subjectColor ?? Color.primary))
                Text(entry.start).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Text(entry.end).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }
            .frame(width: 46)

            Rectangle()
                .fill(highlight ? AnyShapeStyle(.tint) : AnyShapeStyle(subjectColor ?? Color.clear))
                .frame(width: 3)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.subject)
                    .font(.callout.weight(.medium))
                    .strikethrough(entry.isCancelled)
                    .foregroundStyle(entry.isCancelled ? .secondary : .primary)
                HStack(spacing: Theme.Space.sm) {
                    if let teacher = entry.teacher { Text(teacher) }
                    roomLabel
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if entry.isCancelled {
                    badge("Lekcja odwołana", .negative, "xmark.circle.fill")
                } else if entry.isMoved {
                    badge(entry.note ?? "Przeniesiona", .info, "arrow.turn.up.right")
                } else if entry.isSubstitution {
                    badge(entry.note ?? "Zastępstwo", .warning, "arrow.triangle.2.circlepath")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Space.sm)
        .opacity(entry.isCancelled ? 0.65 : 1)
    }

    @ViewBuilder private var roomLabel: some View {
        if entry.roomChanged, let room = entry.classroom {
            HStack(spacing: 2) {
                if let org = entry.originalClassroom {
                    Text("sala \(org)").strikethrough()
                }
                Text("→ \(room)")
            }
            .foregroundStyle(Color.warning)
            .fontWeight(.semibold)
        } else if let room = entry.classroom {
            Text("sala \(room)")
        }
    }

    private func badge(_ text: String, _ color: Color, _ icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, Theme.Space.sm).padding(.vertical, 2)
        .background(color.opacity(0.14), in: Capsule())
    }
}

// MARK: - Lesson detail

/// Everything Librus knows about one slot — the row itself only has room for a
/// summary, and the substitution note in particular is usually truncated there.
struct LessonDetailView: View {
    let entry: TimetableEntry
    let date: Date

    @Environment(\.dismiss) private var dismiss

    private var hasChange: Bool {
        entry.isCancelled || entry.isSubstitution || entry.roomChanged
            || !(entry.note ?? "").isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    KeyValueRow(key: "Przedmiot", value: entry.subject)
                    KeyValueRow(key: "Lekcja", value: "\(entry.lessonNo)")
                    KeyValueRow(key: "Godziny", value: "\(entry.start) – \(entry.end)")
                    KeyValueRow(key: "Dzień", value: "\(date.weekdayName.capitalized), \(date.dayMonthYear)")
                    if let minutes = length {
                        KeyValueRow(key: "Czas trwania", value: "\(minutes) min")
                    }
                }

                if entry.teacher != nil || entry.classroom != nil {
                    Section {
                        if let teacher = entry.teacher {
                            KeyValueRow(key: "Nauczyciel", value: teacher)
                        }
                        if let room = entry.classroom {
                            KeyValueRow(key: "Sala", value: room)
                        }
                        if entry.roomChanged, let original = entry.originalClassroom {
                            KeyValueRow(key: "Sala pierwotna", value: original)
                        }
                    }
                }

                if hasChange {
                    Section("Zmiany") {
                        if entry.isCancelled {
                            Label("Lekcja odwołana", systemImage: "xmark.circle.fill")
                                .foregroundStyle(Color.negative)
                        }
                        if entry.isMoved {
                            Label("Przeniesiona", systemImage: "arrow.turn.up.right")
                                .foregroundStyle(Color.info)
                        } else if entry.isSubstitution {
                            Label("Zastępstwo", systemImage: "arrow.triangle.2.circlepath")
                                .foregroundStyle(Color.warning)
                        }
                        if let orgDate = entry.originalDate {
                            KeyValueRow(key: "Pierwotny termin",
                                        value: "\(orgDate.weekdayName.capitalized), \(orgDate.dayMonthYear)")
                        }
                        if entry.roomChanged {
                            Label("Zmiana sali", systemImage: "arrow.left.arrow.right")
                                .foregroundStyle(Color.warning)
                        }
                        if let note = entry.note, !note.isEmpty {
                            Text(note).font(.callout).textSelection(.enabled)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appGroupedBackground.ignoresSafeArea())
            .navigationTitle(entry.subject)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var length: Int? {
        guard let s = entry.startMinutes, let e = entry.endMinutes, e > s else { return nil }
        return e - s
    }
}
