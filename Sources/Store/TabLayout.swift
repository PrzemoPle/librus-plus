import SwiftUI
import Observation

/// Every screen that can sit in the tab bar. Pulpit is always first and Więcej
/// always last; the three slots in between are the user's to arrange.
enum MainTab: String, CaseIterable, Identifiable, Codable {
    case dashboard, grades, timetable, attendance, announcements, events, notes, messages, more

    var id: String { rawValue }

    /// Short label under the tab icon.
    var title: String {
        switch self {
        case .dashboard: return "Pulpit"
        case .grades: return "Oceny"
        case .timetable: return "Plan"
        case .attendance: return "Frekwencja"
        case .announcements: return "Ogłoszenia"
        case .events: return "Terminarz"
        case .notes: return "Uwagi"
        case .messages: return "Wiadomości"
        case .more: return "Więcej"
        }
    }

    /// Full name for lists and settings.
    var longTitle: String {
        switch self {
        case .timetable: return "Plan lekcji"
        default: return title
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "house.fill"
        case .grades: return "checkmark.seal.fill"
        case .timetable: return "calendar"
        case .attendance: return "person.crop.circle.badge.checkmark"
        case .announcements: return "megaphone.fill"
        case .events: return "calendar.badge.clock"
        case .notes: return "exclamationmark.bubble.fill"
        case .messages: return "envelope.fill"
        case .more: return "ellipsis.circle.fill"
        }
    }

    /// Icon tile colour on the Więcej list.
    var tint: Color {
        switch self {
        case .dashboard: return .accentColor
        case .grades: return .green
        case .timetable: return .teal
        case .attendance: return .indigo
        case .announcements: return .orange
        case .events: return .red
        case .notes: return .purple
        case .messages: return .blue
        case .more: return .gray
        }
    }

    /// Screens the user may place in the bar, in the order the Więcej list shows them.
    static let placeable: [MainTab] = [.grades, .timetable, .attendance, .announcements, .events, .notes, .messages]
}

/// Which three screens sit between Pulpit and Więcej, and in what order.
/// Stored per phone; the default matches the original app.
@MainActor
@Observable
final class TabLayout {
    static let shared = TabLayout()

    static let slots = 3
    static let defaultBar: [MainTab] = [.grades, .timetable, .attendance]
    private static let storageKey = "tabLayout.v1"

    private(set) var bar: [MainTab]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = (defaults.array(forKey: Self.storageKey) as? [String] ?? [])
            .compactMap(MainTab.init(rawValue:))
        bar = Self.validated(stored) ?? Self.defaultBar
    }

    /// Screens that stay on the Więcej list.
    var inMore: [MainTab] {
        MainTab.placeable.filter { !bar.contains($0) }
    }

    var isDefault: Bool { bar == Self.defaultBar }

    func contains(_ tab: MainTab) -> Bool {
        tab == .dashboard || tab == .more || bar.contains(tab)
    }

    /// Puts `tab` into `slot`. If it already occupies another slot the two swap,
    /// so the bar never shows the same screen twice.
    func set(slot: Int, to tab: MainTab) {
        guard bar.indices.contains(slot), MainTab.placeable.contains(tab) else { return }
        var next = bar
        if let other = next.firstIndex(of: tab), other != slot {
            next.swapAt(other, slot)
        } else {
            next[slot] = tab
        }
        bar = next
        save()
    }

    func reset() {
        bar = Self.defaultBar
        save()
    }

    private func save() {
        defaults.set(bar.map(\.rawValue), forKey: Self.storageKey)
    }

    /// Exactly `slots` distinct placeable screens, or nil.
    static func validated(_ tabs: [MainTab]) -> [MainTab]? {
        guard tabs.count == slots, Set(tabs).count == slots,
              tabs.allSatisfy({ MainTab.placeable.contains($0) }) else { return nil }
        return tabs
    }
}
