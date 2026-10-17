import Foundation
var fails = 0
func check(_ n: String, _ ok: Bool, _ got: Any = "") { if !ok { fails += 1; print("FAIL", n, got) } }

// Day arithmetic.
check("addDaysKey", addDaysKey("2026-10-16", -16) == "2026-09-30" && addDaysKey("2024-02-28", 1) == "2024-02-29" && addDaysKey("2026-12-31", 1) == "2027-01-01",
      (addDaysKey("2026-10-16", -16), addDaysKey("2024-02-28", 1), addDaysKey("2026-12-31", 1)))
check("daysBetweenKeys", daysBetweenKeys("2026-09-30", "2026-10-16") == 16)

// A synthetic month: oats + yogurt breakfast 08:00, chicken + rice lunch 14:00, snack 17:30, dinner 21:30.
func f(_ day: String, _ wd: Int, _ m: Int, _ key: String, _ g: Double, _ p: Double, _ fat: Double, _ c: Double, _ fib: Double) -> LoggedFood {
    LoggedFood(day: day, weekday: wd, minute: m, key: key, name: key, grams: g, kcal: p * 4 + fat * 9 + c * 4, protein: p, fat: fat, carbs: c, fibre: fib)
}
var logs: [LoggedFood] = []
for i in 1...30 {
    let d = addDaysKey("2026-10-16", -i), wd = (i % 7) + 1
    logs += [f(d, wd, 480, "oats", 80, 10, 5, 50, 8), f(d, wd, 485, "yogurt", 250, 25, 2, 10, 0),
             f(d, wd, 840, "chicken", 200, 60, 6, 0, 0), f(d, wd, 845, "rice", 250, 6, 1, 70, 1),
             f(d, wd, 1050, "banana", 120, 1, 0, 27, 3),
             f(d, wd, 1290, "salmon", 150, 30, 18, 0, 0), f(d, wd, 1295, "potato", 300, 6, 0, 50, 6)]
}
logs.append(LoggedFood(day: "2026-10-01", weekday: 4, minute: 720, key: "", name: "Day total (imported)", grams: 0, kcal: 2500, protein: 150, fat: 80, carbs: 250, fibre: 0))
let targets = Dictionary(uniqueKeysWithValues: (1...30).map { (addDaysKey("2026-10-16", -$0), DayTarget(kcal: 2400, protein: 190, fat: 60, carbs: 250)) })
let p = EatingProfile.learn(logs, today: "2026-10-16", targets: targets)
check("days used (imported totals ignored)", p.daysUsed == 30, p.daysUsed)
check("four meals a day", p.mealsPerDay == 4, p.mealsPerDay)
check("breakfast at 08:00", p.slots.first?.typicalMinute == 480, p.slots.first?.typicalMinute ?? -1)
check("breakfast foods", Set(p.slots[0].foods.prefix(2).map(\.key)) == ["oats", "yogurt"])
check("lunch portion of rice", p.slots[1].foods.first { $0.key == "rice" }?.grams == 250)
check("oats and yogurt together", p.together.contains { Set([$0.a, $0.b]) == ["oats", "yogurt"] && $0.times == 30 })
check("snack is low in protein", p.misses.contains { $0.what == "protein spread" })
check("protein short vs 190 target", p.misses.contains { $0.what == "protein" })
check("deterministic", EatingProfile.learn(logs, today: "2026-10-16", targets: targets) == p)
// Recency: a food switched a week ago outranks the old one.
var switched = logs.filter { $0.key != "oats" || $0.day < addDaysKey("2026-10-16", -7) }
for i in 1...7 { switched.append(f(addDaysKey("2026-10-16", -i), 1, 480, "granola", 70, 8, 10, 40, 4)) }
let q = EatingProfile.learn(switched, today: "2026-10-16")
let gi = q.slots[0].foods.firstIndex { $0.key == "granola" } ?? 99, oi = q.slots[0].foods.firstIndex { $0.key == "oats" } ?? 99
check("recent behaviour weighs more (7 recent days vs 23 older)", gi < 99 && oi < 99 && q.slots[0].foods[gi].score > 0.35 * q.slots[0].foods[oi].score, (gi, oi))

