import Foundation
import UserNotifications

enum NotificationManager {
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    /// `student` — the child's name, shown as the subtitle when several are linked.
    static func notifyNewGrades(_ grades: [GradeItem], student: String? = nil) async {
        guard !grades.isEmpty, await isAuthorized() else { return }

        let content = UNMutableNotificationContent()
        if let student { content.subtitle = student }
        if grades.count == 1, let g = grades.first {
            content.title = "Nowa ocena: \(g.raw)"
            content.body = "\(g.subjectName)\(g.categoryName.isEmpty ? "" : " — \(g.categoryName)")"
        } else {
            content.title = "Nowe oceny (\(grades.count))"
            content.body = grades.prefix(5).map { "\($0.raw) \($0.subjectName)" }.joined(separator: ", ")
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "grades-\(UUID().uuidString)", content: content, trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func notifyTimetableChanges(_ lines: [String], student: String? = nil) async {
        guard !lines.isEmpty, await isAuthorized() else { return }
        let content = UNMutableNotificationContent()
        if let student { content.subtitle = student }
        content.title = lines.count == 1 ? "Zmiana w planie lekcji"
                                         : "Zmiany w planie lekcji (\(lines.count))"
        content.body = lines.prefix(4).joined(separator: "\n")
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "timetable-\(UUID().uuidString)", content: content, trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func notifyNewMessages(_ messages: [MessageItem], student: String? = nil) async {
        guard !messages.isEmpty, await isAuthorized() else { return }
        let content = UNMutableNotificationContent()
        if let student { content.subtitle = student }
        if messages.count == 1, let m = messages.first {
            content.title = "Nowa wiadomość"
            content.body = "\(m.correspondent): \(m.subject.isEmpty ? "(bez tematu)" : m.subject)"
        } else {
            content.title = "Nowe wiadomości (\(messages.count))"
            content.body = messages.prefix(5).map(\.correspondent).joined(separator: ", ")
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "messages-\(UUID().uuidString)", content: content, trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    enum TestOutcome {
        /// Handed to the system — it should appear in a couple of seconds.
        case scheduled
        /// Notifications are turned off for the app (or the OS refused the prompt).
        case denied
        /// The system rejected the request itself (rare — e.g. sandboxed container).
        case failed(String)
    }

    /// Fires a local notification a few seconds out, requesting permission first if
    /// it was never asked. Returns what actually happened so the UI can explain it
    /// (in a LiveContainer / sideload, notifications often don't work at all).
    static func sendTestNotification() async -> TestOutcome {
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            status = granted ? .authorized : .denied
        }
        guard status == .authorized || status == .provisional else { return .denied }

        let content = UNMutableNotificationContent()
        content.title = "Librus Plus"
        content.body = "Powiadomienia działają. Tak wyglądałaby informacja o nowej ocenie."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "test-\(UUID().uuidString)", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        )
        do {
            try await center.add(request)
            return .scheduled
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
