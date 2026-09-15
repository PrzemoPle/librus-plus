import SwiftUI

/// Settings → Kolory przedmiotów: every subject the app has seen for this child,
/// each with an optional colour. Subjects without a colour look as they always did.
struct SubjectColorsView: View {
    @Environment(DataRepository.self) private var repo
    @Environment(SubjectColors.self) private var colors

    @State private var editing: EditingSubject?
    @State private var confirmClear = false

    private struct EditingSubject: Identifiable {
        let name: String
        var id: String { name }
    }

    /// Subjects from the timetable and the grade book, plus any name that already
    /// carries a colour (so a subject from the other child stays editable here).
    private var subjects: [String] {
        var names: [String: String] = [:] // key -> display name
        for subject in repo.subjectGrades {
            names[SubjectColors.key(subject.subjectName)] = subject.subjectName
        }
        for day in repo.timetableWeeks.values.flatMap({ $0 }) {
            for entry in day.entries where entry.subject != "—" {
                let key = SubjectColors.key(entry.subject)
                if names[key] == nil { names[key] = entry.subject }
            }
        }
        for key in colors.assignments.keys where names[key] == nil {
            names[key] = key.prefix(1).uppercased() + key.dropFirst()
        }
        return names.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        List {
            if subjects.isEmpty {
                Section {
                    EmptyStateView(systemImage: "paintpalette", title: "Brak przedmiotów",
                                   message: "Lista wypełni się po pierwszym pobraniu planu lekcji i ocen.")
                }
            } else {
                Section {
                    ForEach(subjects, id: \.self) { subject in
                        Button {
                            Haptics.tap()
                            editing = EditingSubject(name: subject)
                        } label: {
                            subjectRow(subject)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("Kolor pokazuje się w planie lekcji, na pulpicie i przy ocenach. Przedmiot bez koloru wygląda tak jak dotąd. Kolory są wspólne dla obojga dzieci i zapisane tylko na tym telefonie.")
                }
            }

            if !colors.isEmpty {
                Section {
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label("Usuń wszystkie kolory", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground.ignoresSafeArea())
        .navigationTitle("Kolory przedmiotów")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { item in
            PalettePickerSheet(subject: item.name)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Usunąć wszystkie kolory?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Usuń", role: .destructive) {
                Haptics.warning()
                colors.clearAll()
            }
            Button("Anuluj", role: .cancel) {}
        }
    }

    private func subjectRow(_ subject: String) -> some View {
        let current = colors.palette(for: subject)
        return HStack(spacing: Theme.Space.md) {
            SubjectSwatch(palette: current)
            Text(subject)
            Spacer()
            Text(current?.label ?? "Brak")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(subject): \(current?.label ?? "bez koloru")")
        .accessibilityHint("Otwiera wybór koloru")
    }
}

/// Bottom sheet with the palette grid for one subject.
private struct PalettePickerSheet: View {
    @Environment(SubjectColors.self) private var colors
    @Environment(\.dismiss) private var dismiss
    let subject: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.md), count: 4)

    var body: some View {
        let current = colors.palette(for: subject)
        NavigationStack {
            VStack(spacing: Theme.Space.xl) {
                LazyVGrid(columns: columns, spacing: Theme.Space.lg) {
                    ForEach(SubjectPalette.allCases) { palette in
                        Button {
                            Haptics.selection()
                            colors.set(palette, for: subject)
                            dismiss()
                        } label: {
                            VStack(spacing: Theme.Space.xs) {
                                ZStack {
                                    Circle().fill(palette.color).frame(width: 44, height: 44)
                                    if palette == current {
                                        Image(systemName: "checkmark")
                                            .font(.headline.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                Text(palette.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(palette.label)
                        .accessibilityAddTraits(palette == current ? .isSelected : [])
                    }
                }

                Button {
                    Haptics.selection()
                    colors.set(nil, for: subject)
                    dismiss()
                } label: {
                    Label("Bez koloru", systemImage: "circle.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(current == nil)

                Spacer(minLength: 0)
            }
            .padding(Theme.Space.xl)
            .screenBackground()
            .navigationTitle(subject)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { dismiss() }
                }
            }
        }
    }
}

/// Filled dot for a coloured subject, a hairline ring for an uncoloured one.
struct SubjectSwatch: View {
    let palette: SubjectPalette?
    var size: CGFloat = 18

    var body: some View {
        if let palette {
            Circle()
                .fill(palette.color)
                .frame(width: size, height: size)
        } else {
            Circle()
                .strokeBorder(Color.appHairline, lineWidth: 1)
                .frame(width: size, height: size)
        }
    }
}

/// Small colour dot placed before a subject name in lists; renders nothing when
/// the subject has no colour, so uncoloured layouts don't shift.
struct SubjectDot: View {
    @Environment(SubjectColors.self) private var colors
    let subject: String
    var size: CGFloat = 8

    var body: some View {
        if let color = colors.color(for: subject) {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
    }
}