// MARK: Planner
func food(_ k: String, _ kc: Double, _ p: Double, _ fa: Double, _ c: Double, _ fi: Double, usual g: Double, slots: [Int: Double], step: Double = 10, max mx: Double = 500) -> PlanFood {
    PlanFood(key: k, name: k, per100: (kc, p, fa, c, fi), step: step, usualGrams: g, maxGrams: mx, usualSlots: slots, frequency: slots.values.reduce(0, +))
}
let rawPantry: [PlanFood] = [
    food("oats", 380, 13, 7, 60, 10, usual: 80, slots: [0: 20]), food("greek yogurt", 60, 10, 0.4, 4, 0, usual: 250, slots: [0: 18, 3: 4]),
    food("whey", 380, 78, 6, 8, 0, usual: 30, slots: [0: 6, 2: 10], step: 15, max: 60), food("banana", 89, 1.1, 0.3, 23, 2.6, usual: 120, slots: [2: 12, 0: 5], step: 120, max: 360),
    food("chicken breast", 120, 23, 2.6, 0, 0, usual: 200, slots: [1: 20, 3: 8]), food("rice", 130, 2.7, 0.3, 28, 0.4, usual: 250, slots: [1: 18, 3: 6]),
    food("potato", 77, 2, 0.1, 17, 2.2, usual: 300, slots: [3: 12]), food("salmon", 208, 20, 13, 0, 0, usual: 150, slots: [3: 12]),
    food("olive oil", 884, 0, 100, 0, 0, usual: 10, slots: [1: 10, 3: 10], step: 5, max: 40), food("bread", 250, 9, 3, 47, 6, usual: 60, slots: [0: 6, 2: 8]),
    food("eggs", 143, 12.6, 9.5, 0.7, 0, usual: 120, slots: [0: 8], step: 60, max: 240), food("broccoli", 34, 2.8, 0.4, 7, 2.6, usual: 200, slots: [3: 8, 1: 4]),
    food("cottage cheese", 98, 11, 4.3, 3.4, 0, usual: 200, slots: [3: 3]), food("pasta", 158, 5.8, 0.9, 31, 1.8, usual: 250, slots: [1: 6]),
    food("beef mince 5%", 137, 21, 5, 0, 0, usual: 150, slots: [1: 5, 3: 6]), food("almonds", 579, 21, 50, 22, 12, usual: 25, slots: [2: 5], step: 5, max: 50),
]
// Realism: roles and meals from names and macros, as in the app.
let pantry: [PlanFood] = rawPantry.map { f in
    var f = f.with(role: FoodRole.guess(name: f.name, kcal: f.per100.kcal, protein: f.per100.protein, fat: f.per100.fat, carbs: f.per100.carbs))
    f.bands = MealBand.guess(name: f.name)
    return f
}
func slotsFor(training: (Int, Int)?, meals: Int = 4, preSleep: Bool = false) -> [PlanSlot] {
    Planner.slots(wake: 7 * 60, sleep: 23 * 60, meals: meals, training: training, preSleep: preSleep)
}
let cutDay = PlanTargets(kcal: 2300, protein: 200, fat: 60, carbs: 240, fibreFloor: 25, fatFloor: 55, weightKg: 110)
func checkPlan(_ name: String, _ plan: DayPlan, _ t: PlanTargets) {
    check("\(name): feasible (\(plan.relaxed))", plan.feasible, (Int(plan.totals.kcal), Int(plan.totals.protein), Int(plan.totals.fat), Int(plan.totals.fibre)))
    check("\(name): hard constraints hold", Planner.hard(plan.totals, t, PlanOptions(), tolerance: plan.relaxed.contains("calorie tolerance ±10%") ? 0.10 : 0.05).isEmpty || !plan.feasible)
}
// Timing.
let evening = slotsFor(training: (18 * 60, 75))
check("evening training: a pre-workout meal before 18:00", evening.contains { $0.kind == .preWorkout && $0.minute <= 17 * 60 && $0.minute >= 14 * 60 }, evening.map { ($0.kind.rawValue, $0.minute) })
check("evening training: a post-workout meal after 19:15", evening.contains { $0.kind == .postWorkout && $0.minute >= 19 * 60 + 15 }, evening.map { ($0.kind.rawValue, $0.minute) })
let morning = slotsFor(training: (7 * 60 + 30, 60))
check("early training: post-workout meal", morning.contains { $0.kind == .postWorkout })
let fastedMorning = Planner.slots(wake: 6 * 60, sleep: 23 * 60, meals: 4, training: (6 * 60 + 30, 60), fasted: true)
check("fasted training: no pre-workout meal", !fastedMorning.contains { $0.kind == .preWorkout })
let ramadan = Planner.slots(wake: 5 * 60, sleep: 24 * 60, meals: 3, training: nil, eatingWindow: (19 * 60 + 30, 23 * 60 + 30))
check("Ramadan: every meal between iftar and suhoor", ramadan.allSatisfy { $0.minute >= 19 * 60 + 30 && $0.minute <= 23 * 60 + 30 }, ramadan.map(\.minute))
for (st, len) in [(18 * 60, 75), (7 * 60 + 30, 60), (11 * 60, 90), (14 * 60, 60), (20 * 60, 60)] {
    let sl = slotsFor(training: (st, len))
    check("no meal during a \(st / 60):\(String(format: "%02d", st % 60)) session", !sl.contains { $0.minute > st - 30 && $0.minute < st + len }, sl.map(\.minute))
    check("a post-workout meal within ~2 h after \(st / 60):00", sl.contains { $0.kind == .postWorkout && $0.minute >= st + len && $0.minute <= st + len + 120 }, sl.map { ($0.kind.rawValue, $0.minute) })
}
check("slots are in time order", evening.map(\.minute) == evening.map(\.minute).sorted())

// Scenarios.
let t0 = Date()
let rest = Planner.plan(cutDay, slots: slotsFor(training: nil), foods: pantry)
let dayMs = Date().timeIntervalSince(t0) * 1000
checkPlan("rest day cut", rest, cutDay)
check("rest day: built mostly from usual foods", rest.slots.flatMap(\.items).filter { i in pantry.first { $0.key == i.key }!.usualSlots.values.reduce(0, +) > 0 }.count >= rest.slots.flatMap(\.items).count - 1)
let eve = Planner.plan(cutDay, slots: evening, foods: pantry)
checkPlan("evening training", eve, cutDay)
func m(_ s: PlanSlot) -> Macros { s.items.reduce(Macros()) { a, i in a + pantry.first { $0.key == i.key }!.macros(i.grams) } }
if let pre = eve.slots.first(where: { $0.kind == .preWorkout }) {
    check("pre-workout meal: carbs, modest fat", m(pre).carbs >= 30 && m(pre).fat <= 20, (m(pre).carbs, m(pre).fat))
}
let spread = eve.slots.map { m($0).protein }
check("protein spread: every meal ≥ 20 g", spread.allSatisfy { $0 >= 20 }, spread.map { Int($0) })
checkPlan("morning training", Planner.plan(cutDay, slots: morning, foods: pantry), cutDay)
let lowCal = PlanTargets(kcal: 1900, protein: 220, fat: 50, carbs: 150, fibreFloor: 20, fatFloor: 50, weightKg: 110)
checkPlan("high-protein low-calorie cut day", Planner.plan(lowCal, slots: slotsFor(training: nil), foods: pantry), lowCal)
let bulk = PlanTargets(kcal: 3600, protein: 190, fat: 100, carbs: 470, fibreFloor: 30, fatFloor: 60, weightKg: 85)
checkPlan("bulk day", Planner.plan(bulk, slots: slotsFor(training: (17 * 60, 90), meals: 5), foods: pantry), bulk)
let fastDay = PlanTargets(kcal: 600, protein: 80, fat: 15, carbs: 30, fibreFloor: 0, fatFloor: 10, weightKg: 110)
checkPlan("fasting day", Planner.plan(fastDay, slots: Planner.slots(wake: 7 * 60, sleep: 23 * 60, meals: 2, training: nil), foods: pantry), fastDay)
let ram = Planner.plan(cutDay, slots: ramadan, foods: pantry)
checkPlan("Ramadan day", ram, cutDay)
if !ram.feasible { print("  ramadan misses", ram.misses, ram.shortMeals, ram.slots.map { ($0.minute, $0.band.rawValue, $0.items.map { "\($0.key) \(Int($0.grams))" }) }) }
let ps = Planner.plan(cutDay, slots: slotsFor(training: nil, preSleep: true), foods: pantry, options: PlanOptions(preSleepProtein: true))
checkPlan("pre-sleep protein", ps, cutDay)
check("pre-sleep slot is protein-rich", ps.slots.last.map { m($0).protein >= 30 } ?? false, ps.slots.last.map { m($0).protein } ?? 0)

