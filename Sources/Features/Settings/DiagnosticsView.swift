import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DiagnosticsView: View {
    @Environment(AppState.self) private var app

    @State private var results: [DiagnosticResult] = []
    @State private var running = false
    @State private var copied = false
    @State private var dumpingTimetable = false
    @State private var timetableCopied = false
    @State private var dumpingInbox = false
    @State private var inboxCopied = false

    var body: some View {
        List {
            Section {
                Button {
                    Task { await runChecks() }
                } label: {
                    HStack {
                        Label("Uruchom test połączenia", systemImage: "stethoscope")
                        Spacer()
                        if running { ProgressView() }
                    }
                }
                .disabled(running)
            } footer: {
                Text("Sprawdza każdy endpoint Librusa osobno. Skopiuj raport i wyślij go, jeśli coś nie działa.")
            }

            Section {
                Button {
                    Task { await dumpTimetable() }
                } label: {
                    HStack {
                        Label(timetableCopied ? "Skopiowano" : "Kopiuj surowy JSON planu lekcji",
                              systemImage: timetableCopied ? "checkmark" : "doc.on.doc")
                        Spacer()
                        if dumpingTimetable { ProgressView() }
                    }
                }
                .disabled(dumpingTimetable)
            } footer: {
                Text("Pełna, niesformatowana odpowiedź Librusa dla ubiegłego, tego i przyszłego tygodnia — przydatne przy zgłaszaniu błędów planu lekcji (np. przeniesień). Zawiera imiona i nazwiska nauczycieli.")
            }

            Section {
                Button {
                    Task { await dumpInbox() }
                } label: {
                    HStack {
                        Label(inboxCopied ? "Skopiowano" : "Kopiuj surowy HTML skrzynki",
                              systemImage: inboxCopied ? "checkmark" : "doc.on.doc")
                        Spacer()
                        if dumpingInbox { ProgressView() }
                    }
                }
                .disabled(dumpingInbox)
            } footer: {
                Text("Strona skrzynki odbiorczej dokładnie tak, jak wysyła ją Synergia — przydatne, gdy jakaś wiadomość ma złą datę, nadawcę albo temat. Zawiera nazwiska nadawców i tematy wiadomości.")
            }

            if !results.isEmpty {
                Section {
                    ForEach(results) { r in
                        HStack(alignment: .top, spacing: Theme.Space.md) {
                            Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .font(.body)
                                .foregroundStyle(r.ok ? Color.positive : Color.negative)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(.callout.weight(.medium))
                                Text(r.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                } header: {
                    let bad = results.filter { !$0.ok }.count
                    Text(bad == 0 ? "Wszystko OK (\(results.count))" : "\(bad) z \(results.count) nie działa")
                        .textCase(nil)
                }

                Section {
                    Button {
                        // The report can contain teacher names and a message
                        // snippet — keep it on this device (no Universal Clipboard)
                        // and let it expire so it doesn't linger.
                        UIPasteboard.general.setItems(
                            [[UTType.utf8PlainText.identifier: Diagnostics.report(results)]],
                            options: [.localOnly: true,
                                      .expirationDate: Date().addingTimeInterval(10 * 60)]
                        )
                        Haptics.success()
                        withAnimation(Theme.Motion.quick) { copied = true }
                    } label: {
                        Label(copied ? "Skopiowano" : "Kopiuj raport", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground.ignoresSafeArea())
        .navigationTitle("Diagnostyka")
        .navigationBarTitleDisplayMode(.inline)
        .animation(Theme.Motion.standard, value: results.count)
    }

    private func runChecks() async {
        Haptics.tap()
        running = true
        copied = false
        results = []
        defer { running = false }
        results = await Diagnostics(session: app.session, account: app.repository?.account.login).run()
    }

    private func dumpTimetable() async {
        Haptics.tap()
        dumpingTimetable = true
        timetableCopied = false
        defer { dumpingTimetable = false }
        let json = await Diagnostics(session: app.session, account: app.repository?.account.login).rawTimetableJSON()
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: json]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(10 * 60)]
        )
        Haptics.success()
        withAnimation(Theme.Motion.quick) { timetableCopied = true }
    }

    private func dumpInbox() async {
        Haptics.tap()
        dumpingInbox = true
        inboxCopied = false
        defer { dumpingInbox = false }
        let html = await Diagnostics(session: app.session, account: app.repository?.account.login).rawInboxHTML()
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: html]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(10 * 60)]
        )
        Haptics.success()
        withAnimation(Theme.Motion.quick) { inboxCopied = true }
    }
}
