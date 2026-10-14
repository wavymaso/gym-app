// Weekly budget: under-eating earlier in the week raises the days left, within ±20%.
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
    for i in 0..<daysBefore {                                   // every earlier day this week: 600 under
        ctx.insert(FoodEntry(day: addDays(monday, i), time: Date(), name: "x", brand: nil, foodKey: nil, amount: 1, unit: "", grams: 0,
                             nutrients: Nutrients(kcal: 1900, protein: 180, fat: 60, carbs: 170)))
    }
    try! ctx.save()
    check("off: plain targets", ctx.dayTargets(on: today)?.kcal == 2500)
    p.weeklyBudget = true; try! ctx.save()
    let left = Double(7 - daysBefore)
    let expected = 2500 + min(500, 600 * Double(daysBefore) / left)
    let got = ctx.dayTargets(on: today)?.kcal ?? -1
    check("on: \(daysBefore) days 600 under → today \(Int(expected))", daysBefore == 0 ? got == 2500 : abs(got - expected) < 0.01, got)
    check("protein unchanged", ctx.dayTargets(on: today)?.protein == 180)
    let r = Micro.fromOFF { ["caffeine_100g": 0.032, "alcohol_100g": 5.0][$0] }
    check("caffeine 0,032 g → 32 mg", abs((r?["caffeine"] ?? 0) - 32) < 1e-9, r ?? [:])
    check("alcohol 5 % vol → 3,9 g", abs((r?["alcohol"] ?? 0) - 3.945) < 1e-9)
}
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
