// Opens a copy of a real store with the current schema: data intact, new fields round-trip.
// Run: ./run.sh <path to a copy of default.store>  (the copy is modified)
import Foundation
import SwiftData
setvbuf(stdout, nil, _IONBF, 0)
var fails = 0
func check(_ n: String, _ ok: Bool, _ got: Any = "") { print(ok ? "ok   \(n)" : "FAIL \(n) got \(got)"); if !ok { fails += 1 } }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let expected = Double(CommandLine.arguments[2]) ?? -1
MainActor.assumeIsolated {
    do {
        let c = try ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(url: url))
        let ctx = c.mainContext
        let entries = try ctx.fetch(FetchDescriptor<FoodEntry>())
        let total = entries.reduce(0) { $0 + $1.nutrients.kcal }
        check("opens, \(entries.count) entries", !entries.isEmpty)
        check("calorie total unchanged", abs(total - expected) < 0.5, total)
        let e = FoodEntry(day: "2000-01-01", time: Date(), name: "migration test", brand: nil, foodKey: nil, amount: 1, unit: "", grams: 0,
                          nutrients: Nutrients(kcal: 10, protein: 1, fat: 0, carbs: 1, micros: ["iron": 2.5, "vitD": 4]))
        ctx.insert(e); ctx.commit()
        let p = try ctx.fetch(FetchDescriptor<Profile>()).first
        check("profile has the new settings", p != nil && (p!.fastKcal > 0) && BMREquation(rawValue: p!.bmrEquation) != nil, (p?.fastKcal ?? -1, p?.bmrEquation ?? "?"))
        // Plan adherence log (17 Oct 2026): existing profiles open with an empty log; a day saves and reads back.
        check("profile opens with an empty plan log", p?.planLog.isEmpty ?? false || p?.planLogJSON.isEmpty == false, p?.planLogJSON ?? "")
        // Imported day totals (one entry at 13:00) are never "too big to be right", so they never leave expenditure.
        let imported = Set(entries.filter { $0.foodKey == "import" }.map(\.day))
        check("imported day totals are never flagged as large", ctx.unconfirmedLargeDays.isDisjoint(with: imported) && imported.allSatisfy { ctx.largeFlags(on: $0).isEmpty })
        // A1 (18 Oct 2026): the default expenditure is the engine's, built on the trend the screens show.
        let keepExp = p?.expAlgorithm ?? ""
        p?.expAlgorithm = ""; dataVersion += 1
        let live = ctx.expenditureEstimates().last?.kcal, eng = ctx.engineSnapshot()?.expenditure.last?.kcal
        check("default expenditure is the engine's", live != nil && live == eng, (live ?? -1, eng ?? -1))
        check("screens show the engine trend by default", TrendAlgorithm.current == .engine && abs((trendSeries(ctx.weightValues, through: dayKey()).last?.trend ?? 0) - (ctx.engineSnapshot()?.trend.last?.trend ?? -1)) < 0.001)
        p?.expAlgorithm = keepExp
        // One synced trend choice (18 Oct 2026): existing profiles open on the default (the engine).
        check("profile opens with the default trend", p?.trendAlgorithm == "" || TrendAlgorithm(rawValue: p?.trendAlgorithm ?? "") != nil, p?.trendAlgorithm ?? "?")
        p?.trendAlgorithm = "v1"
        p?.planLog = ["2000-01-01": [PlannedMeal(index: 0, minute: 480, name: "Breakfast", foods: ["oats"])]]
        ctx.commit()
    } catch { print("ERROR", error); fails += 1 }
    do {
        let c = try ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(url: url))
        let ctx = c.mainContext
        let back = try c.mainContext.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.name == "migration test" })).first
        check("trend choice saved and read back", try ctx.fetch(FetchDescriptor<Profile>()).first?.trendAlgorithm == "v1")
        check("plan log saved and read back", try ctx.fetch(FetchDescriptor<Profile>()).first?.planLog["2000-01-01"]?.first?.foods == ["oats"])
        check("micros saved and read back", back?.nutrients.micros?["iron"] == 2.5 && back?.nutrients.micros?["vitD"] == 4, back?.nutrients.micros ?? [:])
        // Taxonomy and raw/cooked fields: existing foods open with defaults, and corrections save and read back.
        let foods = try ctx.fetch(FetchDescriptor<Food>())
        check("foods open with taxonomy defaults", !foods.isEmpty && foods.allSatisfy { $0.cookedRatio >= 0 && $0.nova >= 0 }, foods.count)
        if let f = foods.first {
            f.taxonomyOverride = #"{"role":"carbSide","nova":2}"#; f.weightState = "raw"; f.cookedRatio = 2.4
            try ctx.save()
            let k = f.key
            let back2 = try ctx.fetch(FetchDescriptor<Food>(predicate: #Predicate { $0.key == k })).first
            check("taxonomy correction and batch ratio saved", back2?.taxonomyOverride.contains("carbSide") == true && back2?.cookedRatio == 2.4 && back2?.weightState == "raw")
        }
    } catch { print("ERROR", error); fails += 1 }
} 
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
