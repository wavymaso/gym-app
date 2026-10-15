import Foundation
import SwiftData

// Backtest on your own history: every week, take each method's expenditure estimate and predict
// the trend weight 4 weeks later from what you actually ate. How far off was it?
// Usage: run.sh <copy of default.store> <mf-expenditure.csv>
let args = CommandLine.arguments
let container = try! ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(url: URL(fileURLWithPath: args[1])))
let ctx = ModelContext(container)
let intake = ctx.dailyIntake()
let weights = ctx.weightValues
let start = ctx.expenditureStart!
let end = dayKey()
var mf: [String: Double] = [:]
for line in (try! String(contentsOfFile: args[2], encoding: .utf8)).split(separator: "\n") {
    let p = line.split(separator: ","); if p.count == 2, let v = Double(p[1]) { mf[String(p[0])] = v }
}
let truthV2 = Dictionary(trendSeries(weights, through: end).map { ($0.day, $0.trend) }, uniquingKeysWith: { a, _ in a })
print("data: \(weights.count) weigh-ins, \(intake.count) logged days, from \(start.day) (start \(Int(start.kcal)) kcal)")

func series(_ s: JointSettings) -> [String: Double] {
    Dictionary(jointExpenditure(start: start.day, end: end, initial: start.kcal, intake: intake, weights: weights, settings: s).map { ($0.day, $0.kcal) },
               uniquingKeysWith: { a, _ in a })
}
var methods: [(String, [String: Double], Double, Double)] = []      // name, series, gain density, loss density
methods.append(("Ours (V2, 7700/7700)", series(JointSettings()), 7700, 7700))
for (g, l) in [(6000.0, 7700.0), (5000, 7700), (4000, 7700), (6000, 7000)] {
    var s = JointSettings(); s.gainDensity = g; s.lossDensity = l
    methods.append(("Ours gain \(Int(g)) / loss \(Int(l))", series(s), g, l))
}
methods.append(("V1 (regression)", v1, 7700, 7700))
methods.append(("MacroFactor", mf, 7700, 7700))

let v1 = Dictionary(expenditureSeries(start: start.day, end: end, initial: start.kcal, intake: intake, weights: weights).map { ($0.day, $0.kcal) },
                    uniquingKeysWith: { a, _ in a })
