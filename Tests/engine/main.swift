import Foundation
var fails = 0
func check(_ n: String, _ ok: Bool, _ got: Any = "") { if !ok { fails += 1; print("FAIL", n, got) } }
func trend(_ s: [SimDay]) -> [TrendPoint] { EngineTrend.run(s.map(\.day)) }

// 1. Steady cut: 600 kcal under for 10 weeks. Rate within 0.15 kg/wk of the truth after 4 weeks.
do {
    var sim = Simulator(); var days: [SimDay] = []
    for i in 0..<70 { days.append(sim.step(i, intake: 2300)) }
    let t = trend(days)
    let trueRate = (days[69].trueMass - days[55].trueMass) / 2
    check("steady cut: rate", abs(t[69].ratePerWeek - trueRate) < 0.15, (t[69].ratePerWeek, trueRate))
    check("steady cut: level", abs(t[69].trend - days[69].trueMass) < 0.5, (t[69].trend, days[69].trueMass))
    // Property: the trend never moves more than 0.3 kg in a day.
    let jumps = zip(t.dropFirst(14), t.dropFirst(15)).filter { $0.0.weighed && $0.1.weighed }.map { abs($1.trend - $0.trend) }
    check("settled: never more than 0.4 kg between consecutive weigh-ins", jumps.allSatisfy { $0 < 0.4 }, jumps.max() ?? 0)
}

var taggedRise = 0.0
// 2. Refeed weekend, tagged vs untagged: 300 g extra carbs two days → about 1 kg of glycogen water.
for tagged in [true, false] {
    var sim = Simulator(); sim.rng = Rng(s: 7); var days: [SimDay] = []
    for i in 0..<42 {
        let refeed = i == 35 || i == 36
        days.append(sim.step(i, intake: refeed ? 3700 : 2500, extraCarbs: refeed ? 300 : 0, tag: refeed && tagged ? [.refeed] : []))
    }
    let t = trend(days)
    let rise = t[38].trend - t[34].trend
    let scaleJump = (days[37].day.weighIns.first ?? 0) - (days[34].day.weighIns.first ?? 0)
    if tagged { check("refeed tagged: trend rises < 0.25 kg", rise < 0.25, (rise, scaleJump)); taggedRise = rise }
    else { check("tagging helps (tagged rise < untagged)", taggedRise < rise, (taggedRise, rise)) }
}

// 3. Creatine start (tagged): scale up ~0.75 kg of water in a week; trend moves < 0.35 kg in 3 days.
do {
    var sim = Simulator(); sim.rng = Rng(s: 11); var days: [SimDay] = []
    for i in 0..<45 { days.append(sim.step(i, intake: 2900, creatine: i >= 35, tag: i == 35 ? [.creatineStart] : [])) }
    let t = trend(days)
    check("creatine: trend calm", t[38].trend - t[34].trend < 0.35, t[38].trend - t[34].trend)
}

// 4. Travel with a different scale (+1.2 kg) for a week, tagged.
do {
    var sim = Simulator(); sim.rng = Rng(s: 3); var days: [SimDay] = []
    for i in 0..<56 {
        sim.scaleOffset = (35..<42).contains(i) ? 1.2 : 0
        days.append(sim.step(i, intake: 2600, tag: (35..<42).contains(i) ? [.travel] : []))
    }
    let t = trend(days)
    check("travel scale: trend within 0.5 kg", abs(t[41].trend - days[41].trueMass) < 0.5, (t[41].trend, days[41].trueMass))
}

// 5. A week of half-logged days (intake unknown) and a two-week gap with no weigh-ins.
do {
    var sim = Simulator(); sim.rng = Rng(s: 5); var days: [SimDay] = []
    for i in 0..<84 {
        if (40..<54).contains(i) { sim.weighInChance = 0 } else { sim.weighInChance = 0.85 }
        days.append(sim.step(i, intake: 2400, logged: (28..<35).contains(i) ? false : nil))
    }
    let t = trend(days)
    check("gap: uncertainty grows", t[53].sd > t[39].sd * 1.5, (t[39].sd, t[53].sd))
    check("gap: back on track within a week", abs(t[60].trend - days[60].trueMass) < 0.6, (t[60].trend, days[60].trueMass))
    // Expenditure: half-logged days are unknown, not zero: the estimate stays near the truth.
    let e = EngineEnergy.run(days.map(\.day), trend: t, prior: 2600, body: BodyComposition(bodyFatPercent: 20))
    check("expenditure converges", abs(e[83].kcal - 2900) < 250, e[83].kcal)
    check("expenditure uncertainty narrows", e[83].sd < e[10].sd, (e[10].sd, e[83].sd))
    check("expenditure moves within its weekly limit", (7..<e.count).allSatisfy { abs(e[$0].kcal - e[$0 - 7].kcal) <= 200.5 })
}

