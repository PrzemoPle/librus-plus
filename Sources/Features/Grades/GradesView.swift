import SwiftUI

struct GradesView: View {
    @Environment(DataRepository.self) private var repo
    @State private var filter: SemesterFilter = .current
    @State private var simulatorSubject: SubjectGrades?
    @State private var search = ""

    private var current: Int { repo.currentSemester }

    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Grades of a subject after the semester filter and the search query. A query
    /// that matches the subject name keeps all of its grades; otherwise only the
    /// grades that match themselves (category, teacher, the mark) stay.
    private func grades(in subject: SubjectGrades) -> [GradeItem] {
        let all = subject.filtered(filter, current: current)
        guard !query.isEmpty, !subject.subjectName.localizedCaseInsensitiveContains(query) else {
            return all
        }
        return all.filter {
            $0.categoryName.localizedCaseInsensitiveContains(query)
                || $0.teacherName.localizedCaseInsensitiveContains(query)
                || $0.raw.localizedCaseInsensitiveContains(query)
        }
    }

    private var visibleSubjects: [SubjectGrades] {
        repo.subjectGrades.filter { !grades(in: $0).isEmpty }
    }

    private var overallAverage: Double? {
        let a = visibleSubjects.compactMap { $0.average(filter, current: current) }
        return a.isEmpty ? nil : a.reduce(0, +) / Double(a.count)
    }

    var body: some View {
        List {
            if let error = repo.lastError {
                Section { ErrorBanner(message: error) { Task { await repo.refreshCore() } } }
                    .listRowInsets(EdgeInsets(top: 0, leading: Theme.Space.lg, bottom: Theme.Space.sm, trailing: Theme.Space.lg))
                    .listRowBackground(Color.clear)
            }

            Section {
                SemesterPicker(selection: $filter)
                    .listRowInsets(EdgeInsets(top: Theme.Space.xs, leading: 0, bottom: Theme.Space.sm, trailing: 0))
                    .listRowBackground(Color.clear)

                if let avg = overallAverage {
                    HStack {
                        Text("Średnia ze średnich")
                            .font(.subheadline)
                        Spacer()
                        Text(GradeMath.format(avg))
                            .font(.title3.weight(.bold))
                            .fontDesign(.rounded)
                            .foregroundStyle(gradeColor(for: avg))
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if visibleSubjects.isEmpty {
                Section {
                    EmptyStateView(
                        systemImage: query.isEmpty ? "checkmark.seal" : "magnifyingglass",
                        title: query.isEmpty ? "Brak ocen" : "Nic nie znaleziono",
                        message: query.isEmpty
                            ? "Zmień semestr lub pociągnij w dół, aby odświeżyć."
                            : "Brak ocen pasujących do „\(query)”."
                    )
                }
            }

            ForEach(visibleSubjects) { subject in
                Section {
                    ForEach(grades(in: subject)) { grade in
                        NavigationLink {
                            GradeDetailView(grade: grade)
                        } label: {
                            GradeRow(grade: grade, isNew: repo.isGradeUnseen(grade))
                        }
                        .contextMenu {
                            Button {
                                Haptics.tap()
                                simulatorSubject = subject
                            } label: {
                                Label("Symulator średniej", systemImage: "function")
                            }
                        }
                    }
                } header: {
                    HStack(spacing: Theme.Space.sm) {
                        Text(subject.subjectName)
                        Spacer(minLength: Theme.Space.sm)
                        if let avg = subject.average(filter, current: current) {
                            Text(GradeMath.format(avg))
                                .fontDesign(.rounded)
                                .foregroundStyle(gradeColor(for: avg))
                        }
                        Button {
                            Haptics.tap()
                            simulatorSubject = subject
                        } label: {
                            Image(systemName: "function")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tint)
                                .padding(.horizontal, Theme.Space.sm)
                                .padding(.vertical, 3)
                                .background(Color.appFill, in: Capsule())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Symulator średniej — \(subject.subjectName)")
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground.ignoresSafeArea())
        .navigationTitle("Oceny")
        .childSwitcher()
        .searchable(text: $search, prompt: "Przedmiot, kategoria, nauczyciel")
        .refreshable { await repo.refreshCore() }
        .onDisappear { repo.markGradesSeen() }
        .sheet(item: $simulatorSubject) { subject in
            GradeSimulatorView(subjectName: subject.subjectName,
                               realGrades: subject.normalGrades(filter, current: current))
        }
        .animation(Theme.Motion.quick, value: filter)
    }
}

struct GradeRow: View {
    let grade: GradeItem
    var isNew: Bool = false

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Pill(text: grade.raw, color: gradeColor(for: grade.value))
                .frame(minWidth: 42)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.Space.sm) {
                    Text(grade.categoryName.isEmpty ? Self.label(for: grade.kind) : grade.categoryName)
                        .font(.callout)
                        .lineLimit(1)
                    if isNew {
                        Text("NOWE")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(.tint, in: Capsule())
                    }
                }
                HStack(spacing: Theme.Space.sm) {
                    if grade.weight > 0 { Text("waga \(GradeMath.format(grade.weight))") }
                    if let date = grade.date { Text(date.dayMonthShort) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        // The mark's colour carries meaning — spell the whole row out for VoiceOver.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["Ocena \(grade.raw)"]
        let name = grade.categoryName.isEmpty ? Self.label(for: grade.kind) : grade.categoryName
        parts.append(name)
        if grade.weight > 0 { parts.append("waga \(GradeMath.format(grade.weight))") }
        if let date = grade.date { parts.append(date.dayMonthYear) }
        if isNew { parts.append("nowa") }
        return parts.joined(separator: ", ")
    }

    static func label(for kind: GradeKind) -> String {
        switch kind {
        case .normal: return "Ocena"
        case .semesterProposed: return "Propozycja śródroczna"
        case .semesterFinal: return "Ocena śródroczna"
        case .yearProposed: return "Propozycja roczna"
        case .yearFinal: return "Ocena roczna"
        }
    }
}

struct GradeDetailView: View {
    let grade: GradeItem

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Ocena").foregroundStyle(.secondary)
                    Spacer()
                    Pill(text: grade.raw, color: gradeColor(for: grade.value))
                        .scaleEffect(1.15)
                }
                if let value = grade.value { KeyValueRow(key: "Wartość", value: GradeMath.format(value)) }
                if grade.weight > 0 { KeyValueRow(key: "Waga", value: GradeMath.format(grade.weight)) }
                KeyValueRow(key: "Liczona do średniej", value: grade.countsToAverage ? "Tak" : "Nie")
                KeyValueRow(key: "Rodzaj", value: GradeRow.label(for: grade.kind))
            }
            Section {
                KeyValueRow(key: "Przedmiot", value: grade.subjectName)
                if !grade.categoryName.isEmpty { KeyValueRow(key: "Kategoria", value: grade.categoryName) }
                if !grade.teacherName.isEmpty { KeyValueRow(key: "Nauczyciel", value: grade.teacherName) }
                if let date = grade.date { KeyValueRow(key: "Data", value: date.dayMonthYear) }
                KeyValueRow(key: "Semestr", value: "\(grade.semester)")
            }
            if let comment = grade.comment {
                Section("Komentarz") { Text(comment) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground.ignoresSafeArea())
        .navigationTitle("Szczegóły oceny")
        .navigationBarTitleDisplayMode(.inline)
    }
}
