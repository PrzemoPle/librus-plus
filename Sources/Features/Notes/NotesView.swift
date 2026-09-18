import SwiftUI

struct NotesView: View {
    @Environment(DataRepository.self) private var repo
    @State private var search = ""

    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visible: [NoteItem] {
        guard !query.isEmpty else { return repo.notes }
        return repo.notes.filter {
            $0.text.localizedCaseInsensitiveContains(query)
                || ($0.category?.localizedCaseInsensitiveContains(query) ?? false)
                || ($0.teacher?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        List {
            if visible.isEmpty {
                EmptyStateView(
                    systemImage: query.isEmpty ? "exclamationmark.bubble" : "magnifyingglass",
                    title: query.isEmpty ? "Brak uwag" : "Nic nie znaleziono",
                    message: query.isEmpty ? nil : "Brak uwag pasujących do „\(query)”."
                )
            }
            ForEach(visible) { note in
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    Image(systemName: icon(for: note.kind))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(color(for: note.kind))
                        .frame(width: 28, height: 28)
                        .background(color(for: note.kind).opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: Theme.Space.sm) {
                            if let category = note.category {
                                Text(category).font(.caption.weight(.semibold))
                                    .foregroundStyle(color(for: note.kind))
                            }
                            Spacer(minLength: 0)
                            if let date = note.date {
                                Text(date.dayMonthYear).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text(note.text).font(.callout)
                        if let teacher = note.teacher {
                            Text(teacher).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground.ignoresSafeArea())
        .navigationTitle("Uwagi")
        .childSwitcher()
        .childSwipe()
        .searchable(text: $search, prompt: "Treść, kategoria, nauczyciel")
        .refreshable { await repo.refreshCore() }
        .task { await repo.refreshCoreIfStale() }
    }

    private func icon(for kind: NoteItem.Kind) -> String {
        switch kind {
        case .positive: return "hand.thumbsup.fill"
        case .negative: return "hand.thumbsdown.fill"
        case .neutral: return "info.circle.fill"
        }
    }

    private func color(for kind: NoteItem.Kind) -> Color {
        switch kind {
        case .positive: return .positive
        case .negative: return .negative
        case .neutral: return .secondary
        }
    }
}
