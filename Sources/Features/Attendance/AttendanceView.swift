import SwiftUI

struct AttendanceView: View {
    @Environment(DataRepository.self) private var repo
    @State private var filter: SemesterFilter = .current

    private var items: [AttendanceItem] {
        repo.attendanceItems.filter {
            filter.matches($0.semester ?? repo.currentSemester, current: repo.currentSemester)
        }
    }

    private var summary: AttendanceSummary {
        var s = AttendanceSummary()
        for item in items { s.counts[item.kind, default: 0] += 1 }
        return s
    }

    private struct SubjectAttendance: Identifiable {
        let id = UUID()
        let subject: String
        let absent: Int
        let excused: Int
        let belated: Int
    }

    private var bySubject: [SubjectAttendance] {
        let named = items.filter { $0.subjectName != nil }
        let groups: [String: [AttendanceItem]] = Dictionary(grouping: named) { $0.subjectName ?? "" }
        var rows: [SubjectAttendance] = []
        for (name, entries) in groups {
            let absent = entries.filter { $0.kind == .absent }.count
            let excused = entries.filter { $0.kind == .absentExcused }.count
            let belated = entries.filter { $0.kind == .belated }.count
            guard absent + excused + belated > 0 else { continue }
            rows.append(SubjectAttendance(subject: name, absent: absent, excused: excused, belated: belated))
        }
        return rows.sorted { ($0.absent + $0.belated) > ($1.absent + $1.belated) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.lg) {
                SemesterPicker(selection: $filter)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Space.md) {
                    StatTile(value: summary.attendancePercent.map { String(format: "%.0f%%", $0) } ?? "—",
                             label: "Frekwencja", color: .positive, systemImage: "chart.pie.fill")
                    StatTile(value: "\(summary.effectiveAbsent)", label: "Nieobecności",
                             color: .negative, systemImage: "xmark")
                    StatTile(value: "\(summary.absentExcused)", label: "Usprawiedliwione",
                             color: .warning, systemImage: "checkmark.shield")
                    StatTile(value: "\(summary.belated)", label: "Spóźnienia",
                             color: .info, systemImage: "clock")
                }

                if summary.latesCountedAsAbsence > 0 {
                    Text("Wliczono \(summary.latesCountedAsAbsence) nieob. ze spóźnień (3 spóźnienia = 1 nieobecność). Na liście poniżej pozostają jako spóźnienia.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !bySubject.isEmpty {
                    SectionCard("Wg przedmiotów", systemImage: "list.bullet") {
                        VStack(spacing: Theme.Space.sm) {
                            ForEach(bySubject) { row in
                                HStack {
                                    Text(row.subject).font(.callout).lineLimit(1)
                                    Spacer(minLength: Theme.Space.sm)
                                    if row.absent > 0 { Pill(text: "\(row.absent) nb", color: .negative, prominent: false) }
                                    if row.excused > 0 { Pill(text: "\(row.excused) u", color: .warning, prominent: false) }
                                    if row.belated > 0 { Pill(text: "\(row.belated) sp", color: .info, prominent: false) }
                                }
                            }
                        }
                    }
                }

                if items.isEmpty {
                    EmptyStateView(systemImage: "person.crop.circle.badge.checkmark",
                                   title: "Brak wpisów frekwencji")
                        .padding(.top, Theme.Space.xl)
                } else {
                    SectionCard("Wpisy", systemImage: "clock.arrow.circlepath") {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                                entryRow(item)
                                if idx < items.count - 1 { Divider().opacity(0.4) }
                            }
                        }
                    }
                }
            }
            .padding(Theme.Space.lg)
        }
        .screenBackground()
        .navigationTitle("Frekwencja")
        .childSwitcher()
        .refreshable { await repo.refreshCore() }
        .animation(Theme.Motion.quick, value: filter)
    }

    private func entryRow(_ item: AttendanceItem) -> some View {
        let color = Color(librusHex: item.colorHex) ?? attendanceColor(item.kind)
        return HStack(spacing: Theme.Space.md) {
            Text(item.typeShort)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(item.subjectName ?? item.typeName).font(.callout).lineLimit(1)
                Text(item.typeName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Space.sm)
            VStack(alignment: .trailing, spacing: 1) {
                if let date = item.date { Text(date.dayMonthShort).font(.caption) }
                if let no = item.lessonNo {
                    Text("lekcja \(no)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, Theme.Space.sm)
    }
}
