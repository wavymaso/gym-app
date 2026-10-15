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
if ProcessInfo.processInfo.environment["TREND"] != nil {
    // Trend filters compared on forecasting: from each day's state, predict the mean of the actual
    // weigh-ins 1–4 weeks later (±3 days). Train/test split at two thirds.
    let all = days(from: weights.first!.day, through: end)
    let events = ctx.waterEvents(from: all.first!, to: end)
    let wmap = Dictionary(weights.map { ($0.day, $0.value) }, uniquingKeysWith: { a, _ in a })
    let edays = all.map { d in EngineDay(key: d, weighIns: wmap[d].map { [$0] } ?? [], intake: intake[d], events: events.contains(d) ? [.tagged] : []) }
    let split = all[all.count * 2 / 3]
    func target(_ d: String) -> Double? {
        let v = (-3...3).compactMap { wmap[addDays(d, $0)] }
        return v.count >= 2 ? v.reduce(0, +) / Double(v.count) : nil
    }
    // Current: the EMA trend; its slope over the last 14 days (or none).
    let ema = trendSeriesV1(weights, through: end)
    let emaMap = Dictionary(ema.map { ($0.day, $0.trend) }, uniquingKeysWith: { a, _ in a })
    func evalForecast(_ name: String, _ f: (String, Int) -> Double?) {
        var line = name.padding(toLength: 34, withPad: " ", startingAt: 0)
        for (lo, hi, label) in [("0", split, "train"), (split, "9", "test")] {
            var cells: [String] = []
            for wk in 1...4 {
                var errs: [Double] = []
                for (i, d) in all.enumerated() where i % 3 == 0 && d >= lo && d < hi && i > 30 {
                    guard wmap[d] != nil, let p = f(d, wk * 7), let t = target(addDays(d, wk * 7)) else { continue }
                    errs.append(abs(p - t))
                }
                cells.append(String(format: "%.2f", errs.reduce(0, +) / Double(max(errs.count, 1))))
            }
            line += " \(label) " + cells.joined(separator: "/")
        }
        print(line)
    }
    print("forecast MAE (kg) at 1/2/3/4 weeks")
    evalForecast("current EMA, level only") { d, _ in emaMap[d] }
    evalForecast("current EMA + 14-day slope") { d, h in
        guard let a = emaMap[d], let b = emaMap[addDays(d, -14)] else { return nil }
        return a + (a - b) / 14 * Double(h)
    }
    func kalman(_ s: TrendSettings, events useEvents: Bool = true) -> [String: TrendPoint] {
        let input = useEvents ? edays : edays.map { var x = $0; x.events = []; return x }
        return Dictionary(EngineTrend.run(input, s).map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
    }
    var best: (Double, TrendSettings)? = nil
    var cands: [(Double, Double, TrendSettings)] = []
    if ProcessInfo.processInfo.environment["TUNE"] != nil {
        for mn in [0.005, 0.01, 0.02] { for rn in [0.0005, 0.001, 0.002, 0.004] { for ws in [0.4, 0.6, 0.9] { for ph in [0.5, 0.75] { for sn in [0.3, 0.5] {
            var s = TrendSettings(); s.massNoise = mn; s.rateNoise = rn; s.waterSD = ws; s.waterPersistence = ph; s.scaleNoise = sn
            let tl = EngineTrend.run(edays.filter { $0.key < split }, s)
            let jumps = zip(tl.dropFirst(14), tl.dropFirst(15)).filter { $0.0.weighed && $0.1.weighed }.map { abs($1.trend - $0.trend) }.sorted()
            guard !jumps.isEmpty else { continue }
            let j99 = jumps[jumps.count * 99 / 100]
            let k = kalman(s)
            var errs: [Double] = []
            for (i, d) in all.enumerated() where i % 3 == 0 && d < split && i > 30 {
                guard wmap[d] != nil, let p = k[d] else { continue }
                for wk in 1...4 { if let t = target(addDays(d, wk * 7)) { errs.append(abs(p.trend + p.ratePerWeek / 7 * Double(wk * 7) - t)) } }
            }
            let m = errs.reduce(0, +) / Double(max(errs.count, 1))
            cands.append((m, j99, s))
            if j99 <= 0.3, best == nil || m < best!.0 { best = (m, s) }
        } } } } }
        for c in cands.sorted(by: { $0.1 < $1.1 }).prefix(6) { print(String(format: "  jump99 %.2f train err %.2f", c.1, c.0), c.2) }
        for c in cands.sorted(by: { $0.0 < $1.0 }).prefix(4) { print(String(format: "  best err %.2f jump99 %.2f", c.0, c.1), c.2) }
        print("tuned on train:", best.map { "\($0.1)" } ?? "none under 0.3")
    }
    let ks = best?.1 ?? TrendSettings()
    let k = kalman(ks)
    evalForecast("Kalman, level only") { d, _ in k[d]?.trend }
    evalForecast("Kalman + rate") { d, h in k[d].map { $0.trend + $0.ratePerWeek / 7 * Double(h) } }
    evalForecast("Kalman + half rate (damped)") { d, h in k[d].map { $0.trend + $0.ratePerWeek / 7 * Double(h) * 0.5 } }
    for (rn, sn) in [(0.001, 0.3), (0.0015, 0.3), (0.002, 0.25), (0.001, 0.4)] {
        var v = ks; v.rateNoise = rn; v.scaleNoise = sn
        let kv = kalman(v)
        if ProcessInfo.processInfo.environment["TUNE"] != nil { continue }
        evalForecast("Kalman rate \(rn) scale \(sn)") { d, h in kv[d].map { $0.trend + $0.ratePerWeek / 7 * Double(h) } }
        let tl = EngineTrend.run(edays, v)
        let jumps = zip(tl.dropFirst(14), tl.dropFirst(15)).filter { $0.0.weighed && $0.1.weighed }.map { abs($1.trend - $0.trend) }.sorted()
        print("   between consecutive weigh-in days: max \(String(format: "%.2f", jumps.last ?? 0)) kg, 99th pct \(String(format: "%.2f", jumps[jumps.count * 99 / 100]))")
    }
    let kn = kalman(ks, events: false)
    evalForecast("Kalman without event tags") { d, h in kn[d].map { $0.trend + $0.ratePerWeek / 7 * Double(h) * 0.5 } }
    // Expenditure: Forbes/Hall density vs the fitted 5 500 kcal/kg baseline. Score: from each day, predict
    // the weigh-in mean 4 weeks later from the Kalman trend + logged intake − estimate, at each method's density.
    let bodyAssumed = BodyComposition()
    func energy(_ fixed: Double?) -> [String: ExpenditureEstimate] {
        var es = EnergySettings(); es.fixedDensity = fixed
        let r = EngineEnergy.run(edays, trend: EngineTrend.run(edays, ks), prior: start.kcal, body: bodyAssumed, es)
        return Dictionary(r.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
    }
    let classic = Dictionary(classicExpenditure(start: start.day, end: end, initial: start.kcal, intake: intake, weights: weights).map { ($0.day, $0.kcal) }, uniquingKeysWith: { a, _ in a })
    for (name, fixed) in [("engine, Forbes density (20% BF assumed)", nil as Double?), ("engine, fixed 5 500 (baseline)", 5500), ("engine, fixed 7 700", 7700)] {
        let e = energy(fixed)
        for (lo, hi, label) in [("0", split, "train"), (split, "9", "test")] {
            var errs: [Double] = [], mfErr: [Double] = []
            for (i, d) in all.enumerated() where i % 3 == 0 && d >= lo && d < hi && i > 60 {
                if let m = mf[d], let x = e[d] { mfErr.append(abs(x.kcal - m)) }
                guard let x = e[d], let tp = k[d], let t = target(addDays(d, 28)) else { continue }
                guard (1...28).compactMap({ intake[addDays(d, $0)] }).count >= 20 else { continue }
                let pred = tp.trend + (1...28).reduce(0.0) { acc, j in intake[addDays(d, j)].map { acc + ($0 - x.kcal) / x.density } ?? acc }
                errs.append(abs(pred - t))
            }
            print(name.padding(toLength: 40, withPad: " ", startingAt: 0), label, String(format: "4-wk weight error %.2f kg (n %d) · vs MacroFactor %.0f kcal", errs.reduce(0, +) / Double(max(errs.count, 1)), errs.count, mfErr.reduce(0, +) / Double(max(mfErr.count, 1))))
        }
    }
    for (lo, hi, label) in [("0", split, "train"), (split, "9", "test")] {
        var errs: [Double] = []
        for (i, d) in all.enumerated() where i % 3 == 0 && d >= lo && d < hi && i > 60 {
            guard let c = classic[d], let tp = emaMap[d], let t = target(addDays(d, 28)) else { continue }
            guard (1...28).compactMap({ intake[addDays(d, $0)] }).count >= 20 else { continue }
            errs.append(abs(tp + (1...28).reduce(0.0) { acc, j in intake[addDays(d, j)].map { acc + ($0 - c) / 5500 } ?? acc } - t))
        }
        print("current classic (5 500, EMA trend)      ", label, String(format: "4-wk weight error %.2f kg (n %d)", errs.reduce(0, +) / Double(max(errs.count, 1)), errs.count))
    }
    var cErr: [Double] = []
    for (i, d) in all.enumerated() where i % 3 == 0 && d >= split && i > 60 { if let m = mf[d], let c = classic[d] { cErr.append(abs(c - m)) } }
    print("current classic (5 500, EMA)            test vs MacroFactor", String(format: "%.0f kcal", cErr.reduce(0, +) / Double(max(cErr.count, 1))))
    exit(0)
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