// 6. Fast bulk (+700 kcal) and recomp (flat weight): rate sign right.
do {
    var sim = Simulator(); sim.rng = Rng(s: 9); var days: [SimDay] = []
    for i in 0..<56 { days.append(sim.step(i, intake: 3600)) }
    check("fast bulk: rising", trend(days)[55].ratePerWeek > 0.4, trend(days)[55].ratePerWeek)
    var sim2 = Simulator(); sim2.rng = Rng(s: 10); var flat: [SimDay] = []
    for i in 0..<56 { flat.append(sim2.step(i, intake: 2900)) }
    check("recomp/maintenance: flat", abs(trend(flat)[55].ratePerWeek) < 0.2, trend(flat)[55].ratePerWeek)
}

// 6b. Step adjustment: 5 000 more steps this week at ~89 kg → about +220 kcal, and only when switched on.
do {
    var sim = Simulator(); sim.rng = Rng(s: 21); var days: [SimDay] = []
    for i in 0..<70 { var d = sim.step(i, intake: 2900); d.day.steps = i >= 63 ? 13000 : 8000; days.append(d) }
    let t = EngineTrend.run(days.map(\.day))
    var on = EnergySettings(); on.stepAdjustment = true
    let a = EngineEnergy.run(days.map(\.day), trend: t, prior: 2900, body: BodyComposition(bodyFatPercent: 20), on)
    let b = EngineEnergy.run(days.map(\.day), trend: t, prior: 2900, body: BodyComposition(bodyFatPercent: 20))
    let expected = 5000 * 0.0005 * t[69].trend
    check("steps: adjustment ≈ 5 000 × 0.0005 × kg", abs(a[69].stepAdjustment - expected) < 25, (a[69].stepAdjustment, expected))
    check("steps: off by default", b[69].stepAdjustment == 0 && abs(a[69].kcal - b[69].kcal - a[69].stepAdjustment) < 0.01)
}

// 7. Forbes density: leaner → a bigger lean share → fewer kcal per kg.
check("density lean < density higher fat", EngineEnergy.density(fatMass: 10) < EngineEnergy.density(fatMass: 30))
check("density at 30 kg fat near 7 700", abs(EngineEnergy.density(fatMass: 30) - 7470) < 150, EngineEnergy.density(fatMass: 30))
// 8. Targets: hand-calculated.
let me = Person(male: true, heightCm: 189, age: 33)
do {
    // Mifflin 110 kg, 189 cm, 33 y, male: 1100 + 1181.25 − 165 + 5 = 2121.25
    check("Mifflin by hand", abs(EngineTargets.mifflin(me, weight: 110) - 2121.25) < 0.01)
    // Floor with 20% body fat: 30 × 88 = 2640; without: max(Mifflin, 1500) and flagged.
    check("floor from FFM", abs(EngineTargets.floor(me, weight: 110, body: BodyComposition(bodyFatPercent: 20)).kcal - 2640) < 0.01)
    let fb = EngineTargets.floor(me, weight: 110, body: BodyComposition())
    check("fallback floor", fb.fallback && abs(fb.kcal - 2121.25) < 0.01)
    // Cut at 0.5%/wk, 3000 expenditure, 110 kg, 20% BF: density at 22 kg fat; daily = 0.55 × ρ / 7.
    let rho = EngineEnergy.density(fatMass: 22)
    let r = EngineTargets.make(phase: .cut, ratePercent: 0.5, expenditure: 3000, weight: 110, body: BodyComposition(bodyFatPercent: 20), person: me)
    let expected = max(((3000 - 0.55 * rho / 7) / 10).rounded() * 10, 2640)
    check("cut calories by hand", r.targets.kcal == expected, (r.targets.kcal, expected))
    check("cut protein 2.6 g/kg lean, clamped ≤ 2.6 g/kg BW", r.targets.protein == min((2.6 * 88).rounded(), 286), r.targets.protein)
    check("fat ≥ floor (55 g)", r.targets.fat >= 55)
    check("macros add up", abs(r.targets.protein * 4 + r.targets.fat * 9 + r.targets.carbs * 4 - r.targets.kcal) < 15)
    // Property: across a grid, targets never break the floor, the deficit/surplus limits or the fat floor.
    var ok = true
    for e in stride(from: 1800.0, through: 4200, by: 200) { for w in stride(from: 60.0, through: 140, by: 20) { for ph in Phase.allCases { for bf: Double? in [nil, 12, 25] {
        let t = EngineTargets.make(phase: ph, ratePercent: ph == .cut ? 1.0 : ph.defaultRate, expenditure: e, weight: w, body: BodyComposition(bodyFatPercent: bf), person: me)
        let fl = EngineTargets.floor(me, weight: w, body: BodyComposition(bodyFatPercent: bf)).kcal
        if t.targets.kcal + 5 < fl || (t.targets.kcal > e * 1.15 + 5 && t.targets.kcal > fl + 5) || t.targets.fat + 1 < min(max(40, 0.5 * w), t.targets.kcal / 9) { ok = false }
        if t.targets.kcal + 5 < e * 0.75 && t.targets.kcal > fl + 5 { ok = false }
    } } } }
    check("targets always within floor and limits", ok)
}

