import Foundation
import SwiftData

// The iPhone's side of sync: it talks to the Mac whenever it can reach it (on opening,
// a few seconds after each change, and every minute while open). Away from the Mac
// everything still works; changes wait and go across next time.

@MainActor final class SyncClient: ObservableObject {
    static let shared = SyncClient()

    @Published private(set) var syncing = false
    @Published private(set) var error: String?
    @Published private(set) var lastSync: Date? = UserDefaults.standard.object(forKey: "lastMacSync") as? Date
    var context: ModelContext?

    private let defaults = UserDefaults.standard
    private var pending: Task<Void, Never>?
    private var timer: Timer?

    /// e.g. https://marcels-macbook-pro.tail1234.ts.net:8443
    var address: String { defaults.string(forKey: "macAddress") ?? "" }
    var code: String { defaults.string(forKey: "macCode") ?? "" }
    var macName: String { defaults.string(forKey: "macName") ?? "your Mac" }
    var connected: Bool { !address.isEmpty && !code.isEmpty }

    /// The Mac's clock: what it has sent us up to. And ours: what we've sent it up to.
    private var macCursor: Double {
        get { defaults.double(forKey: "macCursor") }
        set { defaults.set(newValue, forKey: "macCursor") }
    }
    private var pushedUntil: Double {
        get { defaults.double(forKey: "pushedUntil") }
        set { defaults.set(newValue, forKey: "pushedUntil") }
    }

    // MARK: Connecting

    struct Mac { var name: String; var hasData: Bool }

    /// Check the address and code work, without changing anything.
    func check(address: String, code: String) async throws -> Mac {
        let base = Self.normalise(address)
        let (data, _) = try await request(base: base, code: Self.normaliseCode(code), path: "/gym/ping", body: nil)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return Mac(name: json["name"] as? String ?? "your Mac", hasData: json["hasData"] as? Bool ?? false)
    }

    /// Start syncing with this Mac. If it already has your data, this iPhone's is replaced
    /// by it (only once it has all arrived); if the Mac is empty, this iPhone's data is sent to it.
    func connect(address: String, code: String, mac: Mac) async throws {
        guard let ctx = context else { return }
        let base = Self.normalise(address), code = Self.normaliseCode(code)
        if mac.hasData {
            let (data, _) = try await request(base: base, code: code, path: "/gym/sync", body: ["since": 0, "records": [], "deleted": []])
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let now = json["now"] as? Double else {
                throw SyncError.message("Your Mac sent something unexpected. Update Gym on both devices.")
            }
            ctx.wipeSyncedData()
            ctx.applySync(records: json["records"] as? [[String: Any]] ?? [], deleted: json["deleted"] as? [[String: Any]] ?? [])
            macCursor = now - 60
            pushedUntil = Date().timeIntervalSince1970
        } else {
            macCursor = 0; pushedUntil = 0                          // everything here goes to the Mac
        }
        defaults.set(base, forKey: "macAddress")
        defaults.set(code, forKey: "macCode")
        defaults.set(mac.name, forKey: "macName")
        objectWillChange.send()
        await sync()
        startTimer()
    }

    func disconnect() {
        for k in ["macAddress", "macCode", "macName", "macCursor", "pushedUntil", "lastMacSync"] { defaults.removeObject(forKey: k) }
        timer?.invalidate(); timer = nil
        error = nil; lastSync = nil
        objectWillChange.send()
    }

    // MARK: Syncing

    /// Once the app is open: sync now, then every minute and shortly after each change.
    func start() {
        guard connected else { return }
        Task { await sync() }
        startTimer()
    }

