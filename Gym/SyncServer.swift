import Foundation
import Network
import SwiftData

// The Mac's side of sync: a small HTTP server on 127.0.0.1, published to your own
// devices by Tailscale Serve at https://<this Mac>.<tailnet>.ts.net:8443.
// It only answers requests that carry the pairing code.

let syncPort: UInt16 = 8010

/// One sync round, the same on both sides: what the phone sends, what the Mac answers.
/// (A plain function so it can be tested without a network.)
@MainActor func handleSync(_ body: [String: Any], ctx: ModelContext) -> [String: Any] {
    let since = Date(timeIntervalSince1970: body["since"] as? Double ?? 0)
    let started = Date()
    ctx.applySync(records: body["records"] as? [[String: Any]] ?? [], deleted: body["deleted"] as? [[String: Any]] ?? [])
    let (records, deleted) = ctx.syncChanges(since: since)
    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastPhoneSync")   // a number: Settings reads it with @AppStorage
    return ["now": started.timeIntervalSince1970, "records": records, "deleted": deleted]
}

#if os(macOS)
@MainActor final class SyncServer: ObservableObject {
    static let shared = SyncServer()
    @Published private(set) var running = false
    @Published private(set) var error: String?
    private var listener: NWListener?
    var context: ModelContext?

    /// The pairing code the phone must send (made once, kept until you make a new one).
    var code: String {
        if let c = UserDefaults.standard.string(forKey: "syncCode") { return c }
        return newCode()
    }

    @discardableResult func newCode() -> String {
        let letters = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        let c = String((0..<8).map { _ in letters.randomElement()! })
        let pretty = "\(c.prefix(4))-\(c.suffix(4))"
        UserDefaults.standard.set(pretty, forKey: "syncCode")
        objectWillChange.send()
        return pretty
    }

    /// Sync on or off, remembered between launches.
    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "syncEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "syncEnabled"); newValue ? start() : stop(); objectWillChange.send() }
    }

    /// The address the iPhone uses (Tailscale Serve publishes the server there).
    var address: String {
        get { UserDefaults.standard.string(forKey: "syncAddress") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "syncAddress"); objectWillChange.send() }
    }

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: syncPort)!)   // never on the network directly
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] c in Task { @MainActor in self?.serve(c) } }
            l.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready: self?.running = true; self?.error = nil
                    case .failed(let e): self?.running = false; self?.error = "Couldn't start sync: \(e.localizedDescription)"; self?.stop()
                    default: break
                    }
                }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            self.error = "Couldn't start sync: \(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel(); listener = nil; running = false
    }

    // MARK: HTTP, just enough for one request per connection

    private func serve(_ c: NWConnection) {
        c.start(queue: .main)
        receive(c, buffer: Data())
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, err in
            Task { @MainActor in
                guard let self else { return }
                var buf = buffer
                if let data { buf.append(data) }
                if let request = HTTPRequest(buf) {
                    self.respond(c, to: request)
                } else if done || err != nil || buf.count > 50 << 20 {
                    c.cancel()
                } else {
                    self.receive(c, buffer: buf)
                }
            }
        }
    }

    private func respond(_ c: NWConnection, to r: HTTPRequest) {
        var status = 200
        var json: Any = ["ok": true]
        if r.headers["authorization"] != "Bearer \(code)" {
            status = 401; json = ["error": "Wrong pairing code. Check it on the Mac: Gym → Settings → iPhone sync."]
        } else if r.method == "GET" && r.path == "/gym/ping" {
            json = ["ok": true, "name": Host.current().localizedName ?? "Mac", "hasData": context?.hasSyncedData ?? false]
        } else if r.method == "POST" && r.path == "/gym/photo",
                  let body = (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any] {
            // The phone's photo, through the model on this Mac (takes a few seconds; answer when done).
            let images = ((body["images"] as? [String]) ?? [body["image"] as? String].compactMap { $0 }).compactMap { Data(base64Encoded: $0) }
            let text = body["text"] as? String ?? ""
            Task { @MainActor in
                do {
                    let items = try await PhotoAI.askLocal(images: images, text: text)
                    self.send(c, 200, ["items": items.map(\.dict)])
                } catch {
                    self.send(c, 502, ["error": error.localizedDescription])
                }
            }
            return
        } else if r.method == "POST" && r.path == "/gym/sync", let ctx = context,
                  let body = (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any] {
            json = handleSync(body, ctx: ctx)
        } else {
            status = 404; json = ["error": "Not found"]
        }
        send(c, status, json)
    }

    private func send(_ c: NWConnection, _ status: Int, _ json: Any) {
        let payload = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        let head = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        c.send(content: Data(head.utf8) + payload, completion: .contentProcessed { _ in c.cancel() })
    }
}
#endif

/// A complete HTTP request (nil until all of it has arrived).
struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    init?(_ data: Data) {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[data.startIndex..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let first = head.first?.split(separator: " ") ?? []
        guard first.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in head.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = data[end.upperBound...]
        guard body.count >= length else { return nil }
        method = String(first[0]); path = String(first[1]).components(separatedBy: "?")[0]; self.headers = headers
        self.body = Data(body.prefix(length))
    }
}
