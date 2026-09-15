import SwiftUI

struct EventsView: View {
    @Environment(DataRepository.self) private var repo
    @State private var showPast = false
    @State private var search = ""

    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visible: [CalendarEvent] {
        let base = showPast ? repo.events : repo.events.filter { !$0.isPast }
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.content.localizedCaseInsensitiveContains(query)
                || ($0.category?.localizedCaseInsensitiveContains(query) ?? false)
                || ($0.subject?.localizedCaseInsensitiveContains(query) ?? false)
                || ($0.teacher?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var grouped: [(key: String, items: [CalendarEvent])] {
        let buckets: [String: [CalendarEvent]] = Dictionary(grouping: visible) { event in
            event.date?.dayMonthYear ?? "Bez daty"
        }
        var rows: [(key: String, items: [CalendarEvent])] = []
        for (key, items) in buckets {
            rows.append((key: key, items: items))
        }
        rows.sort { lhs, rhs in
            let l = lhs.items.first?.date ?? .distantFuture
            let r = rhs.items.first?.date ?? .distantFuture
            return l < r
        }
        return rows
    }

    private var emptyMessage: String? {
        if !query.isEmpty { return "Brak wpisów pasujących do „\(query)”." }
        if repo.events.isEmpty { return nil }
        return "Włącz „Pokaż minione”, aby zobaczyć starsze wpisy."
    }

    var body: some View {
        List {
            if visible.isEmpty {
                EmptyStateView(systemImage: query.isEmpty ? "calendar.badge.clock" : "magnifyingglass",
                               title: query.isEmpty ? "Brak wpisów w terminarzu" : "Nic nie znaleziono",
                               message: emptyMessage)
            }

            ForEach(grouped, id: \.key) { group in
                Section {
                    ForEach(group.items) { ev in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: Theme.Space.sm) {
                                if let category = ev.category { Chip(text: category, tint: .accentColor) }
                                if let subject = ev.subject {
                                    Text(subject).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if let time = ev.time {
                                    Text(time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                } else if let no = ev.lessonNo {
                                    Text("lekcja \(no)").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            Text(ev.content.isEmpty ? "(bez opisu)" : ev.content).font(.callout)
                            if let teacher = ev.teacher {
                                Text(teacher).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(group.key).textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground.ignoresSafeArea())
        .navigationTitle("Terminarz")
        .childSwitcher()
        .searchable(text: $search, prompt: "Opis, kategoria, przedmiot")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Pokaż minione", isOn: $showPast.animation(Theme.Motion.quick))
                } label: {
                    Label("Filtr", systemImage: showPast
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .refreshable { await repo.refreshCore() }
        .task { await repo.refreshCoreIfStale() }
    }
}
