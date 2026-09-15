import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(DataRepository.self) private var repo

    @State private var showLogoutConfirm = false
    @State private var confirmCalendarRemoval = false
    @State private var notice: Notice?
    @State private var isSyncingCalendar = false
    @AppStorage(BackgroundRefresh.Keys.grades) private var notifyNewGrades = false
    @AppStorage(BackgroundRefresh.Keys.timetable) private var notifyTimetable = false
    @AppStorage(BackgroundRefresh.Keys.messages) private var notifyMessages = false
    @AppStorage(CalendarSync.enabledKey) private var syncCalendar = false
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    /// One alert slot shared by every informational message on this screen —
    /// stacking several `.alert`s on one view fights over the presentation.
    private struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// Who to write to about the app — also the feedback address for TestFlight.
    static let contactEmail = "przemyslaw@plewinski.pl"

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        List {
            Section("Konto") {
                LabeledContent("Uczeń", value: repo.studentName.isEmpty ? "—" : repo.studentName)
                if let className = repo.schoolYear.className {
                    LabeledContent("Klasa", value: className)
                }
                if let tutor = repo.schoolYear.tutor {
                    LabeledContent("Wychowawca", value: tutor)
                }
                if let login = app.portalLogin {
                    LabeledContent("Konto LIBRUS", value: login)
                }
                LabeledContent("Bieżący semestr", value: "\(repo.currentSemester)")
                if let sync = repo.lastSync {
                    LabeledContent("Ostatnia synchronizacja", value: sync.formattedPL("d MMM yyyy, HH:mm"))
                }
            }

            if app.accounts.count > 1 {
                Section {
                    ForEach(app.accounts) { account in
                        Button {
                            Haptics.selection()
                            Task { await app.switchAccount(to: account.login) }
                        } label: {
                            HStack {
                                Text(account.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if account.login == repo.account.login {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .disabled(app.isSwitchingAccount)
                    }
                } header: {
                    Text("Dzieci")
                } footer: {
                    Text("Konta Synergia połączone z tym Kontem LIBRUS. Dziecko przełączysz też menu w lewym górnym rogu każdego ekranu.")
                }
            }

            Section {
                Picker("Motyw", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { Haptics.selection() }
                NavigationLink {
                    SubjectColorsView()
                } label: {
                    Label("Kolory przedmiotów", systemImage: "paintpalette")
                }
            } header: {
                Text("Wygląd")
            } footer: {
                Text("Kolory przedmiotów są opcjonalne — bez nich aplikacja wygląda jak dotąd.")
            }

            Section {
                Button {
                    Haptics.tap()
                    Task {
                        await repo.refreshCore()
                        await repo.loadTimetable(weekStart: LibrusDate.weekStart())
                    }
                } label: {
                    Label("Odśwież wszystko", systemImage: "arrow.clockwise")
                }
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Label("Diagnostyka połączenia", systemImage: "stethoscope")
                }
            }

            Section {
                Toggle(isOn: $notifyNewGrades) {
                    Label("Nowe oceny", systemImage: "checkmark.seal")
                }
                Toggle(isOn: $notifyTimetable) {
                    Label("Zmiany w planie lekcji", systemImage: "calendar.badge.exclamationmark")
                }
                Toggle(isOn: $notifyMessages) {
                    Label("Nowe wiadomości", systemImage: "envelope.badge")
                }
                if notifyNewGrades || notifyTimetable || notifyMessages {
                    Button {
                        Task {
                            let text: String
                            switch await NotificationManager.sendTestNotification() {
                            case .scheduled:
                                text = "Wysłane. Powiadomienie powinno pojawić się za chwilę. "
                                    + "Jeśli nie przychodzi — sprawdź Ustawienia iOS → Powiadomienia → Dzienniczek."
                            case .denied:
                                text = "Powiadomienia są wyłączone dla aplikacji. "
                                    + "Włącz je w Ustawieniach iOS → Powiadomienia → Dzienniczek."
                            case .failed(let detail):
                                text = "System odrzucił powiadomienie: \(detail)"
                            }
                            notice = Notice(title: "Powiadomienie testowe", message: text)
                        }
                    } label: {
                        Label("Wyślij powiadomienie testowe", systemImage: "paperplane")
                    }
                }
            } header: {
                Text("Powiadomienia")
            } footer: {
                Text("Eksperymentalne. iOS sam decyduje, kiedy odświeżyć aplikację w tle — dla apek sideloadowanych bywa to rzadko. Plakietki „nowe” w aplikacji działają zawsze.")
            }

            Section {
                Toggle(isOn: $syncCalendar) {
                    Label("Dodawaj wpisy do Kalendarza", systemImage: "calendar.badge.plus")
                }
                if syncCalendar {
                    Button {
                        Task { await syncCalendarNow() }
                    } label: {
                        HStack {
                            Label("Synchronizuj teraz", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if isSyncingCalendar { ProgressView() }
                        }
                    }
                    .disabled(isSyncingCalendar)

                    Button(role: .destructive) {
                        confirmCalendarRemoval = true
                    } label: {
                        Label("Usuń kalendarz „\(CalendarSync.calendarTitle)”", systemImage: "trash")
                    }
                }
            } header: {
                Text("Kalendarz")
            } footer: {
                Text("Wpisy z terminarza trafiają do osobnego kalendarza „\(CalendarSync.calendarTitle)” i odświeżają się przy każdej synchronizacji — zmieniony wpis jest aktualizowany, usunięty znika. Twoje własne wydarzenia nie są odczytywane ani zmieniane.")
            }

            Section {
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Label("Wyloguj się", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } footer: {
                Text("Wylogowanie usuwa dane logowania z Keychaina oraz lokalną pamięć podręczną.")
            }

            Section("O aplikacji") {
                LabeledContent("Wersja", value: version)
                Link(destination: URL(string: "mailto:\(Self.contactEmail)")!) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kontakt")
                            Text(Self.contactEmail).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "envelope")
                    }
                }
                Link(destination: URL(string: "https://github.com/PrzemoPle/librus-plus/issues")!) {
                    Label("Zgłoś problem", systemImage: "ladybug")
                }
                Link(destination: URL(string: "https://github.com/PrzemoPle/librus-plus")!) {
                    Label("Kod źródłowy (GitHub)", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Text("""
                Nieoficjalny klient Librus Synergia — bez związku z firmą Librus. Do użytku \
                edukacyjnego / własnego, na własną odpowiedzialność. Łączy się wyłącznie z \
                *.librus.pl; dane logowania trzymane są tylko w Keychainie tego urządzenia. \
                Brak analityki i serwera pośredniczącego.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground.ignoresSafeArea())
        .navigationTitle("Ustawienia")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.accentColor)
        .onChange(of: notifyNewGrades) { _, on in handleToggle(on) { notifyNewGrades = false } }
        .onChange(of: notifyTimetable) { _, on in handleToggle(on) { notifyTimetable = false } }
        .onChange(of: notifyMessages) { _, on in handleToggle(on) { notifyMessages = false } }
        .onChange(of: syncCalendar) { _, on in handleCalendarToggle(on) }
        .confirmationDialog("Wylogować się?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Wyloguj", role: .destructive) {
                Task { await app.logOut() }
            }
            Button("Anuluj", role: .cancel) {}
        }
        .confirmationDialog(
            "Usunąć kalendarz „\(CalendarSync.calendarTitle)”?",
            isPresented: $confirmCalendarRemoval, titleVisibility: .visible
        ) {
            Button("Usuń kalendarz", role: .destructive) {
                CalendarSync.removeMirrorCalendar()
                syncCalendar = false
                notice = Notice(title: "Kalendarz usunięty",
                                message: "Wpisy z terminarza zniknęły z aplikacji Kalendarz.")
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Zniknie razem ze wszystkimi wpisami, które tam dodaliśmy. Twoje własne wydarzenia zostaną nietknięte.")
        }
        .alert(notice?.title ?? "", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        ), presenting: notice) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0.message) }
    }

    /// Turning the mirror on asks for Calendar access and does a first pass right
    /// away, so the user sees the entries land instead of waiting for a refresh.
    private func handleCalendarToggle(_ turnedOn: Bool) {
        Haptics.selection()
        guard turnedOn else { return }
        Task {
            guard await CalendarSync.requestAccess() else {
                Haptics.warning()
                syncCalendar = false
                notice = Notice(
                    title: "Brak dostępu do Kalendarza",
                    message: "Włącz go w Ustawieniach iOS → Prywatność i bezpieczeństwo → Kalendarze → Dzienniczek."
                )
                return
            }
            await syncCalendarNow()
        }
    }

    private func syncCalendarNow() async {
        isSyncingCalendar = true
        defer { isSyncingCalendar = false }
        guard let result = await repo.syncCalendarIfEnabled() else { return }

        switch result {
        case .synced(let added, let updated, let removed):
            Haptics.success()
            notice = Notice(
                title: "Kalendarz zsynchronizowany",
                message: added + updated + removed == 0
                    ? "Wszystko było już aktualne."
                    : "Dodane: \(added), zaktualizowane: \(updated), usunięte: \(removed)."
            )
        case .denied:
            Haptics.warning()
            notice = Notice(
                title: "Brak dostępu do Kalendarza",
                message: "Włącz go w Ustawieniach iOS → Prywatność i bezpieczeństwo → Kalendarze → Dzienniczek."
            )
        case .failed(let detail):
            Haptics.warning()
            notice = Notice(title: "Nie udało się zsynchronizować", message: detail)
        }
    }

    /// Shared handler for the three notification toggles: ask for permission when
    /// switching one on (revert via `revert` if denied), (re)schedule or cancel the
    /// background task based on whether any are still on.
    private func handleToggle(_ turnedOn: Bool, revert: @escaping () -> Void) {
        Haptics.selection()
        Task {
            if turnedOn {
                let granted = await NotificationManager.requestAuthorization()
                if granted {
                    BackgroundRefresh.scheduleIfEnabled()
                } else {
                    Haptics.warning()
                    revert()
                }
            } else if !BackgroundRefresh.anyEnabled {
                BackgroundRefresh.cancel()
            }
        }
    }
}
