// Weekly budget: under-eating earlier in the week raises the days left, within 10% a day (at most −150 kcal a day after a big day).
import Foundation
import SwiftData
setvbuf(stdout, nil, _IONBF, 0)
var fails = 0
func check(_ n: String, _ ok: Bool, _ got: Any = "") { print(ok ? "ok   \(n)" : "FAIL \(n) got \(got)"); if !ok { fails += 1 } }
MainActor.assumeIsolated {
    let c = try! ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let ctx = c.mainContext
    let p = Profile(sex: .male, birthDate: Date(timeIntervalSince1970: 0), heightCm: 180, activity: .moderate, weightUnit: .kg, energyUnit: .kcal)
    ctx.insert(p)
    let n = dayNumber(dayKey()), monday = dayKey(number: n - ((n + 3) % 7 + 7) % 7)
    let set = TargetSet(targets: Targets(kcal: 2500, protein: 180, fat: 80, carbs: 260), expenditure: 3000, reason: "setup")
    set.fromDay = addDays(monday, -7); ctx.insert(set)
    let today = dayKey(), daysBefore = daysBetween(monday, today)
    for i in 0..<daysBefore {                                   // every earlier day this week: 600 under, in 4 meals
        for m in 0..<4 {
            ctx.insert(FoodEntry(day: addDays(monday, i), time: Date(timeIntervalSince1970: Double(m) * 4 * 3600), name: "x", brand: nil, foodKey: nil, amount: 1, unit: "", grams: 0,
                                 nutrients: Nutrients(kcal: 475, protein: 45, fat: 15, carbs: 42.5)))
        }
    }
    ctx.commit()
    check("off: plain targets", ctx.dayTargets(on: today)?.kcal == 2500)
    p.weeklyBudget = true; ctx.commit()
    let left = Double(7 - daysBefore)
    let expected = 2500 + min(250, 600 * Double(daysBefore) / left)
    let got = ctx.dayTargets(on: today)?.kcal ?? -1
    check("on: \(daysBefore) days 600 under → today \(Int(expected))", daysBefore == 0 ? got == 2500 : abs(got - expected) < 0.01, got)
    check("protein unchanged", ctx.dayTargets(on: today)?.protein == 180)
    // A single 1 900 kcal entry looks like a typo: until confirmed, its day doesn't move the budget.
    if daysBefore > 0 {
        ctx.insert(FoodEntry(day: monday, time: Date(timeIntervalSince1970: 20 * 3600), name: "typo", brand: nil, foodKey: nil, amount: 1, unit: "", grams: 0,
                             nutrients: Nutrients(kcal: 1900, protein: 10, fat: 10, carbs: 400)))
        ctx.commit()
        let without = 2500 + min(250, 600 * Double(daysBefore - 1) / left)
        check("unconfirmed big entry: that day left out", abs((ctx.dayTargets(on: today)?.kcal ?? -1) - without) < 0.01, ctx.dayTargets(on: today)?.kcal ?? -1)
        ctx.confirmLarge(ctx.largeFlags(on: monday).flatMap(\.ids), on: monday)
        let over = 2500 + max(-150, min(250, (600 * Double(daysBefore) - 1900) / left))
        check("confirmed: counts, and the cut is capped at 150 a day", abs((ctx.dayTargets(on: today)?.kcal ?? -1) - over) < 0.01, (ctx.dayTargets(on: today)?.kcal ?? -1, over))
    }
    let r = Micro.fromOFF { ["caffeine_100g": 0.032, "alcohol_100g": 5.0][$0] }
    check("caffeine 0,032 g → 32 mg", abs((r?["caffeine"] ?? 0) - 32) < 1e-9, r ?? [:])
    check("alcohol 5 % vol → 3,9 g", abs((r?["alcohol"] ?? 0) - 3.945) < 1e-9)
}
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
