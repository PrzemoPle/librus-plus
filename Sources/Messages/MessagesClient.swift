import Foundation

/// Read + reply access to the Librus message inbox.
///
/// This school's Synergia serves the **legacy** message UI inline at
/// `synergia.librus.pl/wiadomosci` (HTML 4.01 + jQuery 1.8, `rowCollection.js`) —
/// not the standalone `wiadomosci.librus.pl` domain and not a JSON API. So we
/// establish the Synergia web session and scrape the HTML directly:
///   1. POST `2.0/AutoLoginToken` (bearer)                    -> one-time token
///   2. GET  `synergia.librus.pl/loguj/token/<T>/przenies/…`  -> sets `DZIENNIKSID`
///   3. GET  `synergia.librus.pl/wiadomosci` (+ `/1/5/<id>/f0`) and parse the table.
actor MessagesClient {
    private let session: LibrusSession
    /// Synergia login of the child whose inbox this is; nil = the selected one.
    private let account: String?
    private let http: URLSession
    private var sessionEstablishedAt: Date?

    /// Human-readable trace of the last session attempt — surfaced in errors so a
    /// remote Diagnostics report shows where it broke.
    private(set) var lastTrail = ""

    init(session: LibrusSession, account: String? = nil) {
        self.session = session
        self.account = account
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": Librus.browserUserAgent]
        self.http = URLSession(configuration: config)
    }

    func invalidateSession() { sessionEstablishedAt = nil }

    // MARK: - Public API

    /// Librus folder ids: 5 = odebrane, 6 = wysłane.
    enum Folder: Int, Sendable {
        case received = 5
        case sent = 6
    }

    func inbox() async throws -> [MessageItem] { try await messages(in: .received) }

    /// The inbox page exactly as Synergia serves it — for the diagnostics screen,
    /// so a parsing bug can be reproduced from a real row instead of guessed at.
    func rawInboxHTML() async throws -> String {
        try await ensureSynergiaSession()
        let (data, _) = try await get("https://synergia.librus.pl/wiadomosci/\(Folder.received.rawValue)")
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    func messages(in folder: Folder) async throws -> [MessageItem] {
        try await ensureSynergiaSession()
        let (data, resp) = try await get("https://synergia.librus.pl/wiadomosci/\(folder.rawValue)")
        let html = String(data: data, encoding: .utf8) ?? ""
        let finalURL = resp?.url?.absoluteString ?? ""

        if finalURL.contains("/loguj") || html.contains(">Brak dostępu<") || html.contains("stop.png") {
            throw APIError.messageBridgeFailed("Synergia odmówiła dostępu do skrzynki wiadomości · "
                + lastTrail + " · " + snippet(html))
        }

        let items = Self.parseMessageList(html)
        if items.isEmpty {
            if html.range(of: #"[Bb]rak wiadomości|nie posiadasz żadnych|Wiadomości: 0"#,
                          options: .regularExpression) != nil { return [] }
            throw APIError.messageBridgeFailed("nie rozpoznałem listy wiadomości · "
                + Self.tableRegion(html))
        }
        return items
    }

    struct MessageContent: Sendable {
        var text: String
        var senderLoginId: String?
        /// Sent messages: who received it and when they read it.
        var receipts: [Receipt] = []

        struct Receipt: Identifiable, Hashable, Sendable {
            var id: String { name }
            let name: String
            /// nil = still unread.
            let readAt: String?
        }
    }

    func content(messageId: Int, folder: Folder = .received) async throws -> MessageContent {
        try await ensureSynergiaSession()
        let (data, _) = try await get(
            "https://synergia.librus.pl/wiadomosci/1/\(folder.rawValue)/\(messageId)/f0")
        let html = String(data: data, encoding: .utf8) ?? ""

        // szkolny reads `.container-message-content` — grab it with nesting honoured.
        let bodyHTML = Self.balancedDiv(after: "container-message-content", in: html)
            ?? Self.firstGroup(#"<td[^>]*class=["'][^"']*message[^"']*["'][^>]*>(.*?)</td>"#, html)
            ?? Self.tableRegion(html)

        let senderId = HTTP.firstMatch(#"/wiadomosci/2/6/(\d+)"#, in: html)
        return MessageContent(text: cleanup(bodyHTML),
                              senderLoginId: senderId,
                              receipts: folder == .sent ? Self.parseReceipts(html) : [])
    }

    /// Sent-message read table: rows of `odbiorca | data odczytania` where "NIE"
    /// means not read yet.
    private static func parseReceipts(_ html: String) -> [MessageContent.Receipt] {
        var out: [MessageContent.Receipt] = []
        for m in HTTP.allMatches(#"<tr[^>]*>(.*?)</tr>"#, in: html) where m.count > 1 {
            let cells = HTTP.allMatches(#"<td[^>]*>(.*?)</td>"#, in: m[1])
                .compactMap { $0.count > 1 ? stripHTML($0[1]) : nil }
            guard cells.count >= 2 else { continue }
            let name = cells[0]
            let status = cells[1]
            guard name.contains(" "), name.count > 4 else { continue }
            let isDate = status.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil
            let notRead = status.uppercased() == "NIE"
            guard isDate || notRead else { continue }
            out.append(.init(name: name, readAt: isDate ? status : nil))
        }
        return out
    }

    // MARK: - Composing
    //
    // Verified against a saved DOM + network capture (2026-09-03):
    //   1. GET  /wiadomosci/2/5  -> compose form, `requestkey` CSRF, `adresat` radios
    //   2. POST /getRecipients   -> HTML fragment of `DoKogo[]` checkboxes for a category
    //   3. POST <form action>    -> requestkey + carried hidden fields + adresat +
    //                               DoKogo[] / DoKogo_hid[] + temat + tresc + wyslij

    struct Recipient: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let group: String?
    }

    struct RecipientList: Sendable {
        var people: [Recipient]
        var field: String
        var allowsMultiple: Bool
    }

    struct RecipientCategory: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let classID: String?
    }

    // Regexes kept as named constants so the parsing code stays readable.
    private static let REGEX_HIDDEN_INPUT = #"<input([^>]*type=["']?[Hh][Ii][Dd][Dd][Ee][Nn]["']?[^>]*)>"#
    private static let REGEX_NAME_ATTR = #"name=["']([^"']+)["']"#
    private static let REGEX_VALUE_ATTR = #"value=["']([^"']*)["']"#
    private static let REGEX_TYPE_ATTR = #"type=["']([^"']+)["']"#
    private static let REGEX_CSRF_JS = #"csrfTokenValue\s*=\s*["']([^"']+)["']"#
    private static let REGEX_FORM_ACTION_NAMED = #"<form[^>]*\bname=["']formWiadomosci["'][^>]*\baction=["']([^"']+)["']"#
    private static let REGEX_FORM_ACTION_ANY = #"<form[^>]*\baction=["']([^"']*wiadomosci[^"']*)["']"#
    private static let REGEX_FORM_OPEN = #"<form([^>]*)>"#
    private static let REGEX_INPUT_OPEN = #"<input([^>]*)>"#
    private static let REGEX_TEXTAREA_OPEN = #"<textarea([^>]*)>"#
    private static let REGEX_ADRESAT_RADIO =
        #"<input[^>]*name=["']adresat["'][^>]*value=["']([^"']+)["'][^>]*onclick=["']([^"']*)["'][^>]*>[\s\S]{0,300}?<label[^>]*>(.*?)</label>"#
    private static let REGEX_DIGITS_2PLUS = #"(\d{2,})"#
    private static let REGEX_LINE_ROW = #"<tr[^>]*class=["'][^"']*line[01][^"']*["'][^>]*>(.*?)</tr>"#
    private static let REGEX_DOKOGO_INPUT = #"(<input[^>]*name=["']DoKogo\[\]["'][^>]*>)"#
    private static let REGEX_SPAN_TEXT = #"<span[^>]*>(.*?)</span>"#
    private static let REGEX_LABEL_TEXT = #"<label[^>]*>(.*?)</label>"#
    private static let REGEX_IMG_TITLE = #"<img[^>]*title=["']([^"']+)["']"#
    private static let REGEX_SEND_OK = #"(?i)(została|zostały) wysłan|wiadomość (została )?wysłana"#
    private static let REGEX_SEND_ERROR =
        #"class=["'][^"']*(?:error|red|blad|komunikat|warning-box)[^"']*["'][^>]*>(.*?)</"#

    private static let composeURL = "https://synergia.librus.pl/wiadomosci/2/5"
    private static let carriedHiddenFields = [
        "requestkey", "filtrUzytkownikow", "idPojemnika", "Rodzaj",
        "poprzednia", "fileStorageIdentifier",
    ]

    private struct ComposeForm {
        let html: String
        let url: String
        let action: String
        var hidden: [String: String]
    }

    private func loadComposeForm() async throws -> ComposeForm {
        let (data, resp) = try await get(Self.composeURL)
        let html = String(data: data, encoding: .utf8) ?? ""
        let final = resp?.url?.absoluteString ?? Self.composeURL
        if final.contains("/loguj") || html.contains(">Brak dostepu<") || html.contains("stop.png") {
            throw APIError.messageBridgeFailed("brak dostepu do formularza wiadomosci - " + snippet(html))
        }
        var hidden: [String: String] = [:]
        for m in HTTP.allMatches(Self.REGEX_HIDDEN_INPUT, in: html) where m.count > 1 {
            guard let name = HTTP.firstMatch(Self.REGEX_NAME_ATTR, in: m[1]) else { continue }
            let value = HTTP.firstMatch(Self.REGEX_VALUE_ATTR, in: m[1]) ?? ""
            if hidden[name] == nil { hidden[name] = value }
        }
        if hidden["requestkey"] == nil,
           let csrf = HTTP.firstMatch(Self.REGEX_CSRF_JS, in: html) {
            hidden["requestkey"] = csrf
        }
        let action = HTTP.firstMatch(Self.REGEX_FORM_ACTION_NAMED, in: html)
            ?? HTTP.firstMatch(Self.REGEX_FORM_ACTION_ANY, in: html)
            ?? "/wiadomosci/2/5"
        return ComposeForm(html: html, url: final,
                           action: Self.absolute(action, base: resp?.url), hidden: hidden)
    }

    /// Step 1 -- recipient categories (the `adresat` radios).
    func recipientCategories() async throws -> [RecipientCategory] {
        try await ensureSynergiaSession()
        let form = try await loadComposeForm()
        let cats = Self.parseCategories(form.html)
        guard !cats.isEmpty else {
            throw APIError.messageBridgeFailed("brak kategorii odbiorcow - " + Self.formDump(form.html))
        }
        return cats
    }

    private static func parseCategories(_ html: String) -> [RecipientCategory] {
        var out: [RecipientCategory] = []
        var seen = Set<String>()
        for m in HTTP.allMatches(Self.REGEX_ADRESAT_RADIO, in: html) where m.count > 3 {
            let value = m[1]
            guard seen.insert(value).inserted else { continue }
            let nums = HTTP.allMatches(Self.REGEX_DIGITS_2PLUS, in: m[2]).compactMap { $0.count > 1 ? $0[1] : nil }
            let classID = nums.last.flatMap { $0 == "0" ? nil : $0 }
            out.append(RecipientCategory(id: value,
                                         name: stripHTML(m[3]).nonEmpty ?? value,
                                         classID: classID))
        }
        return out
    }

    /// Step 2 -- the people inside a category, via `POST /getRecipients`.
    func recipients(in category: RecipientCategory) async throws -> RecipientList {
        try await ensureSynergiaSession()
        let form = try await loadComposeForm()

        var body: [(String, String)] = [
            ("typAdresata", category.id),
            ("poprzednia", "5"),
            ("tabZaznaczonych", ""),
            ("czyWirtualneKlasy", "false"),
            ("idGrupy", "0"),
        ]
        if let classID = category.classID {
            body += [("klasa_rada_rodzicow", classID), ("klasa_opiekunowie", classID),
                     ("klasa_rodzice", classID)]
        }

        let (data, resp) = try await post("https://synergia.librus.pl/getRecipients",
                                          pairs: body,
                                          headers: ["requestkey": form.hidden["requestkey"] ?? "",
                                                    "X-Requested-With": "XMLHttpRequest",
                                                    "Referer": Self.composeURL])
        let html = String(data: data, encoding: .utf8) ?? ""
        guard let list = Self.parsePeople(html), !list.people.isEmpty else {
            throw APIError.messageBridgeFailed(
                "brak osob w kategorii [\(resp?.statusCode ?? 0)] - "
                    + Self.formDump(html) + " -- " + snippet(html, 260))
        }
        return list
    }

    private static func parsePeople(_ html: String) -> RecipientList? {
        var people: [Recipient] = []
        var seen = Set<String>()
        var multiple = true
        for m in HTTP.allMatches(Self.REGEX_LINE_ROW, in: html) where m.count > 1 {
            let row = m[1]
            guard let tag = HTTP.firstMatch(Self.REGEX_DOKOGO_INPUT, in: row),
                  let value = HTTP.firstMatch(Self.REGEX_VALUE_ATTR, in: tag),
                  !value.isEmpty, value != "0", seen.insert(value).inserted else { continue }
            let name = HTTP.firstMatch(Self.REGEX_SPAN_TEXT, in: row).flatMap { stripHTML($0).nonEmpty }
                ?? HTTP.firstMatch(Self.REGEX_LABEL_TEXT, in: row).flatMap { stripHTML($0).nonEmpty }
                ?? value
            let role = HTTP.firstMatch(Self.REGEX_IMG_TITLE, in: row).map(stripHTML)
            multiple = tag.range(of: "type=[\"']radio[\"']",
                                 options: [.regularExpression, .caseInsensitive]) == nil
            people.append(Recipient(id: value,
                                    name: role.map { "\(name) - \($0)" } ?? name,
                                    group: "DoKogo[]"))
        }
        guard !people.isEmpty else { return nil }
        return RecipientList(
            people: people.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            field: "DoKogo[]",
            allowsMultiple: multiple
        )
    }

    /// Step 3 -- send.
    @discardableResult
    func send(recipientLoginIds: [String], subject: String, body: String,
              recipientField: String? = nil,
              category: (field: String, id: String)? = nil) async throws -> Int {
        try await ensureSynergiaSession()
        let ids = recipientLoginIds.filter { !$0.isEmpty }
        guard !ids.isEmpty else { throw APIError.messageBridgeFailed("brak odbiorcy") }

        let form = try await loadComposeForm()
        let field = recipientField ?? "DoKogo[]"

        var pairs: [(String, String)] = []
        for key in Self.carriedHiddenFields {
            let fallback = (key == "Rodzaj") ? "0" : (key == "poprzednia" ? "5" : "")
            pairs.append((key, form.hidden[key] ?? fallback))
        }
        if let category { pairs.append((category.field, category.id)) }
        for id in ids {
            pairs.append((field, id))
            pairs.append(("DoKogo_hid[]", id))
        }
        pairs.append(("temat", subject))
        pairs.append(("tresc", body))
        pairs.append(("wyslij", "Wyslij"))

        let (respData, resp) = try await post(form.action, pairs: pairs,
                                              headers: ["Referer": form.url])
        let respHTML = String(data: respData, encoding: .utf8) ?? ""
        let finalURL = resp?.url?.absoluteString ?? ""

        if respHTML.range(of: Self.REGEX_SEND_OK, options: .regularExpression) != nil
            || finalURL.hasSuffix("/wiadomosci/5") || finalURL.hasSuffix("/wiadomosci/6") {
            return 0
        }
        let err = Self.firstGroup(Self.REGEX_SEND_ERROR, respHTML)
        throw APIError.messageBridgeFailed(
            err.flatMap { Self.stripHTML($0).nonEmpty }
                ?? "wysylka nie powiodla sie [\(resp?.statusCode ?? 0)] - " + snippet(respHTML, 300))
    }

    private static func absolute(_ path: String, base: URL?) -> String {
        if path.hasPrefix("http") { return path }
        return URL(string: path, relativeTo: base ?? URL(string: "https://synergia.librus.pl"))?
            .absoluteString ?? composeURL
    }

    private static func formDump(_ html: String) -> String {
        var out = ["\(html.count)B"]
        if let tag = HTTP.firstMatch(Self.REGEX_FORM_OPEN, in: html) {
            out.append("form{" + collapse(tag).prefix(90) + "}")
        }
        var inputs = Set<String>()
        for m in HTTP.allMatches(Self.REGEX_INPUT_OPEN, in: html) where m.count > 1 {
            guard let name = HTTP.firstMatch(Self.REGEX_NAME_ATTR, in: m[1]) else { continue }
            inputs.insert("\(name):\(HTTP.firstMatch(Self.REGEX_TYPE_ATTR, in: m[1]) ?? "?")")
        }
        out.append("inputs{" + inputs.sorted().prefix(24).joined(separator: " ") + "}")
        let areas = HTTP.allMatches(Self.REGEX_TEXTAREA_OPEN, in: html)
            .compactMap { $0.count > 1 ? HTTP.firstMatch(Self.REGEX_NAME_ATTR, in: $0[1]) : nil }
        if !areas.isEmpty { out.append("textarea{" + areas.joined(separator: " ") + "}") }
        return out.joined(separator: " - ")
    }

    private static func collapse(_ s: String) -> String {
        s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Deep diagnostic

    func probe() async -> String {
        do {
            invalidateSession()
            try await ensureSynergiaSession()
        } catch {
            return "sesja BŁĄD · \(lastTrail) · "
                + ((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
        var lines: [String] = ["sesja OK · \(lastTrail)", "cookies: " + cookieInventory()]
        for url in ["https://synergia.librus.pl/wiadomosci",
                    "https://synergia.librus.pl/wiadomosci/5",
                    "https://synergia.librus.pl/wiadomosci/1/5"] {
            guard let (d, r) = try? await get(url) else { lines.append("\(shortPath(url)): wyjątek"); continue }
            let h = String(data: d, encoding: .utf8) ?? ""
            let parsed = Self.parseMessageList(h)
            lines.append("\(shortPath(url)) [\(r?.statusCode ?? 0)] \(shortPath(r?.url?.absoluteString ?? "")) \(h.count)B · wierszy=\(parsed.count)")
            lines.append("  " + Self.tableRegion(h))
            if let first = parsed.first {
                lines.append("  1.: id=\(first.id) od='\(first.correspondent)' temat='\(first.subject.prefix(40))' data=\(first.sentDate.map { "\($0)" } ?? "?") nieprzeczyt=\(first.isUnread)")
            }
        }

        // Compose-form discovery — every /wiadomosci link the inbox offers, so we can
        // see where Librus actually puts "napisz wiadomość".
        if let (d, _) = try? await get("https://synergia.librus.pl/wiadomosci") {
            let h = String(data: d, encoding: .utf8) ?? ""
            let hrefs = Set(HTTP.allMatches(#"<a[^>]+href=["']([^"']*wiadomosci[^"']*)["']"#, in: h)
                .compactMap { $0.count > 1 ? $0[1] : nil })
            lines.append("linki: " + hrefs.sorted().prefix(16).joined(separator: " "))
        }
        do {
            let cats = try await recipientCategories()
            lines.append("kategorie: " + cats.map { "\($0.name)=\($0.id)" }.joined(separator: ", "))
            if let first = cats.first(where: { $0.id == "nauczyciel" }) ?? cats.first {
                let list = try await recipients(in: first)
                lines.append("[\(first.name)] pole=\(list.field) wielu=\(list.allowsMultiple) osob=\(list.people.count)"
                    + (list.people.first.map { " np. \($0.name.prefix(40))" } ?? ""))
            }
        } catch {
            lines.append("formularz: " + ((error as? LocalizedError)?.errorDescription ?? "\(error)"))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Session

    private func ensureSynergiaSession() async throws {
        if let at = sessionEstablishedAt, Date().timeIntervalSince(at) < 20 * 60,
           cookie("DZIENNIKSID", domainContains: "synergia") != nil { return }

        var steps: [String] = []
        func note(_ s: String) { steps.append(s); lastTrail = steps.joined(separator: " | ") }

        let token = try await autoLoginToken()
        note("token")

        let path = Librus.synergiaTokenLoginPath.replacingOccurrences(of: "TOKEN", with: token)
        let url = Librus.synergiaBase.absoluteString + path + "/uczen/widok/centrum_powiadomien"
        let (data, resp) = try await get(url)
        let body = String(data: data, encoding: .utf8) ?? ""
        note("synergia [\(resp?.statusCode ?? 0)] \(shortPath(resp?.url?.absoluteString ?? ""))")
        try checkBlockers(body)

        let final = resp?.url?.absoluteString ?? ""
        if cookie("DZIENNIKSID", domainContains: "librus") == nil || final.contains("/loguj") {
            throw APIError.messageBridgeFailed("nie zalogowano do Synergii · \(lastTrail) · " + snippet(body))
        }
        note("synergia-sid")
        sessionEstablishedAt = Date()
    }

    private func autoLoginToken() async throws -> String {
        let data: Data
        do {
            data = try await session.authorizedData(path: Librus.Path.autoLoginToken, method: "POST", account: account)
        } catch {
            throw APIError.messageBridgeFailed("AutoLoginToken: "
                + ((error as? LocalizedError)?.errorDescription ?? "\(error)"))
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = (obj["Token"] as? String) ?? (obj["token"] as? String), !token.isEmpty else {
            throw APIError.messageBridgeFailed("brak Token w odpowiedzi AutoLoginToken: " + snippet(data))
        }
        return token
    }

    private func checkBlockers(_ body: String) throws {
        if body.contains("grecaptcha") || body.contains("g-recaptcha") { throw APIError.captchaNeeded }
        if body.contains("przerwa_techniczna") || body.contains("OffLine") { throw APIError.maintenance }
    }

    private func cookie(_ name: String, domainContains: String) -> String? {
        let all = http.configuration.httpCookieStorage?.cookies ?? []
        if domainContains.isEmpty { return all.first { $0.name == name }?.value }
        return all.first { $0.name == name && $0.domain.contains(domainContains) }?.value
    }

    private func cookieInventory() -> String {
        let all = http.configuration.httpCookieStorage?.cookies ?? []
        guard !all.isEmpty else { return "(brak)" }
        return all.map { "\($0.name)@\($0.domain)=\($0.value.prefix(6))…" }.joined(separator: " ")
    }

    // MARK: - HTTP

    private func get(_ urlString: String) async throws -> (Data, HTTPURLResponse?) {
        guard let url = URL(string: urlString) else {
            throw APIError.messageBridgeFailed("zły adres: \(urlString)")
        }
        var request = URLRequest(url: url)
        request.setValue(Librus.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await http.data(for: request)
            return (data, resp as? HTTPURLResponse)
        } catch {
            throw APIError.messageBridgeFailed("GET \(shortPath(urlString)): \(error.localizedDescription)")
        }
    }

    private func post(_ urlString: String, pairs: [(String, String)],
                      headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse?) {
        guard let url = URL(string: urlString) else {
            throw APIError.messageBridgeFailed("zły adres: \(urlString)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(Librus.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://synergia.librus.pl", forHTTPHeaderField: "Origin")
        request.setValue("https://synergia.librus.pl/wiadomosci", forHTTPHeaderField: "Referer")
        for (name, value) in headers where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = HTTP.formBody(pairs)
        do {
            let (data, resp) = try await http.data(for: request)
            return (data, resp as? HTTPURLResponse)
        } catch {
            throw APIError.messageBridgeFailed("POST \(shortPath(urlString)): \(error.localizedDescription)")
        }
    }

    // MARK: - HTML parsing

    /// Layout confirmed against szkolny.eu's Synergia parser:
    /// `table.decorated.stretch tbody > tr`, cells
    /// `[0]=checkbox [1]=attachment icon [2]=sender [3]=subject [4]=ISO date`,
    /// and a message counts as **read** when cell 2 carries no `style` attribute
    /// (Librus bolds unread rows inline). (internal for tests)
    static func parseMessageList(_ html: String) -> [MessageItem] {
        let scope = tableScope(html) ?? html
        var out: [MessageItem] = []
        var seen = Set<Int>()

        for m in HTTP.allMatches(#"<tr[^>]*>(.*?)</tr>"#, in: scope) {
            guard m.count > 1 else { continue }
            let row = m[1]
            guard let idStr = HTTP.firstMatch(#"/wiadomosci/[0-9]+/[0-9]+/([0-9]+?)/"#, in: row),
                  let id = Int(idStr), seen.insert(id).inserted else { continue }

            let cellMatches = HTTP.allMatches(#"<td([^>]*)>(.*?)</td>"#, in: row)
            let attrs = cellMatches.map { $0.count > 1 ? $0[1] : "" }
            let raw = cellMatches.map { $0.count > 2 ? $0[2] : "" }
            let text = raw.map(stripHTML)

            var sender = "Librus"
            var subject = "(bez tematu)"
            var dateStr: String?
            var unread = false
            var attach = false

            if text.count >= 5 {
                // Anchor every column on the date cell rather than on fixed
                // indices: a row with an extra leading cell (a "new" flag, say)
                // used to shift everything by one, which left the freshest message
                // undated — and therefore sorted to the very bottom of the inbox.
                let dateIdx = Self.dateCellIndex(in: text) ?? 4
                let subjectIdx = max(dateIdx - 1, 0)
                let senderIdx = max(dateIdx - 2, 0)
                let attachIdx = dateIdx - 3

                subject = text[subjectIdx].nonEmpty ?? subject
                sender = Self.cleanCorrespondent(text[senderIdx])
                // The sender can still come out as a header word ("Nadawca") or
                // equal the subject on odd layouts — scan the cells before the
                // subject for the first thing that looks like a name.
                if Self.looksLikeHeaderLabel(sender) || sender.isEmpty || sender == subject {
                    sender = (0..<subjectIdx).reversed()
                        .lazy.map { Self.cleanCorrespondent(text[$0]) }
                        .first { !$0.isEmpty && $0.count > 1
                            && !Self.looksLikeHeaderLabel($0) && $0 != subject }
                        ?? "Librus"
                }
                dateStr = text[dateIdx]
                let style = HTTP.firstMatch(#"style=["']([^"']*)["']"#, in: attrs[senderIdx]) ?? ""
                unread = !style.trimmingCharacters(in: .whitespaces).isEmpty
                attach = attachIdx >= 0
                    && raw[attachIdx].range(of: "<img", options: .caseInsensitive) != nil
            } else {
                // Fallback for a different column layout.
                subject = HTTP.firstMatch(#"<a[^>]+/wiadomosci/[0-9]+/[0-9]+/\d+[^>]*>(.*?)</a>"#, in: row)
                    .map(stripHTML)?.nonEmpty ?? subject
                let dateIdx = Self.dateCellIndex(in: text)
                dateStr = dateIdx.map { text[$0] }
                if let di = dateIdx, di > 0 {
                    for i in stride(from: di - 1, through: 0, by: -1)
                    where text[i].count > 1 && text[i] != subject {
                        sender = text[i]; break
                    }
                } else if let s = text.first(where: { $0.count > 1 && $0 != subject }) {
                    sender = s
                }
                unread = row.range(of: #"(?i)font-weight:\s*bold|<strong|<b>"#,
                                   options: .regularExpression) != nil
                attach = row.range(of: #"(?i)zalacznik|spinacz|<img"#, options: .regularExpression) != nil
            }

            sender = Self.cleanCorrespondent(sender)
            if Self.looksLikeHeaderLabel(sender) { sender = "Librus" }

            let date = LibrusDate.fromScrapedCell(dateStr)
            out.append(MessageItem(
                id: id,
                subject: subject,
                correspondent: sender,
                sentDate: date,
                readDateServer: unread ? nil : date,
                hasAttachments: attach,
                body: nil
            ))
        }
        return out
    }

    /// Index of the cell holding the sent date — the last one that looks like a
    /// date, so a date-like fragment in a subject doesn't win.
    static func dateCellIndex(in cells: [String]) -> Int? {
        cells.lastIndex { LibrusDate.looksLikeDate($0) }
    }

    private static let headerLabels: Set<String> =
        ["nadawca", "adresat", "od", "do", "temat", "tytuł", "tytul", "data", "grupa", "typ"]

    private static func looksLikeHeaderLabel(_ s: String) -> Bool {
        headerLabels.contains(s.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// A sender/recipient cell → clean display name. Strips a parenthesised or
    /// trailing/leading role label that Synergia sometimes appends
    /// ("Jan Kowalski (Nauczyciel)", "Jan Kowalski nadawca").
    private static func cleanCorrespondent(_ raw: String) -> String {
        var s = (raw.split(separator: "(").first.map(String.init) ?? raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for role in ["nadawca", "adresat", "wychowawca", "nauczyciel"] {
            if s.lowercased().hasSuffix(" \(role)") {
                s = String(s.dropLast(role.count + 1)).trimmingCharacters(in: .whitespaces)
            }
            if s.lowercased().hasPrefix("\(role) ") {
                s = String(s.dropFirst(role.count + 1)).trimmingCharacters(in: .whitespaces)
            }
        }
        return s
    }

    /// Narrow to the `decorated stretch` message table so page chrome can't
    /// contribute stray `<tr>`s.
    private static func tableScope(_ html: String) -> String? {
        guard let r = html.range(of: #"<table[^>]*class=["'][^"']*decorated[^"']*stretch"#,
                                 options: [.regularExpression, .caseInsensitive]) else { return nil }
        let after = html[r.lowerBound...]
        guard let end = after.range(of: "</table>") else { return String(after) }
        return String(after[..<end.upperBound])
    }

    /// Contents of the element opened at `marker`, honouring nested `<div>`s.
    private static func balancedDiv(after marker: String, in html: String) -> String? {
        guard let mr = html.range(of: marker),
              let gt = html[mr.upperBound...].firstIndex(of: ">") else { return nil }
        let start = html.index(after: gt)
        var i = start
        var depth = 1
        while i < html.endIndex {
            if html[i] == "<" {
                let rest = html[i...]
                if rest.hasPrefix("</div") {
                    depth -= 1
                    if depth == 0 { return String(html[start..<i]) }
                } else if rest.hasPrefix("<div") {
                    depth += 1
                }
            }
            i = html.index(after: i)
        }
        return String(html[start...])
    }

    /// ~900 chars of the HTML around the first message link (or the first table),
    /// whitespace-collapsed — enough to see the row structure remotely.
    private static func tableRegion(_ html: String) -> String {
        let anchor = html.range(of: "/wiadomosci/1/5/")?.lowerBound
            ?? html.range(of: "table")?.lowerBound
            ?? html.startIndex
        let start = html.index(anchor, offsetBy: -450, limitedBy: html.startIndex) ?? html.startIndex
        let end = html.index(anchor, offsetBy: 450, limitedBy: html.endIndex) ?? html.endIndex
        return String(html[start..<end])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func firstGroup(_ pattern: String, _ text: String) -> String? {
        HTTP.firstMatch(pattern, in: text)
    }

    private static func stripHTML(_ s: String) -> String {
        decodeEntities(s.replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanup(_ html: String) -> String {
        Self.decodeEntities(
            html
                .replacingOccurrences(of: "<![CDATA[", with: "")
                .replacingOccurrences(of: "]]>", with: "")
                .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)</p>"#, with: "\n\n", options: .regularExpression)
                .replacingOccurrences(of: #"(?s)<[^>]+>"#, with: "", options: .regularExpression)
        )
        .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decode HTML entities Librus emits — numeric (`&#243;` / `&#xF3;`) plus the
    /// named ones that show up in Polish names ("rodzic&oacute;w" -> "rodziców").
    private static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        for (name, ch) in namedEntities {
            if out.contains(name) { out = out.replacingOccurrences(of: name, with: ch) }
        }
        // &#243;  and  &#xF3;
        for pattern in [#"&#(\d+);"#, #"&#[xX]([0-9A-Fa-f]+);"#] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = out as NSString
            var result = ""
            var last = 0
            for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let digits = ns.substring(with: m.range(at: 1))
                let radix = pattern.contains("x") ? 16 : 10
                if let code = UInt32(digits, radix: radix), let scalar = Unicode.Scalar(code) {
                    result.append(Character(scalar))
                } else {
                    result += ns.substring(with: m.range)
                }
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            out = result
        }
        return out
    }

    private static let namedEntities: [(String, String)] = [
        ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
        ("&quot;", "\""), ("&apos;", "'"), ("&#039;", "'"), ("&#39;", "'"),
        ("&oacute;", "ó"), ("&Oacute;", "Ó"),
        ("&aacute;", "á"), ("&eacute;", "é"), ("&iacute;", "í"), ("&uacute;", "ú"),
        ("&aogon;", "ą"), ("&Aogon;", "Ą"), ("&eogon;", "ę"), ("&Eogon;", "Ę"),
        ("&lstrok;", "ł"), ("&Lstrok;", "Ł"),
        ("&nacute;", "ń"), ("&Nacute;", "Ń"),
        ("&sacute;", "ś"), ("&Sacute;", "Ś"),
        ("&cacute;", "ć"), ("&Cacute;", "Ć"),
        ("&zacute;", "ź"), ("&Zacute;", "Ź"),
        ("&zdot;", "ż"), ("&Zdot;", "Ż"),
        ("&ndash;", "–"), ("&mdash;", "—"), ("&hellip;", "…"),
        ("&raquo;", "»"), ("&laquo;", "«"),
        ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&rdquo;", "”"), ("&ldquo;", "„"),
        ("&bull;", "•"), ("&middot;", "·"), ("&deg;", "°"),
        ("&copy;", "©"), ("&reg;", "®"), ("&trade;", "™"), ("&euro;", "€"),
    ]

    private func snippet(_ data: Data, _ max: Int = 200) -> String {
        snippet(String(data: data, encoding: .utf8) ?? "", max)
    }
    private func snippet(_ text: String, _ max: Int = 200) -> String {
        String(text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).prefix(max))
    }

    private func shortPath(_ url: String) -> String {
        URLComponents(string: url)?.path ?? url
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
