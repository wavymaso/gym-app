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
let v1 = Dictionary(expenditureSeries(start: start.day, end: end, initial: start.kcal, intake: intake, weights: weights).map { ($0.day, $0.kcal) },
                    uniquingKeysWith: { a, _ in a })
var methods: [(String, [String: Double], Double, Double)] = []      // name, series, gain density, loss density
methods.append(("Ours (V2, 7700/7700)", series(JointSettings()), 7700, 7700))
for (g, l) in [(6000.0, 7700.0), (5000, 7700), (4000, 7700), (6000, 7000)] {
    var s = JointSettings(); s.gainDensity = g; s.lossDensity = l
    methods.append(("Ours gain \(Int(g)) / loss \(Int(l))", series(s), g, l))
}
methods.append(("V1 (regression)", v1, 7700, 7700))
methods.append(("MacroFactor", mf, 7700, 7700))

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
if ProcessInfo.processInfo.environment["COHERE"] != nil {
    // A1: which trend should drive both the screens and the targets? The classic expenditure fed by the
    // EMA trend (today) vs by the engine trend; and both trends on forecasts and against MacroFactor's trend.
    let prof = ctx.profile!
    print("settings in this database: expenditure", prof.expAlgorithm.isEmpty ? "default (classic)" : prof.expAlgorithm)
    let all = days(from: weights.first!.day, through: end)
    let split = all[all.count * 2 / 3]
    let wmap = Dictionary(grouping: weights, by: \.day).mapValues { $0.map(\.value) }
    func target(_ d: String) -> Double? {
        let v = (-3...3).flatMap { wmap[addDays(d, $0)] ?? [] }
        return v.count >= 2 ? v.reduce(0, +) / Double(v.count) : nil
    }
    let emaS = trendSeriesV1(weights, through: end)
    let ema = Dictionary(emaS.map { ($0.day, $0.trend) }, uniquingKeysWith: { a, _ in a })
    let engRun = EngineTrend.run(emaS.map { EngineDay(key: $0.day, weighIns: wmap[$0.day] ?? [], events: trendWaterEvents[$0.day] ?? []) })
    let eng = Dictionary(engRun.map { ($0.day, $0.trend) }, uniquingKeysWith: { a, _ in a })
    let engRate = Dictionary(engRun.map { ($0.day, $0.ratePerWeek) }, uniquingKeysWith: { a, _ in a })
    var mfT: [String: Double] = [:]
    let mfTPath = (args[2] as NSString).deletingLastPathComponent + "/mf-trend.csv"
    for line in ((try? String(contentsOfFile: mfTPath, encoding: .utf8)) ?? "").split(separator: "\n") {
        let p = line.split(separator: ","); if p.count == 2, let v = Double(p[1]) { mfT[String(p[0])] = v }
    }
    func avg(_ x: [Double]) -> Double { x.reduce(0, +) / Double(max(x.count, 1)) }
    func ranges() -> [(String, String, String)] { [("0", split, "train"), (split, "9", "test ")] }
    print("\n1. Trend forecasts: MAE (kg) of the mean weigh-in 1/2/3/4 weeks later; test = last third (from \(split))")
    func forecast(_ name: String, _ f: (String, Int) -> Double?) {
        var line = name.padding(toLength: 36, withPad: " ", startingAt: 0)
        for (lo, hi, label) in ranges() {
            let cells = (1...4).map { wk -> String in
                var errs: [Double] = []
                for (i, d) in all.enumerated() where i % 3 == 0 && d >= lo && d < hi && i > 30 {
                    guard wmap[d] != nil, let p = f(d, wk * 7), let t = target(addDays(d, wk * 7)) else { continue }
                    errs.append(abs(p - t))
                }
                return String(format: "%.2f", avg(errs))
            }
            line += " \(label) " + cells.joined(separator: "/")
        }
        print(line)
    }
    forecast("classic EMA, level") { d, _ in ema[d] }
    forecast("classic EMA + 14-day slope") { d, h in ema[d].flatMap { a in ema[addDays(d, -14)].map { a + (a - $0) / 14 * Double(h) } } }
    forecast("engine, level") { d, _ in eng[d] }
    forecast("engine + its rate") { d, h in eng[d].flatMap { a in engRate[d].map { a + $0 / 7 * Double(h) } } }
    for (name, m) in [("classic EMA", ema), ("engine", eng)] {
        var line = "vs MacroFactor's trend: \(name)".padding(toLength: 36, withPad: " ", startingAt: 0)
        for (lo, hi, label) in ranges() { line += String(format: " \(label) %.2f kg", avg(mfT.keys.filter { $0 >= lo && $0 < hi }.compactMap { d in m[d].map { abs($0 - mfT[d]!) } })) }
        print(line)
    }
    if let span = ProcessInfo.processInfo.environment["DAYS"] {
        // DAYS=2025-01-01:2025-07-15 → each weighed day, and the 1st/15th of each month, side by side.
        let p = span.split(separator: ":").map(String.init)
        for d in all where d >= p[0] && d <= p[1] && (wmap[d] != nil || d.hasSuffix("-01") || d.hasSuffix("-15")) {
            print(d, wmap[d].map { String(format: "w %6.2f", $0.reduce(0, +) / Double($0.count)) } ?? "        ", String(format: "eng %6.2f rate %+5.2f  ema %6.2f  mf %@", eng[d] ?? 0, (engRate[d] ?? 0), ema[d] ?? 0, mfT[d].map { String(format: "%6.2f", $0) } ?? "  –"))
        }
        exit(0)
    }
    if ProcessInfo.processInfo.environment["GAP"] != nil {
        // The engine − classic gap by month: signed, against the rate (an EMA lags a moving weight by about
        // (1 − α)/α days, so it sits above the true weight on a cut), and water-event days.
        print("\nmonth     eng−EMA  eng−MF   |gap|  rate kg/wk  EMA lag est.  residual  water-event days  weigh-ins")
        let lagDays = (1 - trendSmoothing) / trendSmoothing
        for (m, ds) in Dictionary(grouping: all, by: { String($0.prefix(7)) }).sorted(by: { $0.key < $1.key }) {
            let g = ds.compactMap { d in eng[d].flatMap { a in ema[d].map { a - $0 } } }
            let gm = ds.compactMap { d in eng[d].flatMap { a in mfT[d].map { a - $0 } } }
            let r = ds.compactMap { engRate[$0] }
            let rate = avg(r), lag = rate / 7 * lagDays
            let ev = ds.filter { !(trendWaterEvents[$0] ?? []).isEmpty }.count
            print(m, String(format: "  %+6.2f  %@  %6.2f   %+6.2f      %+6.2f       %+6.2f   %3d               %d", avg(g), gm.isEmpty ? "   –  " : String(format: "%+6.2f", avg(gm)), avg(g.map(abs)), rate, lag, avg(g) - lag, ev, ds.filter { wmap[$0] != nil }.count))
        }
        exit(0)
    }
    // The app's classic expenditure, with the trend passed in (same maths as classicExpenditure).
    func classic(_ trend: [String: Double], window: Int = 21, density: Double = 5500, alpha: Double = 0.05) -> [String: Double] {
        let ds = days(from: start.day, through: end)
        var e = start.kcal, out: [String: Double] = [:]
        for (i, d) in ds.enumerated() {
            if i >= window - 1 {
                let first = ds[i - window + 1]
                let logged = ds[(i - window + 1)...i].compactMap { intake[$0] }
                if Double(logged.count) >= Double(window) * 0.5, let t0 = trend[first], let t1 = trend[d] {
                    e += alpha * (logged.reduce(0, +) / Double(logged.count) - density * (t1 - t0) / Double(window - 1) - e)
                }
            }
            out[d] = e
        }
        return out
    }
    let c1 = classic(ema), c2 = classic(eng)
    var js = JointSettings(); js.waterEvents = ctx.waterEvents(from: start.day, to: end)
    let jt = Dictionary(jointExpenditure(start: start.day, end: end, initial: start.kcal, intake: intake, weights: weights,
                                         nudges: ctx.expenditureNudges(from: start.day, to: end), settings: js).map { ($0.day, $0.kcal) }, uniquingKeysWith: { a, _ in a })
    let snap = ctx.engineSnapshot()!
    let en = Dictionary(snap.expenditure.map { ($0.day, $0.kcal) }, uniquingKeysWith: { a, _ in a })
    let enTrend = Dictionary(snap.trend.map { ($0.day, $0.trend) }, uniquingKeysWith: { a, _ in a })
    let enDensity = Dictionary(snap.expenditure.map { ($0.day, $0.density) }, uniquingKeysWith: { a, _ in a })
    let appExp = Dictionary(classicExpenditure(start: start.day, end: end, initial: start.kcal, intake: intake, weights: weights).map { ($0.day, $0.kcal) }, uniquingKeysWith: { a, _ in a })
    print(String(format: "\n(check: the copy matches the app's classic expenditure on every day: max diff %.3f kcal)", appExp.keys.map { abs(appExp[$0]! - (c1[$0] ?? .infinity)) }.max() ?? -1))
    print("\n2. Expenditure (classic maths) fed by each trend")
    for (name, e, t) in [("classic exp. on EMA trend", c1, ema), ("classic exp. on engine trend", c2, eng),
                         ("joint V2 (your setting), from EMA", jt, ema), ("joint V2 (your setting), from eng", jt, eng),
                         ("engine energy (shadow), its trend", en, enTrend)] {
        var line = name.padding(toLength: 36, withPad: " ", startingAt: 0)
        for (from, label) in [("2025-01-01", "vs MF since 2025"), ("2026-07-01", "since Jul 26"), (split, "test third")] {
            line += String(format: "  \(label) %.0f kcal", avg(mf.keys.filter { $0 >= from && $0 < end }.compactMap { d in e[d].map { abs($0 - mf[d]!) } }))
        }
        print(line)
        var l2 = "   4-week weight prediction".padding(toLength: 36, withPad: " ", startingAt: 0)
        for (lo, hi, label) in ranges() {
            var errs: [Double] = []
            for (i, d) in all.enumerated() where i % 3 == 0 && d >= lo && d < hi && i > 60 {
                guard let x = e[d], let tp = t[d], let tt = target(addDays(d, 28)) else { continue }
                guard (1...28).compactMap({ intake[addDays(d, $0)] }).count >= 20 else { continue }
                let rho = name.hasPrefix("engine") ? (enDensity[d] ?? 5500) : name.hasPrefix("joint") ? kcalPerKg : 5500   // each model's own kcal/kg
                errs.append(abs(tp + (1...28).reduce(0.0) { acc, j in intake[addDays(d, j)].map { acc + ($0 - x) / rho } ?? acc } - tt))
            }
            l2 += String(format: "  \(label) %.2f kg (n %d)", avg(errs), errs.count)
        }
        print(l2)
    }
    print("\n3. Today (\(end))")
    let g = ctx.activeProgram!
    let body = ctx.bodyInfo(guardrails: g.mode == "coached")
    print("app now: expenditure \(Int(ctx.expenditureEstimates(through: end).last?.kcal ?? 0)), live target \(Int(ctx.targets()?.kcal ?? 0)) kcal, trend shown \(String(format: "%.2f", trendSeries(weights, through: end).last?.trend ?? 0))")
    for (name, e, t) in [("now: joint expenditure, engine weight", jt, eng), ("A1: engine trend + engine energy", en, enTrend), ("A2: engine trend + classic exp.", c2, eng), ("B: classic EMA + classic exp.", c1, ema), ("B': classic EMA + joint", jt, ema)] {
        let kg = t[end] ?? t.values.first!, x = e[end] ?? 0
        let tg = makeTargets(expenditure: x, weightKg: kg, sex: prof.sexValue, goal: g.goalValue, ratePercent: g.ratePercent, diet: g.dietValue, protein: g.proteinValue, body: body)
        print(name.padding(toLength: 38, withPad: " ", startingAt: 0), String(format: "trend %.2f kg · expenditure %.0f · target %.0f kcal, P %.0f g (rate %.2f%%/wk)", kg, x, tg.kcal, tg.protein, g.ratePercent))
    }
    print(String(format: "MacroFactor's last trend %@ %.2f kg", mfT.keys.max() ?? "-", mfT[mfT.keys.max() ?? ""] ?? 0))
    exit(0)
}
if ProcessInfo.processInfo.environment["REPLAY"] != nil {
    // Every week of the last year, as if the engine had been live: only data up to that day.
    let all = ctx.engineDays()
    let person = ctx.enginePerson!, body = ctx.engineBody
    let sets = ((try? ctx.fetch(FetchDescriptor<TargetSet>(sortBy: [SortDescriptor(\.fromDay)]))) ?? [])
    func live(_ d: String) -> TargetSet? { sets.last { $0.fromDay <= d } }
    var lines: [String] = ["| Week ending | Trend (kg) | Rate kg/wk | Engine expenditure | MacroFactor expenditure | App's live target | Engine target | Rule |", "|---|---|---|---|---|---|---|---|"]
    var diffs: [Double] = [], expDiff: [Double] = [], changes = 0, noChange = 0
    var engineCur: MacroTargets? = nil                   // the engine's own targets, carried week to week
    for k in stride(from: all.count - 365, to: all.count, by: 7) where k > 60 {
        let slice = Array(all[0...k])
        let tr = EngineTrend.run(slice)
        let en = EngineEnergy.run(slice, trend: tr, prior: start.kcal, body: body)
        guard let t = tr.last, let e = en.last else { continue }
        let liveSet = live(slice.last!.key)
        let start = engineCur ?? liveSet.map { MacroTargets(kcal: $0.kcal, protein: $0.protein, fat: $0.fat, carbs: $0.carbs) }
            ?? EngineTargets.make(phase: .cut, ratePercent: 0.5, expenditure: e.kcal, weight: t.trend, body: body, person: person).targets
        let week = slice.suffix(8).dropLast(), logged = week.compactMap(\.intake)
        let i = CheckInInput(day: t.day, phase: "cut", weeksInPhase: 8, targetRatePct: 0.5, trendKg: t.trend, trendSD: t.sd, observedRateKgWeek: t.ratePerWeek,
                             expenditure: e.kcal, expenditureSD: e.sd, loggedDays: logged.count, weighIns: week.filter { !$0.weighIns.isEmpty }.count,
                             waterEventLast3Days: slice.suffix(3).contains { !$0.events.isEmpty }, daysOfData: slice.count,
                             avgIntake: logged.isEmpty ? nil : logged.reduce(0, +) / Double(logged.count),
                             currentTargets: start, style: "coached")
        let r = EngineCheckIn.decide(i, person: person, body: body)
        engineCur = r.output
        let liveNext = live(addDays(t.day, 7))?.kcal
        if let l = liveNext { diffs.append(abs(r.output.kcal - l)) }
        if let m = mf[t.day] { expDiff.append(abs(e.kcal - m)) }
        if r.changed { changes += 1 } else { noChange += 1 }
        lines.append("| \(t.day) | \(String(format: "%.1f", t.trend)) | \(String(format: "%+.2f", t.ratePerWeek)) | \(Int(e.kcal)) ± \(Int(e.sd)) | \(mf[t.day].map { String(Int($0)) } ?? "–") | \(liveNext.map { String(Int($0)) } ?? "–") | \(Int(start.kcal)) → \(Int(r.output.kcal)) | \(r.reasons.last?.rule ?? "") |")
    }
    let summary = String(format: "Weeks: %d · engine changed targets %d times, held %d · average gap to the app's live target (%d weeks where it existed) %.0f kcal · engine expenditure vs MacroFactor %.0f kcal", changes + noChange, changes, noChange, diffs.count, diffs.reduce(0, +) / Double(max(diffs.count, 1)), expDiff.reduce(0, +) / Double(max(expDiff.count, 1)))
    print(summary)
    let out = ProcessInfo.processInfo.environment["REPORT"] ?? "/dev/null"
    try? ("## Weekly replay (last 12 months, as if live)\n\nThe engine runs each week on only the data up to that day, carrying its own targets forward (phase assumed: cut at 0.5%/week; body fat assumed 20%). MacroFactor's export has no target history, so its recommendations can't be compared; its expenditure can.\n\n" + summary + "\n\n" + lines.joined(separator: "\n") + "\n").write(toFile: out, atomically: true, encoding: .utf8)
    exit(0)
}
if ProcessInfo.processInfo.environment["ENGINECHECK"] != nil {
    print("person", ctx.enginePerson as Any, "program", ctx.activeProgram != nil, "targets", ctx.targets() != nil)
    let snap = ctx.engineSnapshot()
    print("snapshot days", snap?.days.count ?? -1, "trend", snap?.trend.last as Any, "exp", snap?.expenditure.last as Any)
    if let r = ctx.engineCheckIn() { print(r.action, r.input.currentTargets.kcal, "→", r.output.kcal); for x in r.reasons { print(" -", x.rule, ":", x.detail) } } else { print("no record") }
    exit(0)
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
        ExpenditureAlgorithm.allCases.filter { $0 != .joint && $0 != .classic && $0.rawValue != "engine" }.map { a in ("V1 \(a.rawValue)", Dictionary(expenditureSeries(start: start.day, end: end, initial: start.kcal, intake: intake, weights: weights, settings: a.v1Settings).map { ($0.day, $0.kcal) }, uniquingKeysWith: { x, _ in x })) }
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
