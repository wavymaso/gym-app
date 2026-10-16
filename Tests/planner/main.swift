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
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED")
