// Tunes JointSettings on 150 simulated people, then checks the best on 300 different ones.
import Foundation
setvbuf(stdout, nil, _IONBF, 0)
struct LCG { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
    mutating func normal() -> Double { (0..<12).reduce(0) { a, _ in a + next() } - 6 } }
struct Person { var trueE: [Double]; var intake: [String: Double]; var weights: [DayValue]; var initial: Double; var changeDay: Int }
let days = 112, start = "2026-01-05", end = addDays("2026-01-05", 111)
func person(_ p: Int) -> Person {
    var r = LCG(s: UInt64(p + 1) * 104729)
    var trueE: [Double] = []; var e = 2300 + r.normal() * 300
    let changeDay = 40 + Int(r.next() * 30), change = (r.next() - 0.5) * 700
    for d in 0..<days { e += r.normal() * 5; if d == changeDay { e += change }; trueE.append(e) }
    var intake: [String: Double] = [:], weights: [DayValue] = []
    var mass = 80 + r.normal() * 10, water = 0.0
    let plan = trueE[0] + (r.next() - 0.6) * 900
    for d in 0..<days {
        let ate = plan + r.normal() * 350
        mass += (ate - trueE[d]) / 7700; water = 0.8 * water + r.normal() * 0.36
        let key = addDays(start, d)
        if r.next() < 0.85 { intake[key] = r.next() < 0.08 ? ate * (0.55 + r.next() * 0.3) : ate * (1 + r.normal() * 0.05) }
        if r.next() < 0.75 { var y = mass + water + r.normal() * 0.15; if r.next() < 0.03 { y += (r.next() < 0.5 ? -1 : 1) * 1.8 }; weights.append(DayValue(day: key, value: y)) }
    }
    return Person(trueE: trueE, intake: intake, weights: weights, initial: trueE[0] + (r.next() - 0.5) * 1000, changeDay: changeDay)
}
func score(_ s: [ExpenditurePoint], _ p: Person) -> (Double, Double) {
    let e = (21..<days).map { abs(s[$0].kcal - p.trueE[$0]) }
    let k = min(days - 1, p.changeDay + 21)
    return (e.reduce(0, +) / Double(e.count), abs(s[k].kcal - p.trueE[k]))
}
let tune = (0..<150).map { person($0 + 10_000) }, test = (0..<300).map(person)
func evalJoint(_ js: JointSettings, _ ps: [Person]) -> (Double, Double) {
    var a = 0.0, b = 0.0
    for p in ps { let (x, y) = score(jointExpenditure(start: start, end: end, initial: p.initial, intake: p.intake, weights: p.weights, settings: js), p); a += x; b += y }
    return (a / Double(ps.count), b / Double(ps.count))
}
var best: (JointSettings, Double)? = nil
for drift in [10.0, 18, 26] { for mn in [0.005, 0.01, 0.02] { for wp in [0.5, 0.7, 0.85] { for su in [350.0, 700] { for z in [2.5, 3.5] {
    var js = JointSettings(); js.expenditureDrift = drift; js.massNoise = mn; js.waterPersistence = wp; js.startUncertainty = su; js.outlierZ = z
    let (e, c) = evalJoint(js, tune)
    let sc = e + 0.5 * c
    if best == nil || sc < best!.1 { best = (js, sc); print(String(format: "  drift %4.0f mass %.3f water %.2f start %4.0f z %.1f -> mean %.0f, after change %.0f", drift, mn, wp, su, z, e, c)) }
}}}}}
let js = best!.0
var a = 0.0, b = 0.0
for p in test { let (x, y) = score(expenditureSeries(start: start, end: end, initial: p.initial, intake: p.intake, weights: p.weights), p); a += x; b += y }
let (je, jc) = evalJoint(js, test)
print(String(format: "TEST (300 new people): V1 mean %.0f / after change %.0f   joint mean %.0f / after change %.0f", a / 300, b / 300, je, jc))
