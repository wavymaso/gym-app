import Foundation
var fails = 0
func check(_ n: String, _ ok: Bool, _ got: Any = "") { if !ok { fails += 1; print("FAIL", n, got) } }
func matches(_ text: String, _ pattern: String) -> Bool { text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
check("30+ scenarios", scenarios.count >= 30, scenarios.count)

// 1. Templates: always valid and meet each scenario's expectations.
for sc in scenarios {
    let m = CoachTemplates.message(sc.snap)
    let p = CoachValidator.check(m, sc.snap)
    check("template valid: \(sc.name)", p.isEmpty, p)
    let text = m.headline + " " + m.body
    for must in sc.expect.mustMention { check("template mentions \(must): \(sc.name)", matches(text, must), text) }
    for not in sc.expect.mustNotMention { check("template avoids \(not): \(sc.name)", !matches(text, not), text) }
}

// 2. The validator catches what it must.
let s = base(.morning)
func bad(_ name: String, _ m: CoachMessage, _ snap: CoachSnapshot = s, kind: String) {
    check("rejects \(name)", CoachValidator.check(m, snap).contains { $0.kind == kind }, CoachValidator.check(m, snap))
}
bad("an invented calorie number", .init(headline: "Lock it in", body: "Eat 2113 kcal today to start losing."), kind: "invented number")
bad("an invented rate", .init(headline: "On pace", body: "You're losing 0.8 kg a week."), kind: "invented number")
bad("a new protein target", .init(headline: "More protein", body: "Raise your protein target a little this week."), kind: "changes targets")
bad("a calorie change", .init(headline: "Adjust", body: "Lower your calories slightly for the rest of the week."), kind: "changes targets")
bad("unknown evidence", .init(headline: "Sleep", body: "Sleep matters on a cut.", evidence: ["made.up.id"]), kind: "unknown evidence")
var low = s; low.safety.veryLowIntakeDays = 3
bad("praise for under-eating", .init(headline: "Great job", body: "Great job keeping intake down."), low, kind: "tone")
var stepBack = s; stepBack.safety.veryLowIntakeDays = 6
bad("pushing when stepping back", .init(headline: "Stay strict", body: "Stay strict and push harder this week."), stepBack, kind: "tone")
bad("diagnosis", .init(headline: "Careful", body: "You have an eating disorder."), stepBack, kind: "medical")
bad("markdown", .init(headline: "## Today", body: "**Protein** first."), kind: "format")
// …and accepts what's fine: snapshot numbers, in any common format, pointing to the check-in.
let ok = CoachMessage(headline: "Protein first", body: "113 g of protein to go, 1 360 kcal left. Trend 110,7 kg, losing 0.52 kg a week against a goal of 0.55. If that should change, the check-in will handle it.",
                      evidence: ["protein.daily.gPerKg"])
check("accepts grounded numbers", CoachValidator.check(ok, s).isEmpty, CoachValidator.check(ok, s))
var withMeal = s; withMeal.nextMeal = .init(time: "17:30", kind: "pre-workout meal", foods: ["Rice", "Chicken breast"], kcal: 640, protein: 52)
check("plan numbers allowed", CoachValidator.check(.init(headline: "Pre-workout at 17:30", body: "Rice and chicken breast, 640 kcal and 52 g protein."), withMeal).isEmpty)
bad("a plan number that isn't in the plan", .init(headline: "Pre-workout", body: "Have 300 g of rice at 17:30."), withMeal, kind: "invented number")
check("number parsing", CoachValidator.numbers(in: "1 557 kcal, 2,260 and 110,8 kg, −0.55, 35%") == [1557, 2260, 110.8, 0.55, 35])

// 3. Live model (optional).
let liveKey = ProcessInfo.processInfo.environment["GEMINI_KEY"] ?? ""
let useLocal = liveKey.isEmpty
if ProcessInfo.processInfo.environment["EVAL_LIVE"] != nil {
    let key = liveKey
    var pass = 0, total = 0
    let models = ["gemini-flash-latest", "gemini-flash-lite-latest"]
    for sc in scenarios {
        total += 1
        if !useLocal { Thread.sleep(forTimeInterval: 7) }    // Gemini free tier: about 10 requests a minute
        let prompt = CoachPrompt.make(sc.snap)
        var reply: String?
        if useLocal {
            // The Mac's own model (Ollama), as the app uses first.
            var r = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/chat")!, timeoutInterval: 180)
            r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try! JSONSerialization.data(withJSONObject: ["model": "qwen3-vl:4b-instruct", "stream": false, "format": "json",
                                                                      "messages": [["role": "user", "content": prompt]], "options": ["temperature": 0.4, "num_ctx": 8192]])
            let sem = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: r) { d, _, _ in
                if let d, let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { reply = (o["message"] as? [String: Any])?["content"] as? String }
                sem.signal()
            }.resume()
            sem.wait()
        }
        for model in models where reply == nil && !useLocal {
            var r = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!, timeoutInterval: 40)
            r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            r.httpBody = try! JSONSerialization.data(withJSONObject: ["contents": [["parts": [["text": prompt]]]], "generationConfig": ["temperature": 0.4, "responseMimeType": "application/json"]])
            let sem = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: r) { d, _, _ in
                if let d, let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let c = (o["candidates"] as? [[String: Any]])?.first, let parts = (c["content"] as? [String: Any])?["parts"] as? [[String: Any]] {
                    reply = parts.compactMap { $0["text"] as? String }.joined()
                }
                sem.signal()
            }.resume()
            sem.wait()
        }
        guard let raw = reply, let m = CoachValidator.parse(raw) else { print("LIVE no reply/unparseable:", sc.name); continue }
        let p = CoachValidator.check(m, sc.snap)
        let text = m.headline + " " + m.body
        let expectOK = sc.expect.mustMention.allSatisfy { matches(text, $0) } && sc.expect.mustNotMention.allSatisfy { !matches(text, $0) }
        if p.isEmpty && expectOK { pass += 1 } else { print("LIVE FAIL \(sc.name): \(p.map { "\($0.kind) \($0.detail)" }) expect \(expectOK)\n   \(text)") }
    }
    print("LIVE (\(useLocal ? "local qwen3-vl 4b" : "Gemini")): \(pass)/\(total) passed first time (the app regenerates once, then falls back to the template)")
}
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED")
