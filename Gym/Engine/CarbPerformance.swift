import Foundation

// Your own data, not proof: does a session go better after more carbs (in the 4 hours before, or
// the day before)? Each session's performance is its key lifts' best e1RM and volume against that
// lift's recent sessions. Shown only from 20 sessions, as an observation with its caveats.

enum CarbPerformance {
    struct Session: Equatable {
        var day: String
        var preCarbs: Double              // g eaten in the 4 h before the session started
        var previousDayCarbs: Double      // g the day before
        var lifts: [String: (e1rm: Double, volume: Double)]   // exercise → best e1RM, total kg × reps
        static func == (a: Session, b: Session) -> Bool { a.day == b.day && a.preCarbs == b.preCarbs && a.previousDayCarbs == b.previousDayCarbs }
    }
    struct Insight: Equatable {
        var sessions: Int
        var preHigh: Double, preLow: Double         // mean performance change (%) in the top and bottom third by pre-workout carbs
        var dayHigh: Double, dayLow: Double         // same, by the previous day's carbs
        var preCut: (low: Double, high: Double)     // carb bounds of the bottom and top thirds (g)
        var dayCut: (low: Double, high: Double)
        var text: String
        static func == (a: Insight, b: Insight) -> Bool { a.text == b.text }
    }
    static let minimumSessions = 20

    /// Performance per session: for each lift done before (at least 1 earlier session), the change in
    /// best e1RM against the median of its previous up to 5 sessions, half-weighted with volume; averaged.
    static func scores(_ sessions: [Session]) -> [(Session, Double)] {
        let ss = sessions.sorted { $0.day < $1.day }
        var history: [String: [(e1rm: Double, volume: Double)]] = [:]
        var out: [(Session, Double)] = []
        func median(_ x: [Double]) -> Double { let s = x.sorted(); return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2 }
        for s in ss {
            var changes: [Double] = []
            for (ex, v) in s.lifts.sorted(by: { $0.key < $1.key }) {
                if let h = history[ex], !h.isEmpty {
                    let recent = h.suffix(5)
                    let e = median(recent.map(\.e1rm)), vol = median(recent.map(\.volume))
                    if e > 0, vol > 0 { changes.append(0.5 * (v.e1rm / e - 1) + 0.5 * (v.volume / vol - 1)) }
                }
                history[ex, default: []].append(v)
            }
            if !changes.isEmpty { out.append((s, changes.reduce(0, +) / Double(changes.count) * 100)) }
        }
        return out
    }

    static func analyse(_ sessions: [Session]) -> Insight? {
        let sc = scores(sessions)
        guard sc.count >= minimumSessions else { return nil }
        func thirds(_ key: (Session) -> Double) -> (high: Double, low: Double, cut: (Double, Double)) {
            let sorted = sc.sorted { key($0.0) < key($1.0) }
            let n = sorted.count / 3
            let low = sorted.prefix(n), high = sorted.suffix(n)
            return (high.map(\.1).reduce(0, +) / Double(n), low.map(\.1).reduce(0, +) / Double(n), (key(low.last!.0), key(high.first!.0)))
        }
        let pre = thirds(\.preCarbs), day = thirds(\.previousDayCarbs)
        let f: (Double) -> String = { String(format: "%+.1f%%", $0) }
        let text = "Over \(sc.count) sessions: after more carbs in the 4 h before (≥ \(Int(pre.cut.1)) g) your key lifts were \(f(pre.high)) against your recent sessions, after less (≤ \(Int(pre.cut.0)) g) \(f(pre.low)). By the day before: \(f(day.high)) after ≥ \(Int(day.cut.1)) g, \(f(day.low)) after ≤ \(Int(day.cut.0)) g. This is your own observational data: sleep, fatigue, the program and chance all play a part, so it isn't proof of cause."
        return Insight(sessions: sc.count, preHigh: pre.high, preLow: pre.low, dayHigh: day.high, dayLow: day.low, preCut: pre.cut, dayCut: day.cut, text: text)
    }
}