func score(_ e: [String: Double], from: String, to: String) -> (Double, Double, Int) {
    var errs: [Double] = []
    for a in stride(from: dayNumber(start.day) + 56, through: dayNumber(end) - 28, by: 7).map({ dayKey(number: $0) }) where a >= from && a < to {
        guard let E = e[a], let t0 = truthV2[a], let t1 = truthV2[addDays(a, 28)] else { continue }
        guard (1...28).compactMap({ intake[addDays(a, $0)] }).count >= 20 else { continue }
        let pred = (1...28).reduce(0.0) { acc, k in intake[addDays(a, k)].map { acc + ($0 - E) / 7700 } ?? acc }
        errs.append(pred - (t1 - t0))
    }
    return (errs.map(abs).reduce(0, +) / Double(max(errs.count, 1)), errs.reduce(0, +) / Double(max(errs.count, 1)), errs.count)
}
if ProcessInfo.processInfo.environment["GRID"] != nil {
    let all = days(from: start.day, through: end)
    let split = all[all.count * 2 / 3]
    print("train < \(split) ≤ test")
    var rows: [(Double, Double, String)] = []
    for drift in [6.0, 10, 15, 20, 26] {
        for water in [0.4, 0.6, 0.9] {
            for scale in [0.15, 0.3] {
                for unlogged in [0.09, 0.2] {
                    var s = JointSettings(); s.expenditureDrift = drift; s.waterSD = water; s.scaleNoise = scale; s.unloggedMass = unlogged
                    let e = series(s)
                    let tr = score(e, from: "0", to: split), te = score(e, from: split, to: "9")
                    rows.append((tr.0, te.0, "drift \(drift) water \(water) scale \(scale) unlogged \(unlogged)  test bias \(String(format: "%+.2f", te.1))"))
                }
            }
        }
    }
    for r in rows.sorted(by: { $0.0 < $1.0 }).prefix(8) { print(String(format: "train %.2f  test %.2f  ", r.0, r.1), r.2) }
    let base = series(JointSettings())
    print(String(format: "current: train %.2f test %.2f", score(base, from: "0", to: split).0, score(base, from: split, to: "9").0))
    print(String(format: "V1:      train %.2f test %.2f", score(v1, from: "0", to: split).0, score(v1, from: split, to: "9").0))
    print(String(format: "MF:      train %.2f test %.2f", score(mf, from: "0", to: split).0, score(mf, from: split, to: "9").0))
    exit(0)
}
if ProcessInfo.processInfo.environment["MFCMP"] != nil {
    func mae(_ e: [String: Double], from: String) -> String {
        let ds = mf.keys.filter { $0 >= from && $0 < end && e[$0] != nil }
        let errs = ds.map { abs(e[$0]! - mf[$0]!) }
        return String(format: "%4.0f (n %d)", errs.reduce(0,+)/Double(max(errs.count,1)), errs.count)
    }
    let j = series(JointSettings())
    var jv1 = JointSettings(); jv1.waterSD = 0.6; jv1.unloggedMass = 0.09
    let cl = Dictionary(classicExpenditure(start: start.day, end: end, initial: start.kcal, intake: intake, weights: weights).map { ($0.day, $0.kcal) }, uniquingKeysWith: { x, _ in x })
    let algos: [(String, [String: Double])] = [("classic", cl), ("joint (now)", j), ("joint old", series(jv1)), ("V1 standard", v1)] +
        ExpenditureAlgorithm.allCases.filter { $0 != .joint && $0 != .classic }.map { a in ("V1 \(a.rawValue)", Dictionary(expenditureSeries(start: start.day, end: end, initial: start.kcal, intake: intake, weights: weights, settings: a.v1Settings).map { ($0.day, $0.kcal) }, uniquingKeysWith: { x, _ in x })) }
    for (n, e) in algos { print(n.padding(toLength: 16, withPad: " ", startingAt: 0), "since 2025:", mae(e, from: "2025-01-01"), " since Jul 26:", mae(e, from: "2026-07-01")) }
    for d in ["2026-09-01","2026-09-15","2026-10-01","2026-10-13"] { print(d, "MF", Int(mf[d] ?? 0), algos.map { "\($0.0.prefix(8)) \(Int($0.1[d] ?? 0))" }.joined(separator: "  ")) }
    exit(0)
}
let anchors = stride(from: dayNumber(start.day) + 56, through: dayNumber(end) - 28, by: 7).map { dayKey(number: $0) }
print("anchors: \(anchors.count) weeks\n")
print("method".padding(toLength: 30, withPad: " ", startingAt: 0), "MAE kg", " bias kg", " ≈kcal/day", " n")
for (name, e, g, l) in methods {
    var errs: [Double] = []
    for a in anchors {
        guard let E = e[a], let t0 = truthV2[a], let t1 = truthV2[addDays(a, 28)] else { continue }
        let logged = (1...28).compactMap { intake[addDays(a, $0)] }
        guard logged.count >= 20 else { continue }               // need the intake to know what happened
        let pred = (1...28).reduce(0.0) { acc, k in
            guard let I = intake[addDays(a, k)] else { return acc }
            return acc + (I - E) / (I >= E ? g : l)
        }
        errs.append(pred - (t1 - t0))
    }
    let mae = errs.map(abs).reduce(0, +) / Double(max(errs.count, 1))
    let bias = errs.reduce(0, +) / Double(max(errs.count, 1))
    print(name.padding(toLength: 30, withPad: " ", startingAt: 0), String(format: "%6.2f  %+6.2f   %6.0f   %d", mae, bias, mae * 7700 / 28, errs.count))
}
// Today's estimates
for (name, e, _, _) in methods { if let k = e.keys.max() { print("today", name, Int(e[k] ?? 0), "(\(k))") } }