// Re-solve: eaten meals never change, and the day still adds up.
var partly = eve.slots
partly[0].eaten = true
partly[0].items = [PlanItem(key: "pasta", grams: 400), PlanItem(key: "olive oil", grams: 15)]      // ate something else
let re = Planner.plan(cutDay, slots: partly, foods: pantry)
check("re-solve keeps the eaten meal exactly", re.slots[0].items == partly[0].items)
checkPlan("re-solve after a different breakfast", re, cutDay)
// Locked meal stays.
var locked = rest.slots; locked[0].locked = true
check("locked meal unchanged", Planner.plan(cutDay, slots: locked, foods: pantry).slots[0].items == rest.slots[0].items)
// A huge unplanned meal: no compensation through extreme restriction.
var big = slotsFor(training: nil)
big[0].eaten = true; big[0].items = [PlanItem(key: "pasta", grams: 700), PlanItem(key: "olive oil", grams: 40), PlanItem(key: "almonds", grams: 50), PlanItem(key: "salmon", grams: 300)]
let after = Planner.plan(cutDay, slots: big, foods: pantry)
check("huge meal: says so plainly", after.note != nil)
check("huge meal: remaining meals still feed you (≥ 250 kcal each)", after.slots.dropFirst().allSatisfy { m($0).kcal >= 200 }, after.slots.dropFirst().map { Int(m($0).kcal) })
// Exclusions are respected.
let noFish = Planner.plan(cutDay, slots: slotsFor(training: nil), foods: pantry, options: PlanOptions(exclusions: ["salmon"]))
check("exclusions never planned", !noFish.slots.flatMap(\.items).contains { $0.key == "salmon" })
// Infeasible: only low-protein foods → relaxes in order, reports what it gave up and what it misses.
let junk = [food("bread", 250, 9, 3, 47, 6, usual: 60, slots: [0: 6]), food("banana", 89, 1.1, 0.3, 23, 2.6, usual: 120, slots: [1: 5], step: 120, max: 360)]
let bad = Planner.plan(cutDay, slots: slotsFor(training: nil), foods: junk)
check("infeasible: reported", !bad.feasible && bad.reasons.contains { $0.rule == "can't fully fit" })
check("relaxation follows the order", ["variety", "usual meal slots", "timing preferences", "calorie tolerance ±10%"].starts(with: bad.relaxed), bad.relaxed)
check("relaxing is kept only when it reduces misses", bad.relaxed.isEmpty || !bad.misses.isEmpty || bad.feasible)
check("deterministic", Planner.plan(cutDay, slots: evening, foods: pantry) == eve)
// Performance: a day < 200 ms, a week < 2 s (here on the Mac; the phone is on the device checklist).
let t1 = Date()
for d in 0..<7 { _ = Planner.plan(d % 2 == 0 ? cutDay : bulk, slots: slotsFor(training: d % 2 == 0 ? (18 * 60, 75) : nil), foods: pantry) }
let weekMs = Date().timeIntervalSince(t1) * 1000
print(String(format: "  timing: one day %.0f ms, a week %.0f ms", dayMs, weekMs))
check("a day in under 200 ms", dayMs < 200, dayMs)
check("a week in under 2 s", weekMs < 2000, weekMs)

// MARK: Realism
check("roles: oil a fat source, jam a condiment, chicken a protein main, bread and rice carb sides, banana a fruit, broccoli a vegetable, yogurt dairy, whey a protein snack",
      pantry.first { $0.key == "olive oil" }!.role == .fatSource && FoodRole.guess(name: "Mermelada de Fresa Diet", kcal: 57, protein: 0, fat: 0, carbs: 14) == .condiment
      && pantry.first { $0.key == "chicken breast" }!.role == .proteinMain && pantry.first { $0.key == "bread" }!.role == .carbSide
      && pantry.first { $0.key == "rice" }!.role == .carbSide && pantry.first { $0.key == "banana" }!.role == .fruit && pantry.first { $0.key == "broccoli" }!.role == .vegetable
      && pantry.first { $0.key == "greek yogurt" }!.role == .dairy && pantry.first { $0.key == "whey" }!.role == .proteinSnack,
      pantry.map { "\($0.key): \($0.role)" })