    func pause() {
        timer?.invalidate(); timer = nil
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in Task { @MainActor in await SyncClient.shared.sync() } }
    }

    /// A change was saved here: send it in a few seconds (several quick changes go together).
    func changed() {
        guard connected, !syncing else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { await sync() }
        }
    }

    /// One round: send what changed here, get what changed on the Mac.
    func sync() async {
        guard connected, !syncing, let ctx = context else { return }
        syncing = true
        defer { syncing = false }
        if ctx.hasChanges { ctx.commit() }
        let started = Date()
        let (records, deleted) = ctx.syncChanges(since: Date(timeIntervalSince1970: pushedUntil))
        let body: [String: Any] = ["since": macCursor, "records": records, "deleted": deleted]
        do {
            let (data, _) = try await request(base: address, code: code, path: "/gym/sync", body: body)
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let now = json["now"] as? Double else {
                throw SyncError.message("Your Mac sent something unexpected. Update Gym on both devices.")
            }
            guard connected else { return }                        // disconnected while waiting
            ctx.applySync(records: json["records"] as? [[String: Any]] ?? [], deleted: json["deleted"] as? [[String: Any]] ?? [])
            macCursor = now - 60                                    // a little overlap; applying twice changes nothing
            pushedUntil = started.timeIntervalSince1970
            lastSync = Date(); defaults.set(lastSync, forKey: "lastMacSync")
            if !records.isEmpty || !((json["records"] as? [Any])?.isEmpty ?? true) { WidgetData.changed(ctx) }
            error = nil
        } catch {
            self.error = (error as? SyncError)?.text ?? "Couldn't reach \(macName). It syncs next time the Mac is on with Gym open and Tailscale connected."
        }
    }

    // MARK: Photo logging (the model runs on the Mac)

    func photo(images: [Data], text: String) async throws -> [AIItem] {
        PhotoAI.parse(try await photoRaw(images: images, text: text, recipe: false))
    }

    /// The model's raw answer (a meal, or a recipe with name and servings).
    func photoRaw(images: [Data], text: String, recipe: Bool) async throws -> String {
        let body: [String: Any] = ["text": text, "images": images.map { $0.base64EncodedString() }, "mode": recipe ? "recipe" : "meal"]
        let (data, _) = try await request(base: address, code: code, path: "/gym/photo", body: body, timeout: 240)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let raw = json["raw"] as? String { return raw }
        // An older Mac app: items only.
        let items = json["items"] ?? []
        return String(decoding: (try? JSONSerialization.data(withJSONObject: ["items": items])) ?? Data(), as: UTF8.self)
    }


    // MARK: HTTP

    enum SyncError: Error {
        case message(String)
        var text: String { switch self { case .message(let m): return m } }
    }

    private func request(base: String, code: String, path: String, body: [String: Any]?, timeout: Double? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: base + path) else { throw SyncError.message("That address doesn't look right.") }
        var r = URLRequest(url: url, timeoutInterval: timeout ?? (body == nil ? 10 : 60))
        r.setValue("Bearer \(code)", forHTTPHeaderField: "Authorization")
        if let body {
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: r)
        guard let http = response as? HTTPURLResponse else { throw SyncError.message("No answer from your Mac.") }
        switch http.statusCode {
        case 200: return (data, http)
        case 401: throw SyncError.message("The pairing code doesn't match. Check it on the Mac (Gym → Settings → iPhone sync) and connect again.")
        default:
            let msg = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String
            throw SyncError.message(msg ?? "Your Mac answered with an error (\(http.statusCode)).")
        }
    }

    /// "marcels-mac.tail12.ts.net" → "https://marcels-mac.tail12.ts.net:8443"
    static func normalise(_ address: String) -> String {
        var a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        while a.hasSuffix("/") { a.removeLast() }
        if !a.contains("://") { a = "https://" + a }
        if let u = URLComponents(string: a), u.scheme == "https", u.port == nil { a += ":8443" }
        return a
    }

    static func normaliseCode(_ code: String) -> String {
        let c = code.uppercased().filter { $0.isLetter || $0.isNumber }
        return c.count == 8 ? "\(c.prefix(4))-\(c.suffix(4))" : code.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// What the Mac's QR code holds: "gymsync:<address>#<code>".
    static func parsePairing(_ text: String) -> (address: String, code: String)? {
        guard text.hasPrefix("gymsync:"), let hash = text.lastIndex(of: "#") else { return nil }
        let address = String(text[text.index(text.startIndex, offsetBy: 8)..<hash])
        let code = String(text[text.index(after: hash)...])
        return address.isEmpty || code.isEmpty ? nil : (address, code)
    }
}
