import Foundation

// How many carbs each day and each meal gets (not which foods). Carbs stay the remainder after the
// protein target and fat floor, so the coaching engine's calories always win:
// - between days: on training days fat moves toward its floor and carbs go up, on rest days the
//   reverse; each day's calories and protein are unchanged, and so are the week's fat and carbs;
//   a bigger session (sets, duration) moves more;
// - within a day: the pre-workout meal gets about 0.5–1 g/kg, the post-workout meal more, and more
//   again when the next session is less than ~24 h away; the rest go to the meals you prefer them in.
// Evidence: registry carbs.* and timing.* (the performance effect is modest outside long, high-volume
// sessions; Henselmans et al. 2022), so this is a preference inside the calories, never above them.

struct CarbDay: Equatable {
    var key: String
    var kcal: Double, protein: Double, fat: Double, carbs: Double
    var fatFloor: Double
    var carbFloor: Double
    var training: Bool
    var sessionFactor = 1.0       // 0.5 (short arm session) … 1.5 (long, high-volume leg day)
}

struct CarbSettings: Codable, Equatable {
    var dayShift = 0.3            // share of the gap between fat and its floor moved on an average training day (0 = off)
    var preGPerKg = 0.75          // pre-workout meal carbs (registry carbs.preWorkout.gPerKg, 0.5–1)
    var intra = false             // carbs during sessions over ~90 min
    var recoveryBoost = 0.35      // extra share for the post-workout meal when the next session is < 24 h away
}

struct MealCarbs: Equatable {
    var perSlot: [Int: Double]    // slot index → target carbs (g)
    var intra: Double             // during the session (g), 0 if off
    var recovery: Bool            // the next session is less than ~24 h after this one
    var reasons: [EngineReason]
}

enum CarbPlanner {
    // MARK: Between days

    /// The week's split: training days lower fat toward the floor and add the same calories as carbs;
    /// rest days take that fat back from their carbs (never below the carb floor). Each day keeps its
    /// calories and protein; the week keeps its fat and carbs. On a bulk or at maintenance, a day under
    /// 4 g/kg of carbs also moves fat toward its floor to reach it (calories unchanged).
    static func weekSplit(_ days: [CarbDay], settings: CarbSettings, phase: Phase, kg: Double) -> [CarbDay] {
        var out = days
        if phase != .cut {
            let want = Evidence.value("carbs.physique.gPerKg") * kg
            for i in out.indices where out[i].carbs < want {
                let move = min((want - out[i].carbs) * 4 / 9, max(0, out[i].fat - out[i].fatFloor))
                out[i].fat -= move; out[i].carbs += move * 9 / 4
            }
        }
        guard settings.dayShift > 0, out.contains(where: \.training), out.contains(where: { !$0.training }) else { return out }
        var drops = out.indices.map { i in out[i].training ? max(0, settings.dayShift * out[i].sessionFactor * (out[i].fat - out[i].fatFloor)) : 0 }
        let want = drops.reduce(0, +)
        let capacity = out.indices.filter { !out[$0].training }.map { max(0, out[$0].carbs - out[$0].carbFloor) * 4 / 9 }
        let total = capacity.reduce(0, +)
        guard want > 0, total > 0 else { return out }
        let scale = min(1, total / want)
        drops = drops.map { $0 * scale }
        let moved = drops.reduce(0, +)
        var r = 0
        for i in out.indices {
            if out[i].training {
                out[i].fat -= drops[i]; out[i].carbs += drops[i] * 9 / 4
            } else {
                let raise = moved * capacity[r] / total; r += 1
                out[i].fat += raise; out[i].carbs -= raise * 9 / 4
            }
        }
        return out
    }

    /// Session size against your average (working sets 60%, duration 40%), 0.5–1.5.
    static func sessionFactor(sets: Double, minutes: Double, averageSets: Double, averageMinutes: Double) -> Double {
        let s = averageSets > 0 ? sets / averageSets : 1, m = averageMinutes > 0 ? minutes / averageMinutes : 1
        return min(1.5, max(0.5, 0.6 * s + 0.4 * m))
    }

    // MARK: Within a day

