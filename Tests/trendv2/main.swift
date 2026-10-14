// Weight trend V2 against V1 on simulated weigh-ins: closer to the true weight, and less lag.
import Foundation
var fails = 0
func check(_ n: String, _ ok: Bool, _ got: Any = "") { print(ok ? "ok   \(n)" : "FAIL \(n) got \(got)"); if !ok { fails += 1 } }
struct LCG { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }
var edge1 = 0.0, edge2 = 0.0
var rmse1 = 0.0, rmse2 = 0.0, lag1 = 0.0, lag2 = 0.0, runs = 0
for seed in 1...200 {
    var r = LCG(s: UInt64(seed) * 7919)
    func noise() -> Double { (0..<6).reduce(0) { a, _ in a + r.next() } - 3 }   // roughly normal, sd ~0.7
    let start = "2026-01-01"
    // truth: flat 2 weeks, then losing 0,07 kg/day for 6 weeks, then flat
    var truth: [Double] = []
    var w = 85.0
    for d in 0..<70 { if d >= 14 && d < 56 { w -= 0.07 }; truth.append(w) }
    var weights: [DayValue] = []
    for d in 0..<70 where r.next() < 0.8 {                       // 80% of days weighed
        var v = truth[d] + noise() * 0.6
        if r.next() < 0.05 { v += 1.5 }                          // occasional salty-dinner outlier
        weights.append(DayValue(day: addDays(start, d), value: v))
    }
    let s1 = trendSeriesV1(weights, through: addDays(start, 69)), s2 = robustTrend(s1)
    guard s1.count == 70 else { continue }
    let off = daysBetween(start, s1[0].day)
    for i in 7..<s1.count {
        let t = truth[i + off]
        rmse1 += pow(s1[i].trend - t, 2); rmse2 += pow(s2[i].trend - t, 2)
    }
    // lag: how far the trend is from the truth at the end of the losing phase (day 55)
    let k = 55 - off
    lag1 += abs(s1[k].trend - truth[55]); lag2 += abs(s2[k].trend - truth[55])
    // the newest value, mid-cut (as you'd see it on day 40): only past weigh-ins available
    let cut = s1.filter { $0.day <= addDays(start, 40) }
    if cut.count > 10 { edge1 += abs(cut.last!.trend - truth[40]); edge2 += abs(robustTrend(cut).last!.trend - truth[40]) }
    runs += 1
}
let n = Double(runs)
print(String(format: "  error  V1 %.3f kg  V2 %.3f kg", sqrt(rmse1 / (n * 60)), sqrt(rmse2 / (n * 60))))
print(String(format: "  lag    V1 %.3f kg  V2 %.3f kg (end of the cut)", lag1 / n, lag2 / n))
print(String(format: "  today  V1 %.3f kg  V2 %.3f kg (newest value, mid-cut)", edge1 / n, edge2 / n))
check("V2's newest value is no worse than V1's", edge2 <= edge1)
check("V2 closer to the true weight overall", rmse2 < rmse1)
check("V2 lags less at the end of a cut", lag2 < lag1)
let flat = (0..<30).map { DayValue(day: addDays("2026-03-01", $0), value: 80 + ($0 == 10 ? 3 : 0)) }
let f2 = robustTrend(trendSeriesV1(flat))
check("one big outlier barely moves V2", f2.allSatisfy { abs($0.trend - 80) < 0.15 }, f2.map(\.trend).max() ?? 0)
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
