import Foundation

// Expenditure from energy balance: what you ate, minus the energy stored or released by the change
// in true mass (the trend, water removed). How much energy a kilo holds depends on how much of it is
// lean, which depends on fat mass (Forbes; Hall 2008 energy densities). It starts from a formula
// prior and hands over to the data as good weeks accumulate; it can't move faster than a weekly
// limit, and says when that limit applied.

struct EnergySettings: Equatable {
    var window = 21                    // days of intake averaged (weekly patterns cancel out)
    var minLoggedShare = 0.5           // fewer logged days in the window: hold the estimate
    var priorSD = 350.0                // kcal: how far off the formula prior may be
    var driftPerDay = 25.0             // kcal sd/day: how fast true expenditure can wander
    var maxWeeklyChange = 200.0        // kcal per 7 days, hard limit
    var fixedDensity: Double? = nil    // kcal/kg: use one number (e.g. 5 500, the fitted baseline) instead of Forbes
    var stepAdjustment = false         // short-term: this week's steps vs your 4-week baseline (the long run stays on energy balance)
}

struct ExpenditureEstimate: Equatable {
    var day: String
    var kcal: Double
    var sd: Double                     // kcal, 1 sd: narrows as data accumulates
    var held: Bool                     // not enough logged days: carried forward
    var limited: Bool                  // the weekly limit applied today
    var density: Double                // kcal/kg used today
    var stepAdjustment: Double = 0     // kcal added for steps above (or below) your baseline, already in kcal
}

enum EngineEnergy {
    /// Forbes: the lean share of a small change in weight, from fat mass (kg).
    static func leanShare(fatMass: Double) -> Double { 10.4 / (10.4 + max(fatMass, 0.5)) }

    /// kcal per kg of weight change at this fat mass (registry: energy.fat, energy.lean).
    static func density(fatMass: Double) -> Double {
        let p = leanShare(fatMass: fatMass)
        return p * Evidence.value("energy.lean.kcalPerKg") + (1 - p) * Evidence.value("energy.fat.kcalPerKg")
    }

    static func run(_ days: [EngineDay], trend: [TrendPoint], prior: Double, body: BodyComposition,
                    _ s: EnergySettings = EnergySettings()) -> [ExpenditureEstimate] {
        let tmap = Dictionary(trend.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        var e = prior, variance = s.priorSD * s.priorSD
        var out: [ExpenditureEstimate] = []
        var recent: [Double] = []                                         // last 7 days' estimates (for the weekly limit)
        for i in 0..<days.count {
            variance += s.driftPerDay * s.driftPerDay
            var held = true, limited = false
            var rho = s.fixedDensity ?? 7700
            if i >= s.window - 1, let t1 = tmap[days[i].key], let t0 = tmap[days[i - s.window + 1].key] {
                let logged = days[(i - s.window + 1)...i].compactMap(\.intake)
                if Double(logged.count) >= Double(s.window) * s.minLoggedShare {
                    rho = s.fixedDensity ?? density(fatMass: body.fatMass(weight: t1.trend))
                    let avg = logged.reduce(0, +) / Double(logged.count)
                    let stored = rho * (t1.trend - t0.trend) / Double(s.window - 1)
                    let observed = avg - stored
                    // How noisy that is: the trend's uncertainty at both ends, and the intake average's.
                    let massSD = (t1.sd * t1.sd + t0.sd * t0.sd).squareRoot() * rho / Double(s.window - 1)
                    let intakeSD = 350 / Double(logged.count).squareRoot()
                    let evidenceVar = (massSD * massSD + intakeSD * intakeSD) * 6          // overlapping windows: count each less
                    let gain = variance / (variance + evidenceVar)
                    var next = e + gain * (observed - e)
                    if let weekAgo = recent.first {
                        let lo = weekAgo - s.maxWeeklyChange, hi = weekAgo + s.maxWeeklyChange
                        if next < lo || next > hi { next = min(max(next, lo), hi); limited = true }
                    }
                    e = next
                    variance *= (1 - gain)
                    held = false
                }
            }
            recent.append(e); if recent.count > 7 { recent.removeFirst() }
            var adj = 0.0
            if s.stepAdjustment, let w = tmap[days[i].key]?.trend {
                func avg(_ r: ClosedRange<Int>) -> Double? {
                    let v = r.compactMap { $0 >= 0 && $0 < days.count ? days[$0].steps : nil }
                    return v.count >= r.count / 2 ? v.reduce(0, +) / Double(v.count) : nil
                }
                if let now = avg((i - 6)...i), let base = avg((i - 34)...(i - 7)) {
                    adj = (now - base) * Evidence.value("steps.kcalPerStepPerKg") * w
                    adj = max(-300, min(300, adj))
                }
            }
            out.append(ExpenditureEstimate(day: days[i].key, kcal: e + adj, sd: variance.squareRoot(), held: held, limited: limited, density: rho, stepAdjustment: adj))
        }
        return out
    }
}
