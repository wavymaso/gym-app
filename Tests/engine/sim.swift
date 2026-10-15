import Foundation
// A body simulator that is NOT the engine's model: fat and lean tissue tracked separately (Forbes
// partitioning at each day's fat mass), glycogen with its water (3 g/g), creatine water, sodium
// water, and noisy weigh-ins taken at varying times. The engine only sees intake and the scale.

struct Rng {
    var s: UInt64
    mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
    mutating func normal() -> Double { let u = max(next(), 1e-12), v = next(); return (-2 * log(u)).squareRoot() * cos(2 * .pi * v) }
}

struct SimDay { var day: EngineDay; var trueMass: Double; var trueExpenditure: Double }

struct Simulator {
    var fat = 18.0, lean = 72.0, glycogen = 0.45        // kg
    var water = 0.0                                      // kg of non-glycogen extra water (sodium, creatine)
    var expenditure = 2900.0
    var rng = Rng(s: 42)
    var scaleOffset = 0.0
    var weighInChance = 0.85, logChance = 0.95

    var mass: Double { fat + lean + glycogen * 4 + water }     // glycogen plus its 3 g water per g

    /// One day: what you ate (kcal), extra carbs (g, refeed), sodium (true/false), and creatine.
    mutating func step(_ i: Int, intake: Double, extraCarbs: Double = 0, salty: Bool = false, creatine: Bool = false,
                       logged: Bool? = nil, tag: Set<WaterEvent> = []) -> SimDay {
        // Glycogen: refills with extra carbs (up to 0.8 kg), drifts back to 0.45.
        glycogen += min(extraCarbs / 1000, 0.8 - glycogen) - (glycogen - 0.45) * 0.3
        water *= 0.7
        if salty { water += 0.6 }
        if creatine { water += 0.12 }                     // loading: builds to ~0.75 kg over a week…
        if creatine { water = min(water, 0.9) }
        let balance = intake - expenditure
        let fm = fat
        let p = 10.4 / (10.4 + fm)
        let rho = p * 1816 + (1 - p) * 9440
        let dm = balance / rho
        lean += p * dm; fat += (1 - p) * dm
        let y = mass + scaleOffset + rng.normal() * 0.35 + (rng.next() < 0.03 ? 1.5 : 0)
        let weigh = rng.next() < weighInChance
        let log = logged ?? (rng.next() < logChance)
        return SimDay(day: EngineDay(key: String(format: "d%04d", i), weighIns: weigh ? [y] : [], intake: log ? intake * (1 + rng.normal() * 0.05) : nil, events: tag),
                      trueMass: fat + lean + 0.45 * 4, trueExpenditure: expenditure)
    }
}