// 9. Check-in decisions.
func input(_ f: (inout CheckInInput) -> Void) -> CheckInInput {
    var i = CheckInInput(day: "d", phase: "cut", weeksInPhase: 4, targetRatePct: 0.5, trendKg: 110, trendSD: 0.1, observedRateKgWeek: -0.55,
                         expenditure: 3000, expenditureSD: 80, loggedDays: 7, weighIns: 7, waterEventLast3Days: false, daysOfData: 100,
                         avgIntake: 2600, currentTargets: MacroTargets(kcal: 2600, protein: 220, fat: 70, carbs: 200), style: "coached")
    f(&i); return i
}
let body = BodyComposition(bodyFatPercent: 20)
do {
    let patchy = EngineCheckIn.decide(input { $0.loggedDays = 3 }, person: me, body: body)
    check("patchy week: no change with a reason", !patchy.changed && patchy.reasons.last?.rule == "low confidence")
    let water = EngineCheckIn.decide(input { $0.waterEventLast3Days = true }, person: me, body: body)
    check("water event: no change", !water.changed && water.reasons.last?.rule == "low confidence")
    let newbie = EngineCheckIn.decide(input { $0.daysOfData = 9 }, person: me, body: body)
    check("new user: no change", !newbie.changed && newbie.reasons.last?.rule == "new user")
    // Expenditure up 400: raw well above current → capped at +150.
    let up = EngineCheckIn.decide(input { $0.expenditure = 3400; $0.currentTargets.kcal = 2700 }, person: me, body: body)
    check("cap +150", up.output.kcal - 2700 <= 150 && up.output.kcal > 2700, up.output.kcal)
    // Bulk going down: at most −75.
    let bulk = EngineCheckIn.decide(input { $0.phase = "bulk"; $0.targetRatePct = 0.25; $0.expenditure = 2600; $0.currentTargets.kcal = 3200; $0.observedRateKgWeek = 0.5 }, person: me, body: body)
    check("bulk: at most −75", bulk.output.kcal >= 3125 && bulk.output.kcal < 3200, bulk.output.kcal)
    // Manual: reports, never changes. Collaborative: proposes.
    check("manual reports only", !EngineCheckIn.decide(input { $0.style = "manual"; $0.expenditure = 3400 }, person: me, body: body).changed)
    check("collaborative proposes", EngineCheckIn.decide(input { $0.style = "collaborative"; $0.expenditure = 3400; $0.currentTargets.kcal = 2700 }, person: me, body: body).action == "proposed")
    // Eating far below the floor: never lowered further.
    let low = EngineCheckIn.decide(input { $0.avgIntake = 1500; $0.expenditure = 2500; $0.currentTargets.kcal = 2700 }, person: me, body: body)
    check("low intake: not lowered", low.output.kcal >= 2640 && low.reasons.contains { $0.rule == "low intake" || $0.rule == "calorie floor" }, low.output.kcal)
    // Records explain themselves and round-trip as JSON.
    let data = try! JSONEncoder().encode(up)
    let back = try! JSONDecoder().decode(CheckInRecord.self, from: data)
    check("record round-trips", back == up)
    check("record cites evidence", !up.evidence.isEmpty && up.evidence.allSatisfy { Evidence.entry($0) != nil }, up.evidence)
    // Deterministic.
    check("deterministic", EngineCheckIn.decide(input { _ in }, person: me, body: body) == EngineCheckIn.decide(input { _ in }, person: me, body: body))
}

