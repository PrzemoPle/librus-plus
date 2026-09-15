import SwiftUI

struct MainTabView: View {
    // NOTE: this view's body must NOT read `repo` — otherwise every background
    // `refreshCore()` (which mutates the repo) re-renders the whole TabView and
    // resets each tab's NavigationStack, kicking the user out of any detail view.
    // Badge counts are read inside the individual tab structs instead.
    @Environment(AppState.self) private var app
    @Environment(TabLayout.self) private var layout

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            DashboardTab()
                .tabItem { Label(MainTab.dashboard.title, systemImage: MainTab.dashboard.systemImage) }
                .tag(MainTab.dashboard)

            ForEach(layout.bar) { tab in
                TabScreen(tab: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }

            MoreTab()
                .tabItem { Label(MainTab.more.title, systemImage: MainTab.more.systemImage) }
                .tag(MainTab.more)
        }
        .minimizingTabBar()
        .onChange(of: layout.bar) {
            // The selected screen just moved to Więcej — don't leave the bar
            // pointing at a tab that no longer exists.
            if !layout.contains(app.selectedTab) { app.selectedTab = .dashboard }
        }
    }
}

private struct DashboardTab: View {
    var body: some View { NavigationStack { DashboardView() } }
}

/// One user-placed tab. Reads the repo here (not in `MainTabView`) so a data
/// refresh re-renders only this tab's badge.
private struct TabScreen: View {
    @Environment(DataRepository.self) private var repo
    let tab: MainTab

    var body: some View {
        NavigationStack { TabRoot(tab: tab) }
            .badge(badge)
    }

    private var badge: Int {
        switch tab {
        case .grades: return repo.unseenGradeCount
        case .messages: return repo.unreadMessageCount
        case .announcements: return repo.unreadAnnouncementCount
        default: return 0
        }
    }
}

/// The root screen for a placeable tab — shared by the tab bar and the Więcej list.
struct TabRoot: View {
    let tab: MainTab

    var body: some View {
        switch tab {
        case .grades: GradesView()
        case .timetable: TimetableView()
        case .attendance: AttendanceView()
        case .announcements: AnnouncementsView()
        case .events: EventsView()
        case .notes: NotesView()
        case .messages: MessagesView()
        case .dashboard: DashboardView()
        case .more: MoreView()
        }
    }
}

private struct MoreTab: View {
    @Environment(DataRepository.self) private var repo
    @Environment(TabLayout.self) private var layout

    var body: some View {
        NavigationStack { MoreView() }
            .badge(badge)
    }

    /// Unread counts only for the screens that actually live under Więcej.
    private var badge: Int {
        let hidden = layout.inMore
        return (hidden.contains(.announcements) ? repo.unreadAnnouncementCount : 0)
            + (hidden.contains(.messages) ? repo.unreadMessageCount : 0)
    }
}

struct MoreView: View {
    @Environment(DataRepository.self) private var repo
    @Environment(TabLayout.self) private var layout

    var body: some View {
        List {
            Section {
                ForEach(layout.inMore) { tab in
                    row(tab.longTitle, tab.systemImage, tab.tint, badge: badge(for: tab)) {
                        TabRoot(tab: tab)
                    }
                }
            }
            Section {
                row("Rozkład dzwonków", "bell.fill", .teal) { BellScheduleView() }
                row("Ustawienia", "gearshape.fill", .gray) { SettingsView() }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground.ignoresSafeArea())
        .navigationTitle("Więcej")
        .childSwitcher()
    }

    private func badge(for tab: MainTab) -> Int {
        switch tab {
        case .announcements: return repo.unreadAnnouncementCount
        case .messages: return repo.unreadMessageCount
        case .grades: return repo.unseenGradeCount
        default: return 0
        }
    }

    @ViewBuilder
    private func row<Destination: View>(
        _ title: String, _ icon: String, _ tint: Color, badge: Int = 0,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: Theme.Space.md) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
