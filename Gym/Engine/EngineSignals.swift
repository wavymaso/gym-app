import Foundation

// Training and recovery signals: flags with a reason, never calorie changes on their own.

struct LiftSession: Equatable { var day: String; var exercise: String; var kg: Double; var reps: Int; var rir: Double? }

enum EngineSignals {
    /// Epley e1RM from a set of 3–10 reps (reps in reserve added); nil outside that range.
    static func e1rm(_ s: LiftSession) -> Double? {
        guard (3...10).contains(s.reps), s.kg > 0 else { return nil }
        return s.kg * (1 + (Double(s.reps) + (s.rir ?? 0)) / 30)
    }

    /// Best e1RM per week (week index) for each of the main lifts (the most-trained ones).
    static func weekly(_ sets: [LiftSession], weekOf: (String) -> Int, lifts: Int = 3) -> [String: [Int: Double]] {
        let counts = Dictionary(grouping: sets, by: \.exercise).mapValues(\.count)
        let main = Set(counts.sorted { $0.value > $1.value }.prefix(lifts).map(\.key))
        var out: [String: [Int: Double]] = [:]
        for s in sets where main.contains(s.exercise) {
            guard let e = e1rm(s) else { continue }
            out[s.exercise, default: [:]][weekOf(s.day)] = max(out[s.exercise]?[weekOf(s.day)] ?? 0, e)
        }
        return out
    }

    /// The flags for this week.
    static func flags(weekly: [String: [Int: Double]], thisWeek w: Int, phase: Phase, observedRate: Double, targetRate: Double,
                      weeksInPhase: Int, adherence: Double, sleepHours: Double?) -> [EngineReason] {
        var out: [EngineReason] = []
        // e1RM falling two weeks running on most main lifts.
        let falling = weekly.values.filter { s in
            guard let a = s[w - 2], let b = s[w - 1], let c = s[w] else { return false }
            return b < a * 0.98 && c < b * 0.98
        }.count
        let main = max(weekly.count, 1)
        let losingFast = phase == .cut && observedRate < targetRate * 1.25        // both negative: faster loss
        if falling * 2 >= main, falling > 0, losingFast {
            out.append(.init(rule: "strength drop on a fast cut", detail: "Estimated 1RM has fallen two weeks in a row on your main lifts while you're losing faster than planned: the deficit may be too aggressive.",
                             evidence: ["signal.e1rm.rule", "rate.cut.pctPerWeek"]))
        }
        // Bulk: weight rising faster than planned with flat strength.
        if phase == .bulk, observedRate > targetRate * 1.5 {
            let flat = weekly.values.filter { s in
                guard let a = s[w - 4], let c = s[w] else { return false }
                return c < a * 1.01
            }.count
            if flat * 2 >= main, flat > 0 {
                out.append(.init(rule: "fast gain, flat strength", detail: "Weight is rising faster than planned while strength is flat: the surplus is likely going mostly to fat.",
                                 evidence: ["rate.bulk.pctPerWeek"]))
            }
        }
        // Diet break: never on a timer alone.
        if phase == .cut, weeksInPhase >= 8 {
            var why: [String] = []
            if !out.isEmpty { why.append("strength falling") }
            if adherence < 0.7 { why.append("adherence slipping") }
            if let s = sleepHours, s < 6.5 { why.append("short sleep") }
            if !why.isEmpty {
                out.append(.init(rule: "diet break", detail: "\(weeksInPhase) weeks into the cut with \(why.joined(separator: " and ")): a week or two at maintenance may help adherence (evidence for fat-loss benefit in trained people is weak).",
                                 evidence: ["dietBreak.benefit"] + (sleepHours.map { $0 < 6.5 ? ["sleep.deficit"] : [] } ?? [])))
            }
        }
        if let s = sleepHours, s < 6, phase == .cut, out.allSatisfy({ $0.rule != "diet break" }) {
            out.append(.init(rule: "short sleep", detail: "Short sleep during a deficit tends to shift loss from fat towards muscle.", evidence: ["sleep.deficit"]))
        }
        return out
    }
}