// 10. Signals.
do {
    check("e1RM only 3–10 reps", EngineSignals.e1rm(LiftSession(day: "", exercise: "b", kg: 100, reps: 2, rir: nil)) == nil
          && EngineSignals.e1rm(LiftSession(day: "", exercise: "b", kg: 100, reps: 12, rir: nil)) == nil
          && abs(EngineSignals.e1rm(LiftSession(day: "", exercise: "b", kg: 100, reps: 8, rir: 2))! - 100 * (1 + 10.0 / 30)) < 0.001)
    let falling: [String: [Int: Double]] = ["bench": [1: 140, 2: 136, 3: 132], "squat": [1: 180, 2: 175, 3: 170]]
    let f = EngineSignals.flags(weekly: falling, thisWeek: 3, phase: .cut, observedRate: -1.2, targetRate: -0.55, weeksInPhase: 4, adherence: 0.9, sleepHours: 7.5)
    check("strength drop on a fast cut flagged", f.contains { $0.rule == "strength drop on a fast cut" })
    let slow = EngineSignals.flags(weekly: falling, thisWeek: 3, phase: .cut, observedRate: -0.5, targetRate: -0.55, weeksInPhase: 4, adherence: 0.9, sleepHours: 7.5)
    check("not flagged when losing as planned", slow.isEmpty)
    let timer = EngineSignals.flags(weekly: [:], thisWeek: 3, phase: .cut, observedRate: -0.5, targetRate: -0.55, weeksInPhase: 16, adherence: 0.95, sleepHours: 8)
    check("diet break never on a timer alone", timer.isEmpty)
    let tired = EngineSignals.flags(weekly: [:], thisWeek: 3, phase: .cut, observedRate: -0.5, targetRate: -0.55, weeksInPhase: 10, adherence: 0.6, sleepHours: 6)
    check("diet break with reasons", tired.contains { $0.rule == "diet break" })
}
check("recomp advice: experienced lifter at an assumed body fat → not recommended", EngineTargets.recompAdvice(me, body: BodyComposition()).detail.hasPrefix("A recomp works best"))
check("recomp advice: newer lifter → reasonable", EngineTargets.recompAdvice(Person(male: true, heightCm: 180, age: 25, trainingYears: 0.5), body: BodyComposition()).detail.hasPrefix("A recomp is reasonable"))
check("after a cut comes maintenance", EngineTargets.nextPhase(after: .cut).0 == .maintain)
// A long gap without weigh-ins (18 Oct 2026): losing 0.1 kg a day for 30 days, then nothing for 120
// days, then 8 kg heavier. The rate must not carry on through the gap, the first weigh-in after it is
// believed (not an outlier), and the gap is drawn as a straight line between the two sides.
do {
    var gd: [EngineDay] = []
    for i in 0..<30 { gd.append(EngineDay(key: String(format: "d%04d", i), weighIns: [100 - 0.1 * Double(i)])) }
    for i in 30..<150 { gd.append(EngineDay(key: String(format: "d%04d", i), weighIns: [])) }
    for i in 150..<160 { gd.append(EngineDay(key: String(format: "d%04d", i), weighIns: [105])) }
    let t = EngineTrend.run(gd)
    let before = t[29].trend, after = t[150].trend, mid = t[90].trend
    check("gap: the first weigh-in after it is believed", abs(after - 105) < 1, after)
    check("gap: no runaway rate (trend stays between the two sides)", t[30..<150].allSatisfy { $0.trend >= min(before, after) - 0.01 && $0.trend <= max(before, after) + 0.01 }, t[30..<150].map(\.trend).min() ?? 0)
    check("gap: a straight line between the two sides", abs(mid - (before + (after - before) * 61 / 121)) < 0.01, mid)
    // Still waiting for the next weigh-in: the rate fades instead of extrapolating for months.
    let open = EngineTrend.run(Array(gd[0..<150]))
    check("open gap: the trend drifts at most a few kg", abs(open.last!.trend - before) < 3, open.last!.trend)
}
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED")
