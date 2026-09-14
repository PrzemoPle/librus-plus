import SwiftUI

enum MainTab: Hashable {
    case dashboard, grades, timetable, attendance, more
}

struct MainTabView: View {
    // NOTE: this view's body must NOT read `repo` — otherwise every background
    // `refreshCore()` (which mutates the repo) re-renders the whole TabView and
    // resets each tab's NavigationStack, kicking the user out of any detail view.
    // Badge counts are read inside the individual tab structs instead.
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            DashboardTab()
                .tabItem { Label("Pulpit", systemImage: "house.fill") }
                .tag(MainTab.dashboard)

            GradesTab()
                .tabItem { Label("Oceny", systemImage: "checkmark.seal.fill") }
                .tag(MainTab.grades)

            TimetableTab()
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(MainTab.timetable)

            AttendanceTab()
                .tabItem { Label("Frekwencja", systemImage: "person.crop.circle.badge.checkmark") }
                .tag(MainTab.attendance)

            MoreTab()
                .tabItem { Label("Więcej", systemImage: "ellipsis.circle.fill") }
                .tag(MainTab.more)
        }
        .minimizingTabBar()
    }
}

private struct DashboardTab: View {
    var body: some View { NavigationStack { DashboardView() } }
}

private struct GradesTab: View {
    @Environment(DataRepository.self) private var repo
    var body: some View {
        NavigationStack { GradesView() }
            .badge(repo.unseenGradeCount)
    }
}

private struct TimetableTab: View {
    var body: some View { NavigationStack { TimetableView() } }
}

private struct AttendanceTab: View {
    var body: some View { NavigationStack { AttendanceView() } }
}

private struct MoreTab: View {
    @Environment(DataRepository.self) private var repo
    var body: some View {
        NavigationStack { MoreView() }
            .badge(repo.unreadAnnouncementCount + repo.unreadMessageCount)
    }
}

struct MoreView: View {
    @Environment(DataRepository.self) private var repo

    var body: some View {
        List {
            Section {
                row("Ogłoszenia", "megaphone.fill", .orange, badge: repo.unreadAnnouncementCount) {
                    AnnouncementsView()
                }
                row("Terminarz", "calendar.badge.clock", .red) {
                    EventsView()
                }
                row("Uwagi", "exclamationmark.bubble.fill", .purple) {
                    NotesView()
                }
                row("Wiadomości", "envelope.fill", .blue, badge: repo.unreadMessageCount) {
                    MessagesView()
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