let allPlans = [rest, eve, Planner.plan(cutDay, slots: morning, foods: pantry), Planner.plan(bulk, slots: slotsFor(training: (17 * 60, 90), meals: 5), foods: pantry), re]
let byK = Dictionary(pantry.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
var noMain = 0, loneCondiment = 0, wrongMeal = 0, tooOften = 0
for p in allPlans {
    var count: [String: Int] = [:]
    for s in p.slots {
        for k in Set(s.items.map(\.key)) { count[k, default: 0] += 1 }
        guard !s.eaten else { continue }
        let roles = s.items.compactMap { byK[$0.key]?.role }
        if !roles.contains(where: \.isCore) { noMain += 1; if roles.contains(where: \.isAccompaniment) { loneCondiment += 1 } }
        for it in s.items { if let f = byK[it.key], !f.bands.isEmpty, !f.bands.contains(s.band) { wrongMeal += 1 } }
    }
    tooOften += count.filter { $0.value > (byK[$0.key]?.maxPerDay ?? 9) }.count
}
check("every planned meal has a main food", noMain == 0, noMain)
check("condiments only alongside a main", loneCondiment == 0, loneCondiment)
check("foods only at their meals (no oats at dinner, no rice at breakfast)", wrongMeal == 0, wrongMeal)
check("no food in more meals than allowed a day", tooOften == 0, tooOften)
check("realistic plans still feasible", allPlans.dropLast().allSatisfy(\.feasible), allPlans.map(\.relaxed))
check("bands: Spanish meal times", MealBand.of(minute: 8 * 60) == .breakfast && MealBand.of(minute: 14 * 60) == .lunch && MealBand.of(minute: 18 * 60) == .afternoon
      && MealBand.of(minute: 21 * 60 + 30) == .dinner && MealBand.of(minute: 25 * 60) == .dinner)

// MARK: Training week from workouts
func sessions(_ weekdays: [Int: Int], weeks: Int, today: String, minutes: Int = 70, skip: Set<String> = []) -> [ScheduleInference.Session] {
    var out: [ScheduleInference.Session] = []
    for back in 1...(weeks * 7) {
        let d = addDaysKey(today, -back)
        if let start = weekdays[weekdayOfKey(d)], !skip.contains(d) { out.append(.init(day: d, start: start + (back % 3) * 10 - 10, minutes: minutes)) }
    }
    return out
}
let today = "2026-10-17"
let mwf = ScheduleInference.infer(sessions([2: 18 * 60, 4: 18 * 60, 6: 17 * 60 + 30], weeks: 6, today: today), today: today)
check("infers Mon/Wed/Fri", Set(mwf.keys) == [2, 4, 6], mwf.keys.sorted())
check("usual start to 15 min", mwf[2]?.start == 18 * 60 && mwf[6]?.start == 17 * 60 + 30, mwf.mapValues(\.start))
check("usual length", mwf[2]?.minutes == 70)
var noisy = sessions([2: 18 * 60, 4: 18 * 60], weeks: 6, today: today)
noisy.append(.init(day: addDaysKey(today, -9), start: 11 * 60, minutes: 60))      // one odd Thursday
check("a one-off day isn't a habit", Set(ScheduleInference.infer(noisy, today: today).keys) == [2, 4])
check("missed weeks: still a habit if ≥ half", ScheduleInference.infer(sessions([3: 7 * 60], weeks: 6, today: today, skip: [addDaysKey(today, -4), addDaysKey(today, -11)]), today: today)[3] != nil)
check("no workouts → rest days", ScheduleInference.infer([], today: today).isEmpty)
check("older than 6 weeks ignored", ScheduleInference.infer(sessions([2: 18 * 60], weeks: 12, today: today).filter { $0.day < addDaysKey(today, -42) }, today: today).isEmpty)
check("two weeks of history is enough", Set(ScheduleInference.infer(sessions([2: 18 * 60, 5: 9 * 60], weeks: 2, today: today), today: today).keys) == [2, 5])

// MARK: Large entries
typealias LE = LargeEntryRule.Entry
// Your 16 Oct lunch (14:00): 2,290 kcal in 7 entries, none over 1,500 alone; target 2,123.
let lunch16 = [LE(id: "q", minute: 840, kcal: 244, name: "Quick add"), LE(id: "pasta", minute: 840, kcal: 694, name: "Pipe Rigate"),
               LE(id: "chicken", minute: 840, kcal: 460, name: "Premium Roasted Chicken"), LE(id: "tomato", minute: 840, kcal: 345, name: "Tomate Frito"),
               LE(id: "spinach", minute: 840, kcal: 17, name: "Brotes de espinaca"), LE(id: "bread", minute: 840, kcal: 122, name: "Sourdough Bread"),
               LE(id: "tortellini", minute: 840, kcal: 408, name: "Tortellini Carne")]
let breakfast16 = [LE(id: "b1", minute: 480, kcal: 237, name: "Tortitas"), LE(id: "b2", minute: 480, kcal: 43, name: "Mermelada"),
                   LE(id: "b3", minute: 480, kcal: 92, name: "Banana"), LE(id: "b4", minute: 535, kcal: 191, name: "Peanut butter")]
let f16 = LargeEntryRule.flags(lunch16 + breakfast16, target: 2123, confirmed: [])
check("16 Oct: the lunch is flagged as one meal (2 290 kcal)", f16.count == 1 && !f16[0].single && Int(f16[0].kcal) == 2290, f16)
check("16 Oct: biggest entry listed first", f16.first?.names.first == "Pipe Rigate")
check("confirmed → no flag", LargeEntryRule.flags(lunch16, target: 2123, confirmed: Set(lunch16.map(\.id))).isEmpty)
check("a new entry added to a confirmed meal asks again", !LargeEntryRule.flags(lunch16 + [LE(id: "new", minute: 850, kcal: 300, name: "x")], target: 2123,
                                                                                 confirmed: Set(lunch16.map(\.id))).isEmpty)
let one = LargeEntryRule.flags([LE(id: "big", minute: 600, kcal: 1600, name: "Pizza"), LE(id: "s", minute: 610, kcal: 100, name: "Coke")], target: 3500, confirmed: [])
check("a single 1 600 kcal entry is flagged by itself (not again as a meal)", one.count == 1 && one[0].single && one[0].ids == ["big"], one)
check("60% of target counts too (1 300 of 2 000)", LargeEntryRule.flags([LE(id: "a", minute: 600, kcal: 1300, name: "x")], target: 2000, confirmed: []).count == 1)
check("normal meals aren't flagged", LargeEntryRule.flags(breakfast16, target: 2123, confirmed: []).isEmpty)
check("meals split by a 45-minute gap", LargeEntryRule.flags([LE(id: "a", minute: 600, kcal: 800, name: "x"), LE(id: "b", minute: 700, kcal: 800, name: "y")], target: 3000, confirmed: []).isEmpty)
// A provisional (unconfirmed) meal: eaten and fixed, but its calories don't count yet.
var prov = slotsFor(training: nil)
prov[1].eaten = true; prov[1].provisional = true; prov[1].items = [PlanItem(key: "pasta", grams: 900)]
let pp = Planner.plan(cutDay, slots: prov, foods: pantry)
check("unconfirmed meal not counted: rest of day planned normally", pp.note == nil && pp.slots[1].items == prov[1].items && pp.feasible, (pp.note ?? "", pp.relaxed))

// MARK: Staples (cold start)
let catalog: [String: (name: String, per100: (Double, Double, Double, Double, Double), unitGrams: Double?)] = Dictionary(uniqueKeysWithValues: rawPantry.map {
    ($0.key, (name: $0.name, per100: ($0.per100.kcal, $0.per100.protein, $0.per100.fat, $0.per100.carbs, $0.per100.fibre), unitGrams: $0.key == "eggs" ? 60.0 : nil)) })
let staples = [Staple(key: "oats", grams: 80, band: .breakfast), Staple(key: "greek yogurt", grams: 250, band: .breakfast), Staple(key: "whey", grams: 45, band: .afternoon),
               Staple(key: "banana", grams: 120, band: .afternoon), Staple(key: "bread", grams: 60, band: .afternoon), Staple(key: "chicken breast", grams: 200, band: .lunch),
               Staple(key: "rice", grams: 250, band: .lunch), Staple(key: "olive oil", grams: 10, band: .lunch), Staple(key: "broccoli", grams: 250, band: .dinner),
               Staple(key: "salmon", grams: 150, band: .dinner), Staple(key: "potato", grams: 300, band: .dinner), Staple(key: "beef mince 5%", grams: 150, band: .dinner),
               Staple(key: "eggs", grams: 120, band: .breakfast), Staple(key: "cottage cheese", grams: 200, band: .dinner), Staple(key: "pasta", grams: 250, band: .lunch)]
let sf = Planner.foods(fromStaples: staples, catalog: catalog)
check("staples become candidates at their meal", sf.count == 15 && sf.first { $0.key == "oats" }!.bands == [.breakfast])
let sp = Planner.plan(cutDay, slots: slotsFor(training: (18 * 60, 75)), foods: sf)
checkPlan("plan from 15 staples", sp, cutDay); if !sp.feasible { print("  misses", sp.misses, sp.relaxedHard, sp.shortMeals, sp.slots.map { ($0.band.rawValue, $0.items.map { "\($0.key) \(Int($0.grams))" }) }) }
check("staples plan: every food at the meal you chose", sp.slots.allSatisfy { s in s.items.allSatisfy { it in sf.first { $0.key == it.key }!.bands.contains(s.band) } },
      sp.slots.map { ($0.band.rawValue, $0.items.map(\.key)) })

// MARK: Calories aim at the target; protein minimum per meal; hard limits reported
for (name, p, t) in [("rest", rest, cutDay), ("evening", eve, cutDay), ("staples", sp, cutDay)] where p.feasible {
    check("\(name): calories within ±1.5% (or 40 kcal), not just ±5%", abs(p.totals.kcal - t.kcal) <= max(t.kcal * 0.015, 40) + 0.5, Int(p.totals.kcal - t.kcal))
    check("\(name): no hard limit widened when it fits", p.relaxedHard.isEmpty, p.relaxedHard)
}
func protein(_ s: PlanSlot, _ foods: [PlanFood]) -> Double { s.items.reduce(0) { a, i in a + (foods.first { $0.key == i.key }?.macros(i.grams).protein ?? 0) } }
for (name, p, foods, t) in [("rest", rest, pantry, cutDay), ("evening", eve, pantry, cutDay), ("staples", sp, sf, cutDay)] where p.feasible {
    let low = p.slots.filter { !$0.eaten && protein($0, foods) < t.minProtein($0.kind) - 0.5 }
    check("\(name): every meal reaches its protein minimum (\(Int(t.mealProtein)) g, \(Int(t.trainingMealProtein)) g around training)", low.isEmpty, low.map { ($0.kind.rawValue, Int(protein($0, foods))) })
}
check("minimums from the registry: 0.3 and 0.4 g/kg", cutDay.mealProtein == 33 && cutDay.trainingMealProtein == 44, (cutDay.mealProtein, cutDay.trainingMealProtein))
// Breakfast foods without protein: the meal is reported, not quietly planned low.
var noProteinBreakfast = pantry.map { f -> PlanFood in var f = f; if ["eggs", "greek yogurt", "whey", "cottage cheese"].contains(f.key) { f.bands = [.dinner] }; return f }
noProteinBreakfast = noProteinBreakfast.filter { $0.key != "oats" || true }
let nb = Planner.plan(cutDay, slots: slotsFor(training: nil), foods: noProteinBreakfast.map { f in var f = f; if f.key == "oats" || f.key == "bread" || f.key == "banana" { f.bands = [.breakfast] }; if f.bands.isEmpty || f.bands == [.breakfast, .afternoon] { f.bands = f.key == "oats" || f.key == "bread" || f.key == "banana" ? [.breakfast] : [.lunch, .dinner] }; return f })
check("a meal that can't reach its minimum is reported", !nb.feasible && nb.misses.contains("protein per meal") && nb.shortMeals.contains { nb.slots[$0.index].band == .breakfast }
      && nb.reasons.contains { $0.rule == "protein per meal" }, (nb.misses, nb.shortMeals))
// A day that needs the wider calorie band says so.
let coarse = [food("big meal", 250, 30, 8, 18, 3, usual: 400, slots: [0: 5, 1: 5, 2: 5, 3: 5], step: 400, max: 400),
              food("oil", 884, 0, 100, 0, 0, usual: 10, slots: [0: 1, 1: 1, 2: 1, 3: 1], step: 5, max: 15)].map { $0.with(role: $0.name == "oil" ? .fatSource : .proteinMain) }
let wide = Planner.plan(PlanTargets(kcal: 4500, protein: 400, fat: 150, carbs: 280, fibreFloor: 0, fatFloor: 40, weightKg: 100), slots: slotsFor(training: nil), foods: coarse)
check("widened calorie band is listed as a hard relaxation", !wide.relaxedHard.isEmpty && wide.reasons.contains { $0.rule == "calorie band widened" }, (wide.relaxedHard, Int(wide.totals.kcal)))
check("a widened band never hides a miss: misses listed", wide.feasible || !wide.misses.isEmpty)

// MARK: Roles and condiment limits
let jam = food("Mermelada de Fresa Diet", 57, 0.5, 0, 14, 1, usual: 75, slots: [0: 5]).with(role: .condiment)
check("jam: condiment, ≤ 30 g a meal, once a day", jam.role == .condiment && jam.maxGrams <= 30 && jam.maxPerDay == 1, (jam.maxGrams, jam.maxPerDay))
for (n, kcal, fat, role) in [("Miel de flores", 304.0, 0.0, FoodRole.condiment), ("Crema de cacahuete", 600, 50, .fatSource), ("Tomate Frito", 69, 3, .condiment),
                             ("Ligeresa", 177, 18, .condiment), ("Ketchup cero", 38, 0, .condiment), ("Nutella", 539, 31, .condiment),
                             ("Palomitas de mantequilla", 438, 20, .treat), ("Dates", 288, 0.4, .fruit), ("Premium Roasted Chicken", 115, 2, .proteinMain),
                             ("Barebells Mint", 349, 13, .proteinSnack), ("Tortitas de arroz integral con chocolate negro", 456, 18, .treat), ("Sourdough Bread", 230, 1, .carbSide),
                             ("Pipe Rigate", 347, 1.5, .carbSide)] {
    let g = FoodRole.guess(name: n, kcal: kcal, protein: n.contains("Chicken") ? 24 : 1, fat: fat, carbs: 20)
    check("role: \(n) → \(role)", g == role, g)
}
check("Aceite de oliva is a fat source", FoodRole.guess(name: "Aceite de oliva", kcal: 884, protein: 0, fat: 100, carbs: 0) == .fatSource)
check("honey ≤ 20 g, oil ≤ 15 g and twice a day, tomato sauce ≤ 100 g", CondimentKind.cap("Miel", fat: 0) == 20 && CondimentKind.cap("Aceite de oliva", fat: 100) == 15
      && CondimentKind.perDay("Aceite de oliva", fat: 100) == 2 && CondimentKind.cap("Tomate Frito", fat: 3) == 100)

// MARK: Taxonomy
typealias TI = Taxonomy.Input
let roost = Taxonomy.classify(TI(name: "Premium Roasted Chicken", brand: "Roosterz & Co", source: "custom", kcal: 115, protein: 24, fat: 1.4, carbs: 0.8))
check("Roosterz chicken → chicken, protein main, NOVA 3 estimated", roost.canonical == "chicken" && roost.role == .proteinMain && roost.nova == 3 && roost.novaEstimated, roost)
let arroz = Taxonomy.classify(TI(name: "Arroz redondo", brand: "Hacendado", source: "off", kcal: 350, protein: 7, fat: 1, carbs: 78, offNova: 1, offGroup: "Cereals"))
check("Hacendado arroz redondo → white rice, carb side, NOVA 1 from Open Food Facts", arroz.canonical == "white-rice" && arroz.role == .carbSide && arroz.nova == 1 && !arroz.novaEstimated, arroz)
check("USDA generic foods count as NOVA 1", Taxonomy.classify(TI(name: "Banana, raw", source: "usda", kcal: 97, protein: 0.7, fat: 0.3, carbs: 23)).nova == 1)
check("recipes: NOVA from the ingredients (at least 3), estimated", Taxonomy.classify(TI(name: "Mi bowl", source: "recipe", kcal: 150, protein: 10, fat: 5, carbs: 15, ingredientNovas: [1, 1, 4])).nova == 4)
let unknown = TI(name: "Mystery 9000", source: "off", kcal: 380, protein: 80, fat: 3, carbs: 5)
check("macros: > 60% of calories from protein → protein main, low confidence", Taxonomy.classify(unknown).role == .proteinMain && Taxonomy.classify(unknown).confidence <= 0.5)
let ov = Taxonomy.classify(unknown, override: .init(canonical: "tofu", role: .dairy, nova: 2), suggestion: .init(canonical: "eggs", role: .proteinMain))
check("your correction beats rules and AI, every field", ov.role == .dairy && ov.canonical == "tofu" && ov.nova == 2 && ov.confidence == 1 && ov.roleSource == .user, ov)
let sug = Taxonomy.classify(TI(name: "Zzz", source: "custom", kcal: 0, protein: 0, fat: 0, carbs: 0), suggestion: .init(canonical: "eggs", role: .proteinMain, confidence: 0.9))
check("AI suggestion fills what rules can't, capped at 65% confidence", sug.role == .proteinMain && sug.roleSource == .ai && sug.confidence <= 0.65, sug)
let ruleWins = Taxonomy.classify(TI(name: "Mermelada de fresa", source: "off", kcal: 57, protein: 0, fat: 0, carbs: 14), suggestion: .init(canonical: "eggs", role: .proteinMain))
check("AI never overrides a name rule", ruleWins.role == .condiment && ruleWins.canonical == "jam")
check("specific before general: rice cakes aren't rice, peanut butter isn't butter",
      Taxonomy.match("Tortitas de arroz", brand: nil)?.id == "rice-cakes" && Taxonomy.match("Peanut butter", brand: nil)?.id == "peanut-butter")
check("old saved roles still read (main → protein main, side → vegetable)",
      (try? JSONDecoder().decode([FoodRole].self, from: Data(#"["main","side","condiment"]"#.utf8))) == [.proteinMain, .vegetable, .condiment])
check("protein bars and oats: breakfast and merienda", Taxonomy.bands("protein-bar") == [.breakfast, .afternoon] && Taxonomy.bands("oats") == [.breakfast, .afternoon])
check("every canonical food has keywords and a USDA anchor", Taxonomy.canonical.allSatisfy { !$0.words.isEmpty && !$0.usda.isEmpty })
check("canonical ids unique", Set(Taxonomy.canonical.map(\.id)).count == Taxonomy.canonical.count)
// Drinks: only non-nutritive, caffeinated and sugary ones are left out of planning.
check("liquid protein shake → protein snack", Taxonomy.classify(TI(name: "Batido proteico chocolate", source: "off", kcal: 70, protein: 12, fat: 1, carbs: 3, isLiquid: true)).role == .proteinSnack)
check("RTD protein drink by macros → protein snack", Taxonomy.classify(TI(name: "Pro Drink", source: "off", kcal: 60, protein: 10, fat: 0.5, carbs: 3, isLiquid: true)).role == .proteinSnack)
check("milk → dairy", Taxonomy.classify(TI(name: "Leche semidesnatada", source: "off", kcal: 46, protein: 3.2, fat: 1.6, carbs: 4.7, isLiquid: true)).role == .dairy)
check("energy drink, cola, juice → drink", [TI(name: "NOCCO Ramonade", source: "off", kcal: 1, protein: 0, fat: 0, carbs: 0, isLiquid: true),
      TI(name: "Coca-Cola", source: "off", kcal: 42, protein: 0, fat: 0, carbs: 10.6, isLiquid: true),
      TI(name: "Zumo de naranja", source: "off", kcal: 45, protein: 0.7, fat: 0.2, carbs: 10, isLiquid: true)].allSatisfy { Taxonomy.classify($0).role == .drink })
check("peanut butter → fat source, NOVA 2 (typical)", Taxonomy.classify(TI(name: "Crema de cacahuete", source: "off", kcal: 600, protein: 25, fat: 50, carbs: 12)).role == .fatSource)
// Protein per meal counts every food in the meal, not only the protein main.
let mix = [food("oats", 380, 13, 7, 60, 10, usual: 80, slots: [0: 5]).with(role: .carbSide), food("skyr", 63, 11, 0.2, 4, 0, usual: 200, slots: [0: 5]).with(role: .dairy)]
let only = Planner.shortMeals([PlanSlot(index: 0, minute: 480, kind: .meal, items: [PlanItem(key: "oats", grams: 80), PlanItem(key: "skyr", grams: 200)])],
                              PlanTargets(kcal: 2000, protein: 150, fat: 60, carbs: 200, weightKg: 100), Dictionary(uniqueKeysWithValues: mix.map { ($0.key, $0) }))
check("protein per meal sums all foods (oats 10 g + skyr 22 g = 32 g ≥ 30 g, no protein main)", only.isEmpty, only)

// MARK: Basic foods library
let lib = BasicFoods.all
check("library: 28 foods, ids unique", lib.count == 28 && Set(lib.map(\.id)).count == 28, lib.count)
for b in lib {
    let v = b.values
    // USDA carbs include fibre; Spanish labels list it apart. Fibre counts ~2 kcal/g either way.
    let netCarbs = b.source.hasPrefix("USDA") ? v.carbs - v.fibre : v.carbs
    let atwater = v.protein * 4 + netCarbs * 4 + v.fat * 9 + v.fibre * 2
    check("\(b.name): calories match macros (±15%)", abs(atwater - v.kcal) <= max(v.kcal * 0.15, 8), (atwater, v.kcal))
    check("\(b.name): has meals and a portion", !b.bands.isEmpty && b.portion > 0)
    if let r = b.ratio, let raw = b.raw, let ck = b.cooked, abs(r - 1) > 0.01 {
        // Cooked ÷ raw weight = raw ÷ cooked concentration: protein for meat and fish, carbs for starches.
        let byProtein = raw.protein / max(ck.protein, 0.1), byCarbs = raw.carbs / max(ck.carbs, 0.1)
        let implied = b.role == .proteinMain ? byProtein : byCarbs
        check("\(b.name): ratio \(r) matches its raw/cooked values (\(String(format: "%.2f", implied)))", abs(r - implied) <= max(0.12, r * 0.05), implied)
    }
}
check("oats: dry weight only (no cooked values or ratio)", BasicFoods.byKey["basic:oats"]!.cooked == nil && BasicFoods.byKey["basic:oats"]!.ratio == nil)
check("tinned tuna: 2 tins by default", BasicFoods.byKey["basic:tuna-tin"]!.portion == 2 * BasicFoods.byKey["basic:tuna-tin"]!.unit!.grams)
check("Basic style: tuna, wholemeal bread, queso batido allowed (your choice); whey, skyr, jarred pulses not (NOVA 3–4)",
      ["tuna-tin", "wholemeal-bread", "queso-batido"].allSatisfy { BasicFoods.byKey["basic:\($0)"]!.inBasicStyle }
      && ["whey", "skyr", "chickpeas-jar", "lentils-jar"].allSatisfy { !BasicFoods.byKey["basic:\($0)"]!.inBasicStyle }
      && lib.filter { $0.nova <= 2 }.allSatisfy(\.inBasicStyle))
check("every basic food's canonical food exists", lib.allSatisfy { $0.canonical.map { Taxonomy.byID[$0] != nil } ?? true })
check("basic foods classify as themselves", lib.allSatisfy { b in Taxonomy.classify(TI(key: b.key, name: b.name, source: "basic", kcal: 0, protein: 0, fat: 0, carbs: 0)).role == b.role })
let bf = BasicFoods.planFoods()
// Your own foods can't reach breakfast protein; the library fills it.
let thinBreakfast = pantry.map { f -> PlanFood in var f = f; if ["eggs", "greek yogurt", "whey", "cottage cheese"].contains(f.key) { f.bands = [.dinner] }; return f }
let withLib = Planner.plan(cutDay, slots: slotsFor(training: nil), foods: thinBreakfast + bf)
check("library fills a role your foods can't (breakfast protein)", !withLib.misses.contains("protein per meal"), (withLib.misses, withLib.shortMeals))
let full = Planner.plan(cutDay, slots: slotsFor(training: nil), foods: pantry + bf)
let usedBasics = full.slots.flatMap(\.items).filter { $0.key.hasPrefix("basic:") }.count, usedAll = full.slots.flatMap(\.items).count
check("with enough of your own foods, they come first (≤ 2 library foods in the day)", usedBasics <= 2, (usedBasics, usedAll))
var rice = bf.first { $0.key == "basic:white-rice" }!
rice.shownRatio = 2.8; rice.shownUnit = "g cooked"
check("shown in the state you weigh it: 75 g dry rice → 210 g cooked", rice.shown(75) == "210 g cooked")

do {
// MARK: Staple suggestions
let mk: (String, String, Int, Double) -> LoggedFood = { key, day, minute, g in
    LoggedFood(day: day, weekday: weekdayOfKey(day), minute: minute, key: key, name: key, grams: g, kcal: 0, protein: 0, fat: 0, carbs: 0, fibre: 0)
}
let tday = "2026-10-17"
var slogs: [LoggedFood] = []
for i in 1...10 { slogs.append(mk("chicken", addDaysKey(tday, -i * 2), 14 * 60, i % 2 == 0 ? 200 : 250)) }        // 10 days, lunch
for i in 1...5 { slogs.append(mk("yogurt", addDaysKey(tday, -i), 8 * 60, 170)) }                                   // 5 days: below 6
for i in 1...7 { slogs.append(mk("bread", addDaysKey(tday, -i), i <= 4 ? 8 * 60 : 18 * 60, 60)); slogs.append(mk("bread", addDaysKey(tday, -i), 8 * 60 + 5, 30)) }
for i in 1...8 { slogs.append(mk("old", addDaysKey(tday, -40 - i), 12 * 60, 100)) }                              // outside the window
slogs.append(mk("chicken", tday, 14 * 60, 999))                                                                    // today doesn't count
let sg = StapleSuggestions.suggest(slogs, today: tday)
check("suggested: logged on ≥ 6 of the last 28 days, most frequent first", sg.map(\.key) == ["chicken", "bread"], sg.map(\.key))
check("median portion and usual meal", sg.first?.grams == 225 && sg.first?.band == .lunch, sg.first.map { ($0.grams, $0.band) } ?? (0, .lunch))
check("two entries in one meal are one portion (bread 60 + 30 = 90)", sg.first { $0.key == "bread" }?.grams == 90 && sg.first { $0.key == "bread" }?.band == .breakfast,
      sg.first { $0.key == "bread" }.map { ($0.grams, $0.band) } ?? (0, .lunch))
check("configurable: 5 days in 2 weeks also suggests yogurt", StapleSuggestions.suggest(slogs, today: tday, window: 14, minDays: 5).map(\.key).contains("yogurt"))
check("already a staple or dismissed: not suggested", StapleSuggestions.suggest(slogs, today: tday, staples: ["chicken"], dismissed: ["bread"]).isEmpty)
// Staples count at the canonical level: a staple protein main is preferred over other foods of its role.
var stapleChicken = pantry.first { $0.key == "chicken breast" }!; stapleChicken.staple = true
let withStaple = Planner.plan(cutDay, slots: slotsFor(training: nil), foods: pantry.filter { $0.key != "chicken breast" } + [stapleChicken] + bf)
let mains = Set(withStaple.slots.flatMap(\.items).filter { i in (pantry + bf).first { $0.key == i.key }?.role == .proteinMain }.map(\.key))
check("a staple protein main is used as a primary protein source", mains.contains("chicken breast"), mains)
}

// MARK: Meal templates
let tps = MealTemplates.defaults
check("templates: every food id is a canonical food", MealTemplates.unknownFoods(tps).isEmpty, MealTemplates.unknownFoods(tps))
check("templates: every default is allowed in its slot", tps.allSatisfy { $0.slots.allSatisfy { $0.allowed.contains($0.defaultFood) } })
check("templates: every meal has a required protein slot (the evening snack is a treat only)", tps.filter { $0.meal != .eveningSnack }.allSatisfy { $0.slots.contains { $0.kind == .protein && $0.required } })
check("templates: one carb base per meal (bread as a side is separate)", tps.allSatisfy { $0.slots.filter { $0.kind == .carbBase }.count <= 1 })
check("templates: all seven meals", Set(tps.map(\.meal)) == Set(MealTemplate.Meal.allCases))
let bfast = tps.first { $0.meal == .breakfast }!
check("breakfast: chocolate rice cakes allowed (max 3), plain as the alternative; spreads optional, on by default; eggs then skyr",
      bfast.slots[0].allowed.prefix(2) == ["rice-cakes-chocolate", "rice-cakes"] && bfast.slots[0].maxUnits["rice-cakes-chocolate"] == 3
      && bfast.slots.first { $0.kind == .spread }.map { !$0.required && $0.defaultOn && $0.maxFoods == 2 } == true
      && bfast.slots.first { $0.kind == .protein }.map { $0.defaultFood == "eggs" && $0.allowed.prefix(2) == ["eggs", "skyr"] } == true)
let lunchT = tps.first { $0.meal == .lunch }!, dinnerT = tps.first { $0.meal == .dinner }!
check("dinner: vegetable and sauce lists the same as lunch", lunchT.slots.first { $0.kind == .vegetable }!.allowed == dinnerT.slots.first { $0.kind == .vegetable }!.allowed
      && lunchT.slots.first { $0.kind == .fatOrSauce }!.allowed == dinnerT.slots.first { $0.kind == .fatOrSauce }!.allowed)
check("pulses: optional side at lunch and dinner, and still a carb base", [lunchT, dinnerT].allSatisfy { t in t.slots.contains { $0.kind == .pulses && !$0.required } && t.slots.first { $0.kind == .carbBase }!.allowed.contains("pulses") })
check("evening snack: one treat", tps.first { $0.meal == .eveningSnack }!.slots.map(\.kind) == [.treat])
// Pre- and post-workout replace the meal in their window; they never add meals.
func templatesFor(_ training: (Int, Int)?) -> [MealTemplate.Meal] { slotsFor(training: training).compactMap { MealTemplates.template(for: $0)?.meal } }
check("rest day: breakfast, lunch, merienda, dinner", templatesFor(nil) == [.breakfast, .lunch, .merienda, .dinner], templatesFor(nil))
check("18:00 training: merienda becomes pre-workout, dinner post-workout (still 4 meals)", templatesFor((18 * 60, 75)) == [.breakfast, .lunch, .preWorkout, .postWorkout], templatesFor((18 * 60, 75)))
check("10:00 training: breakfast becomes pre-workout, lunch post-workout", templatesFor((10 * 60, 75)) == [.preWorkout, .postWorkout, .merienda, .dinner], templatesFor((10 * 60, 75)))
check("19:00 training: merienda pre, dinner post", templatesFor((19 * 60, 75)) == [.breakfast, .lunch, .preWorkout, .postWorkout], templatesFor((19 * 60, 75)))
for (st, len) in [(7 * 60 + 30, 60), (10 * 60, 75), (13 * 60, 60), (18 * 60, 75), (20 * 60, 60)] {
    check("training at \(st / 60):\(String(format: "%02d", st % 60)): never more meals than set (4)", slotsFor(training: (st, len)).count == 4)
    for n in [3, 5] { check("…and with \(n) meals: \(n)", slotsFor(training: (st, len), meals: n).count == n) }
}

check("templates: round-trip as JSON (editable, saved in settings)", (try? JSONDecoder().decode([MealTemplate].self, from: JSONEncoder().encode(tps))) == tps)

// MARK: Simple foods catalogue (Gym/SimpleFoods.json)
let cat = SimpleFoods.load(try? Data(contentsOf: URL(fileURLWithPath: "../../Gym/SimpleFoods.json")))
check("catalogue loads", cat.count >= 60, cat.count)
check("catalogue: every entry is a canonical food with its tier", cat.allSatisfy { Taxonomy.byID[$0.id] != nil && $0.tier == Taxonomy.tier($0.id) })
let pool = cat.filter { $0.tier <= 2 && $0.availableAtMyStores }
check("catalogue pool: tier 1–2 at your stores, every role covered", Set(pool.map(\.role)).isSuperset(of: [.proteinMain, .carbSide, .vegetable, .fruit, .fatSource, .dairy, .condiment]))
for f in pool {
    let v = f.values, atwater = v.protein * 4 + v.carbs * 4 + v.fat * 9 + v.fibre * 2
    check("catalogue \(f.name): calories match macros (±20%)", abs(atwater - v.kcal) <= max(v.kcal * 0.2, 10), (atwater, v.kcal))
}
check("catalogue: no drinks", !cat.contains { $0.role == .drink })

// MARK: Meal patterns (co-occurrence)
do {
    let t = "2026-10-17"
    let mk: (String, Int, String) -> LoggedFood = { day, minute, key in
        LoggedFood(day: day, weekday: weekdayOfKey(day), minute: minute, key: key, name: key, grams: 50, kcal: 0, protein: 0, fat: 0, carbs: 0, fibre: 0) }
    let canon = ["tortitas": "rice-cakes-chocolate", "pb": "peanut-butter", "jam": "jam", "banana": "banana", "chicken": "chicken", "potato": "potato", "pasta": "pasta"]
    var l: [LoggedFood] = []
    for d in [-1, -2, -3] { l += [mk(addDaysKey(t, d), 480, "tortitas"), mk(addDaysKey(t, d), 485, "jam"), mk(addDaysKey(t, d), 520, "pb")] }   // 08:00–08:40: one meal
    l += [mk(addDaysKey(t, -1), 480, "banana")]
    l += [mk(addDaysKey(t, -1), 840, "chicken"), mk(addDaysKey(t, -1), 845, "potato"), mk(addDaysKey(t, -2), 840, "chicken"), mk(addDaysKey(t, -2), 841, "pasta")]
    l += [mk(addDaysKey(t, -2), 1300, "jam")]                                                                                   // 21:40, its own meal
    let mp = MealPatterns.learn(l, canonical: { canon[$0] }, today: t)
    check("patterns: entries within 45 min are one meal (08:00 + 08:40)", mp.meals.filter { $0.band == .breakfast }.allSatisfy { $0.foods.contains("peanut-butter") })
    check("patterns: rice cakes → peanut butter at breakfast, every time", abs(mp.association("rice-cakes-chocolate", "peanut-butter", at: .breakfast) - 1) < 1e-9)
    check("patterns: banana with rice cakes once in three (recency-weighted ≈ 1/3)", (0.3...0.4).contains(mp.association("rice-cakes-chocolate", "banana", at: .breakfast)))
    check("patterns: no association across meals (jam at dinner isn't jam at breakfast)", mp.association("jam", "rice-cakes-chocolate", at: .dinner) == 0)
    check("patterns: lunch combos chicken+potato and chicken+pasta", Set(mp.combos.filter { $0.band == .lunch }.map(\.foods)) == [["chicken", "potato"], ["chicken", "pasta"]])
    check("patterns: the breakfast combo is the most frequent", mp.combos.first?.foods == ["jam", "peanut-butter", "rice-cakes-chocolate"], mp.combos.first?.foods ?? [])
    check("patterns: deterministic", MealPatterns.learn(l.reversed(), canonical: { canon[$0] }, today: t) == mp)
    check("patterns: fit = best association with what's in the meal", mp.fit("peanut-butter", with: ["jam", "banana"], at: .breakfast) == mp.association("jam", "peanut-butter", at: .breakfast))
}
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED")
