import Foundation

/// Data shared between the app and the widget extension via an App Group.
///
/// SideStore may rewrite the App Group identifier at sign time, so we can't fully
/// rely on the one declared in the entitlements file. We try that one first, then
/// any groups listed in the embedded provisioning profile, and use the first that
/// actually has a container. Degrades to a no-op when none is available.
enum SharedStore {
    static let declaredGroup = "group.pl.plewinscy.dzienniczek"
    private static let timetableKey = "widget.timetable.v1"

    private static let resolvedGroup: String? = {
        let fm = FileManager.default
        var candidates = [declaredGroup]
        candidates.append(contentsOf: provisionedAppGroups())
        for group in candidates where fm.containerURL(forSecurityApplicationGroupIdentifier: group) != nil {
            return group
        }
        return nil
    }()

    private static var defaults: UserDefaults? {
        resolvedGroup.flatMap { UserDefaults(suiteName: $0) }
    }

    /// App groups declared in this bundle's `embedded.mobileprovision`.
    private static func provisionedAppGroups() -> [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let raw = try? Data(contentsOf: url),
              let text = String(data: raw, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>") else { return [] }
        let plistText = String(text[start.lowerBound..<end.upperBound])
        guard let plistData = plistText.data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any] else { return [] }
        if let groups = entitlements["com.apple.security.application-groups"] as? [String] { return groups }
        return []
    }

    struct WidgetTimetable: Codable {
        struct Lesson: Codable, Identifiable, Hashable {
            var id: String
            var lessonNo: Int
            var start: String
            var end: String
            var subject: String
            var room: String?
            var isCancelled: Bool
            var isSubstitution: Bool
            var roomChanged: Bool
            var note: String?
        }
        struct Day: Codable, Identifiable, Hashable {
            var id: Date { date }
            var date: Date
            var lessons: [Lesson]
        }
        var days: [Day]
        var updated: Date
        /// First name of the child the timetable belongs to (nil on old payloads).
        var student: String?
    }

    static func publishTimetable(_ days: [WidgetTimetable.Day], student: String? = nil) {
        guard let defaults else { return }
        let payload = WidgetTimetable(days: days, updated: Date(), student: student)
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: timetableKey)
        }
    }

    static func loadTimetable() -> WidgetTimetable? {
        guard let data = defaults?.data(forKey: timetableKey) else { return nil }
        return try? JSONDecoder().decode(WidgetTimetable.self, from: data)
    }

    static func clear() {
        defaults?.removeObject(forKey: timetableKey)
    }

    /// Human-readable state for the diagnostics / settings screen.
    static var status: String {
        guard let g = resolvedGroup else { return "niedostępna (App Group nie działa)" }
        let has = loadTimetable() != nil
        return "OK: \(g)\(has ? "" : " (jeszcze bez danych)")"
    }
}