    /// Carb targets per meal. `preference`: how much each meal usually takes (templates and your log; 1 = average).
    /// `hoursToNext`: from the end of today's session to the start of the next one (nil: none soon).
    /// `previousEndedHoursAgo`: yesterday's session ended this long before today's starts (recovery leading in).
    static func meals(dayCarbs: Double, slots: [PlanSlot], kg: Double, session: (start: Int, minutes: Int)?, factor: Double,
                      hoursToNext: Double?, previousEndedHoursAgo: Double? = nil, wake: Int, fasted: Bool,
                      preference: [Int: Double] = [:], settings: CarbSettings = CarbSettings()) -> MealCarbs {
        var reasons: [EngineReason] = []
        var left = max(0, dayCarbs)
        var per: [Int: Double] = [:]
        var intra = 0.0
        let recovery = (hoursToNext ?? 99) < Evidence.value("timing.recovery.within24h")
        let recoveryIn = (previousEndedHoursAgo ?? 99) < Evidence.value("timing.recovery.within24h")
        if let s = session {
            if settings.intra, Double(s.minutes) > Evidence.value("carbs.intra.minMinutes") {
                intra = min(dayCarbs * 0.2, 0.3 * kg * Double(s.minutes - 60) / 60)
                left -= intra
                reasons.append(.init(rule: "carbs during training", detail: "A \(s.minutes)-minute session: about \(Int(intra)) g of carbs during it (dates, banana or a sports drink).", evidence: ["carbs.intra.minMinutes"]))
            }
            // Before: about 0.5–1 g/kg, smaller when training early, none when fasted; never more than 40% of the day.
            if let pre = slots.firstIndex(where: { $0.kind == .preWorkout && !$0.fixed }) {
                let early = s.start - wake < 120
                let g = min(left * 0.4, kg * (early ? 0.35 : settings.preGPerKg) * min(1.2, max(0.8, factor)))
                per[slots[pre].index] = g; left -= g
                reasons.append(.init(rule: "before training", detail: early ? "An early session: a small, quick carb meal before (\(Int(g)) g: banana, rice cakes or dates)."
                                     : "About \(Int(g)) g of carbs (\(String(format: "%.1f", g / kg)) g/kg) 1–3 hours before, low in fat and fibre.",
                                     evidence: ["carbs.preWorkout.gPerKg", "timing.preWorkout.carbs", "timing.preWorkout.lowFatFibre"]))
            } else if fasted {
                reasons.append(.init(rule: "fasted training", detail: "Training fasted: the meal after carries more of the day's carbs.", evidence: ["timing.fastedTraining"]))
            }
        }
        // The rest by weight: your preferred carb meals; the meal after training more, and more again
        // (with the meals after it) when the next session is less than a day away.
        var weights: [Int: Double] = [:]
        let end = session.map { $0.start + $0.minutes } ?? 0
        for s in slots where per[s.index] == nil && !s.fixed {
            var w = preference[s.index] ?? 1
            if s.kind == .postWorkout { w *= 1.5 * (fasted ? 1.3 : 1) * min(1.3, max(0.8, factor)) + (recovery ? settings.recoveryBoost * 4 : 0) }
            else if recovery, session != nil, s.minute > end { w *= 1.3 }
            if recoveryIn, let st = session?.start, s.minute < st { w *= 1.3 }
            weights[s.index] = w
        }
        let sum = weights.values.reduce(0, +)
        for (i, w) in weights { per[i] = sum > 0 ? left * w / sum : 0 }
        if recovery, let h = hoursToNext {
            reasons.append(.init(rule: "recovery window", detail: "The next session is \(Int(h.rounded())) h after this one, so the meal after training and the ones after it get more carbs to refill glycogen (within today's calories).",
                                 evidence: ["timing.recovery.within24h", "timing.glycogen.hours"]))
        }
        if recoveryIn, let h = previousEndedHoursAgo {
            reasons.append(.init(rule: "back-to-back sessions", detail: "Yesterday's session ended \(Int(h.rounded())) h before this one: the meals before it lean carb-heavy.", evidence: ["timing.recovery.within24h"]))
        }
        return MealCarbs(perSlot: per, intra: intra, recovery: recovery, reasons: reasons)
    }

    /// Daily carbs per kg against the range for your phase (a reference on a cut, a target otherwise).
    static func range(_ phase: Phase) -> (range: ClosedRange<Double>, id: String, target: Bool) {
        phase == .cut ? (Evidence.entry("carbs.cut.gPerKg")!.range, "carbs.cut.gPerKg", false)
                      : (Evidence.entry("carbs.physique.gPerKg")!.range, "carbs.physique.gPerKg", true)
    }
}
