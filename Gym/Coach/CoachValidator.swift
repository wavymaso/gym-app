import Foundation

// The grounding contract, enforced: every number must come from the snapshot, every evidence id from
// the snapshot's list, no targets may be set or changed, and tone rules hold (no praise for
// under-eating, no goal-pushing when the snapshot says step back).

enum CoachValidator {
    struct Problem: Equatable { var kind: String; var detail: String }

    /// Numbers written in text: "1 557", "2,260", "110,8", "−0.55", "35%".
    static func numbers(in text: String) -> [Double] {
        var out: [Double] = []
        let t = text.replacingOccurrences(of: "\u{2212}", with: "-").replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
        let re = try! NSRegularExpression(pattern: #"\d{1,3}(?:[ ,]\d{3})+(?![\d,.])|\d+(?:[.,]\d+)?"#)
        for m in re.matches(in: t, range: NSRange(t.startIndex..., in: t)) {
            var s = String(t[Range(m.range, in: t)!])
            if s.range(of: #"^\d{1,3}([ ,]\d{3})+$"#, options: .regularExpression) != nil {
                s = s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "")      // thousands
            } else {
                s = s.replacingOccurrences(of: ",", with: ".")                                              // decimal comma
            }
            if let v = Double(s) { out.append(v) }
        }
        return out
    }

    /// A stated number matches if some allowed number, rounded to the stated precision, equals it.
    static func isAllowed(_ v: Double, written: String? = nil, in allowed: [Double]) -> Bool {
        allowed.contains { a in
            abs(a - v) < 0.0001 || abs(a.rounded() - v) < 0.0001 || abs((a * 10).rounded() / 10 - v) < 0.0001 || abs((a * 100).rounded() / 100 - v) < 0.0001
        }
    }

    static let targetChange = try! NSRegularExpression(pattern:
        #"\b(set|change|raise|lower|increase|decrease|bump|drop|cut|adjust|move)\b[^.]{0,30}\b(your )?(calorie|calories|kcal|target|targets|macro|macros|protein target|carb target|fat target)s?\b"#,
        options: .caseInsensitive)
    static let praise = try! NSRegularExpression(pattern: #"\b(great job|well done|nice work|good job|keep it up|proud|impressive|crushing it|nailed)\b"#, options: .caseInsensitive)
    static let pushing = try! NSRegularExpression(pattern: #"\b(push harder|stay strict|cut more|eat less|tighten up|no excuses)\b"#, options: .caseInsensitive)
    static let medical = try! NSRegularExpression(pattern: #"\b(diagnos|disorder|prescri|medication|you have an?|deficiency)\b"#, options: .caseInsensitive)

    static func check(_ m: CoachMessage, _ s: CoachSnapshot) -> [Problem] {
        var p: [Problem] = []
        let text = [m.headline, m.body, m.action?.label ?? ""].joined(separator: " \n ")
        let allowed = s.allowedNumbers
        for v in numbers(in: text) where !isAllowed(v, in: allowed) {
            p.append(.init(kind: "invented number", detail: String(v)))
        }
        let ids = Set(s.evidence.map(\.id))
        for e in m.evidence where !ids.contains(e) { p.append(.init(kind: "unknown evidence", detail: e)) }
        func has(_ re: NSRegularExpression) -> Bool { re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
        // Changing targets: only by pointing at the check-in (or the engine's proposal).
        // (The engine's own reason and flags may be quoted: remove them before looking for target changes.)
        var own = text
        for q in [s.checkIn.lastReason ?? ""] + s.flags where !q.isEmpty { own = own.replacingOccurrences(of: q, with: "") }
        let pointsToCheckIn = own.lowercased().contains("check-in") || own.lowercased().contains("proposal")
            || m.action?.kind == .openCheckIn || m.action?.kind == .openProposal
        // Negations ("no change to targets", "won't lower") aren't changes.
        let negated = own.replacingOccurrences(of: #"\b(no|not|won't|doesn't|don't|never|without|no need to)\b[^.]{0,25}"#, with: " ", options: [.regularExpression, .caseInsensitive])
        if targetChange.firstMatch(in: negated, range: NSRange(negated.startIndex..., in: negated)) != nil, !pointsToCheckIn {
            p.append(.init(kind: "changes targets", detail: "suggests a target change without pointing to the check-in"))
        }
        if s.safety.veryLowIntakeDays >= 2 || s.today.kcalLeft > s.today.kcalTarget / 2 && s.moment == .nudge, has(praise) {
            p.append(.init(kind: "tone", detail: "praise while intake is low"))
        }
        if s.safety.stepBack, has(pushing) || has(targetChange) { p.append(.init(kind: "tone", detail: "pushing goals when the snapshot says step back")) }
        if has(medical) { p.append(.init(kind: "medical", detail: "diagnosis-like language")) }
        // Coverage: the message must be about what matters in the snapshot.
        let lower = text.lowercased()
        if s.safety.stepBack, !(lower.contains("step back") || lower.contains("doctor") || lower.contains("regular meals")) {
            p.append(.init(kind: "coverage", detail: "the snapshot says step back"))
        }
        if !s.safety.stepBack, s.moment != .checkIn, let f = s.flags.first {
            let key = ["strength", "sleep", "surplus", "fat", "break", "maintenance", "deficit"].filter { f.lowercased().contains($0) }
            if !key.isEmpty, !key.contains(where: { lower.contains($0) }) { p.append(.init(kind: "coverage", detail: "ignores the engine's flag")) }
        }
        if s.moment == .checkIn, !s.safety.stepBack, let a = s.checkIn.lastAction {
            let ok: Bool = switch a {
                case "no change": ["no change", "kept", "keep", "same", "unchanged", "hold"].contains { lower.contains($0) }
                case "proposed": ["propos", "accept", "review"].contains { lower.contains($0) }
                default: s.checkIn.lastTo.map { lower.contains(String($0)) || lower.contains("up") || lower.contains("down") || lower.contains("lower") || lower.contains("raise") || lower.contains("more") || lower.contains("less") } ?? true
            }
            if !ok { p.append(.init(kind: "coverage", detail: "doesn't explain the engine's decision")) }
        }
        if m.headline.count > 80 || m.body.count > 420 { p.append(.init(kind: "length", detail: "too long")) }
        if m.headline.contains("#") || m.body.contains("**") || m.body.contains("\n- ") { p.append(.init(kind: "format", detail: "markdown")) }
        return p
    }

    /// Parse the model's JSON reply (a single object), forgiving about code fences.
    static func parse(_ raw: String) -> CoachMessage? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let a = t.firstIndex(of: "{"), let b = t.lastIndex(of: "}") { t = String(t[a...b]) }
        guard let d = t.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let h = o["headline"] as? String, let body = o["body"] as? String else { return nil }
        var m = CoachMessage(headline: h.trimmingCharacters(in: .whitespacesAndNewlines), body: body.trimmingCharacters(in: .whitespacesAndNewlines))
        if let a = o["action"] as? [String: Any], let k = a["kind"] as? String, let kind = CoachMessage.Action.Kind(rawValue: k), kind != .none {
            m.action = .init(kind: kind, label: a["label"] as? String ?? "")
        }
        m.evidence = o["evidence"] as? [String] ?? []
        return m
    }
}
