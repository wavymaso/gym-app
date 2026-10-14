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
        ctx.insert(e); try ctx.save()
        let p = try ctx.fetch(FetchDescriptor<Profile>()).first
        check("profile has new fields", p?.fastKcal == 600 && p?.highDays == "", (p?.fastKcal ?? -1, p?.highDays ?? "?"))
    } catch { print("ERROR", error); fails += 1 }
    do {
        let c = try ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(url: url))
        let back = try c.mainContext.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.name == "migration test" })).first
        check("micros saved and read back", back?.nutrients.micros?["iron"] == 2.5 && back?.nutrients.micros?["vitD"] == 4, back?.nutrients.micros ?? [:])
    } catch { print("ERROR", error); fails += 1 }
} 
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
