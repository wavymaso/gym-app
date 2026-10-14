// Expenditure engines compared on simulated people (truth known): V1, its variants, and V2 (joint).
// Each person: a starting estimate off by up to ±500 kcal, expenditure that changes (adaptation,
// a new job, more steps), intake logged on ~85% of days with some partial-logging days, weigh-ins
// on ~75% of days with water swings that persist for days, and the odd big outlier.
import Foundation
setvbuf(stdout, nil, _IONBF, 0)
struct LCG { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
    mutating func normal() -> Double { (0..<12).reduce(0) { a, _ in a + next() } - 6 } }
let people = Int(CommandLine.arguments.dropFirst().first ?? "300") ?? 300
var err: [String: [Double]] = [:], late: [String: [Double]] = [:], step: [String: [Double]] = [:]
for p in 0..<people {
    var r = LCG(s: UInt64(p + 1) * 104729)
    let days = 112, start = "2026-01-05"
    var trueE: [Double] = []
    var e = 2300 + r.normal() * 300
    let changeDay = 40 + Int(r.next() * 30), change = (r.next() - 0.5) * 700     // a real change in expenditure
    for d in 0..<days {
        e += r.normal() * 5                                       // slow wander
        if d == changeDay { e += change }
        trueE.append(e)
    }
    var intake: [String: Double] = [:], weights: [DayValue] = []
    var mass = 80 + r.normal() * 10, water = 0.0
    let plan = trueE[0] + (r.next() - 0.6) * 900                  // eats around a plan (deficit or surplus)
    for d in 0..<days {
        let ate = plan + r.normal() * 350
        mass += (ate - trueE[d]) / 7700
        water = 0.8 * water + r.normal() * 0.36
        let key = addDays(start, d)
        if r.next() < 0.85 { intake[key] = r.next() < 0.08 ? ate * (0.55 + r.next() * 0.3) : ate }   // some partial logs
        if r.next() < 0.75 {
            var y = mass + water + r.normal() * 0.15
            if r.next() < 0.03 { y += (r.next() < 0.5 ? -1 : 1) * 1.8 }
            weights.append(DayValue(day: key, value: y))
        }
    }
    let initial = trueE[0] + (r.next() - 0.5) * 1000              // formula error
    let end = addDays(start, days - 1)
    var runs: [(String, [ExpenditurePoint])] = []
    for a in [ExpenditureAlgorithm.standard, .responsive, .stable] {
        runs.append((a.rawValue, expenditureSeries(start: start, end: end, initial: initial, intake: intake, weights: weights, settings: a.v1Settings)))
    }
    runs.append(("joint", jointExpenditure(start: start, end: end, initial: initial, intake: intake, weights: weights)))
    for (name, s) in runs where s.count == days {
        let e21 = (21..<days).map { abs(s[$0].kcal - trueE[$0]) }
        err[name, default: []].append(e21.reduce(0, +) / Double(e21.count))
        late[name, default: []].append(abs(s[days - 1].kcal - trueE[days - 1]))
        let k = min(days - 1, changeDay + 21)                     // 3 weeks after the real change
        step[name, default: []].append(abs(s[k].kcal - trueE[k]))
    }
}
func avg(_ x: [Double]) -> Double { x.reduce(0, +) / Double(x.count) }
func pct(_ x: [Double], _ q: Double) -> Double { let s = x.sorted(); return s[Int(Double(s.count - 1) * q)] }
print("engine        mean error   90th pct   final day   3 wk after a change")
for n in ["standard", "responsive", "stable", "joint"] {
    print(String(format: "%-12@ %8.0f %10.0f %11.0f %14.0f   kcal", n as NSString, avg(err[n]!), pct(err[n]!, 0.9), avg(late[n]!), avg(step[n]!)))
}
let better = avg(err["joint"]!) < avg(err["standard"]!) && avg(step["joint"]!) < avg(step["standard"]!)
print(better ? "joint model is better" : "joint model is NOT better")
exit(better ? 0 : 1)
