import SwiftUI

struct AnnouncementsView: View {
    @Environment(DataRepository.self) private var repo
    @State private var search = ""

    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visible: [AnnouncementItem] {
        guard !query.isEmpty else { return repo.announcements }
        return repo.announcements.filter {
            $0.subject.localizedCaseInsensitiveContains(query)
                || $0.content.localizedCaseInsensitiveContains(query)
                || ($0.author?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        List {
            if visible.isEmpty {
                EmptyStateView(
                    systemImage: query.isEmpty ? "megaphone" : "magnifyingglass",
                    title: query.isEmpty ? "Brak ogłoszeń" : "Nic nie znaleziono",
                    message: query.isEmpty ? nil : "Brak ogłoszeń pasujących do „\(query)”."
                )
            }
            ForEach(visible) { item in
                let read = repo.isAnnouncementRead(item)
                NavigationLink {
                    AnnouncementDetailView(item: item)
                } label: {
                    HStack(alignment: .top, spacing: Theme.Space.md) {
                        Circle()
                            .fill(read ? Color.clear : Color.accentColor)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.subject.isEmpty ? "(bez tematu)" : item.subject)
                                .font(.callout.weight(read ? .regular : .semibold))
                                .lineLimit(2)
                            HStack(spacing: Theme.Space.sm) {
                                if let author = item.author { Text(author) }
                                if let date = item.date { Text(date.dayMonthYear) }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        Haptics.soft()
                        repo.setAnnouncementRead(item, read: !read)
                    } label: {
                        Label(read ? "Nieprzeczytane" : "Przeczytane",
                              systemImage: read ? "envelope.badge" : "envelope.open")
                    }
                    .tint(read ? .gray : .accentColor)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground.ignoresSafeArea())
        .navigationTitle("Ogłoszenia")
        .childSwitcher()
        .searchable(text: $search, prompt: "Temat, treść lub autor")
        .refreshable { await repo.refreshCore() }
        .task { await repo.refreshCoreIfStale() }
    }
}

struct AnnouncementDetailView: View {
    @Environment(DataRepository.self) private var repo
    let item: AnnouncementItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text(item.subject.isEmpty ? "(bez tematu)" : item.subject)
                    .font(.title2.weight(.bold))
                HStack(spacing: Theme.Space.md) {
                    if let author = item.author { Label(author, systemImage: "person.fill") }
                    if let date = item.date { Label(date.dayMonthYear, systemImage: "calendar") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider().padding(.vertical, Theme.Space.xs)

                Text(item.content.isEmpty ? "(brak treści)" : item.content)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.lg)
        }
        .screenBackground()
        .navigationTitle("Ogłoszenie")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { repo.markAnnouncementRead(item) }
    }
}
