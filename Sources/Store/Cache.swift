import Foundation

/// Tiny JSON-file cache under Application Support, so the app opens with the last
/// known data and works offline.
///
/// The snapshot holds personal data (grades, message senders/subjects, the
/// student's name), so every file is written with Data Protection. The level is
/// `completeUntilFirstUserAuthentication` — encrypted at rest, but still readable
/// by the background-refresh task after the first unlock following a reboot,
/// matching the keychain's `AfterFirstUnlock` accessibility.
enum Cache {
    private static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    private static var dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("MojLibrusCache", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true,
            attributes: [.protectionKey: protection]
        )
        // Also covers a directory left over from an older build without protection.
        try? FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: url.path)
        return url
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func save<T: Encodable>(_ value: T, as name: String) {
        guard let data = try? encoder.encode(value) else { return }
        let url = dir.appendingPathComponent("\(name).json")
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // `.atomic` writes via a temp file + rename, which can drop the protection
        // class on some OS versions — pin it explicitly afterwards.
        try? FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: url.path)
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let url = dir.appendingPathComponent("\(name).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    static func clearAll() {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Turns an account login into something safe to embed in a cache file name.
    static func safeName(_ raw: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")
        let cleaned = String(raw.map { allowed.contains($0) ? $0 : "_" })
        return cleaned.isEmpty ? "default" : cleaned
    }
}
