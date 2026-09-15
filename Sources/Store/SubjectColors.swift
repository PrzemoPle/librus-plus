import SwiftUI
import Observation

/// The colours a subject can be tagged with. System colours, so they adapt to
/// light and dark mode on their own.
enum SubjectPalette: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .red: return "Czerwony"
        case .orange: return "Pomarańczowy"
        case .yellow: return "Żółty"
        case .green: return "Zielony"
        case .mint: return "Miętowy"
        case .teal: return "Morski"
        case .cyan: return "Błękitny"
        case .blue: return "Niebieski"
        case .indigo: return "Indygo"
        case .purple: return "Fioletowy"
        case .pink: return "Różowy"
        case .brown: return "Brązowy"
        }
    }

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        }
    }
}

/// Optional per-subject colours. Nothing is coloured until the user assigns a
/// colour in Settings, so the default look stays exactly as it was. Keyed by the
/// subject's name (case-insensitive), so "Matematyka" in the timetable and in
/// the grades share one colour — and so do both children's subjects.
@MainActor
@Observable
final class SubjectColors {
    static let shared = SubjectColors()

    private static let storageKey = "subjectColors.v1"

    private(set) var assignments: [String: SubjectPalette] = [:]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
        assignments = stored.reduce(into: [:]) { acc, pair in
            if let palette = SubjectPalette(rawValue: pair.value) { acc[pair.key] = palette }
        }
    }

    var isEmpty: Bool { assignments.isEmpty }

    func palette(for subject: String) -> SubjectPalette? {
        assignments[Self.key(subject)]
    }

    func color(for subject: String) -> Color? {
        palette(for: subject)?.color
    }

    /// nil removes the colour.
    func set(_ palette: SubjectPalette?, for subject: String) {
        let key = Self.key(subject)
        guard !key.isEmpty else { return }
        var next = assignments
        next[key] = palette
        assignments = next
        save()
    }

    func clearAll() {
        assignments = [:]
        save()
    }

    private func save() {
        let raw = assignments.reduce(into: [String: String]()) { $0[$1.key] = $1.value.rawValue }
        defaults.set(raw, forKey: Self.storageKey)
    }

    static func key(_ subject: String) -> String {
        subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
