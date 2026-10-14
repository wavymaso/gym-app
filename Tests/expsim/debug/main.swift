import Foundation
// One clean person: constant true expenditure 2500, eats 2000 logged exactly every day, weighed daily with mild noise.
var intake: [String: Double] = [:], weights: [DayValue] = []
var mass = 80.0
let start = "2026-01-05"
var s: UInt64 = 7
func rnd() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) - 0.5 }
for d in 0..<84 {
    let key = addDays(start, d)
    intake[key] = 2000
    weights.append(DayValue(day: key, value: mass + rnd() * 0.6))
    mass += (2000 - 2500) / 7700
}
let j = jointExpenditure(start: start, end: addDays(start, 83), initial: 2100, intake: intake, weights: weights)
let v1 = expenditureSeries(start: start, end: addDays(start, 83), initial: 2100, intake: intake, weights: weights)
for d in stride(from: 0, to: 84, by: 7) { print(d, "joint", Int(j[d].kcal), "v1", Int(v1[d].kcal), "truth 2500") }
