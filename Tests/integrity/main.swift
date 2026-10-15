import Foundation
import SwiftData
var fails = 0
func check(_ n: String, _ ok: Bool) { if !ok { fails += 1; print("FAIL", n) } }
UserDefaults.standard.removeObject(forKey: "recentProblems")
let c = try! ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
let ctx = ModelContext(c)

// Clean data stays untouched.
ctx.insert(WeightEntry(day: "2026-10-01", kg: 110)); ctx.commit()
check("clean is clean", ctx.integrityCheck().isClean)

// The same food entry twice (same sync ID): the newer survives, and no deletion goes to sync.
let a = FoodEntry(day: "2026-10-02", time: Date(), name: "Oats", brand: nil, foodKey: nil, amount: 80, unit: "g", grams: 80, nutrients: Nutrients(kcal: 300, protein: 10, fat: 5, carbs: 50))
let b = FoodEntry(day: "2026-10-02", time: Date(), name: "Oats (edited)", brand: nil, foodKey: nil, amount: 90, unit: "g", grams: 90, nutrients: Nutrients(kcal: 340, protein: 11, fat: 6, carbs: 56))
ctx.insert(a); ctx.insert(b); ctx.commit()
b.syncID = a.syncID; a.modifiedAt = Date(timeIntervalSince1970: 1000); b.modifiedAt = Date(timeIntervalSince1970: 2000); try! ctx.save()
let tombsBefore = (try? ctx.fetchCount(FetchDescriptor<Tombstone>())) ?? 0
var r = ctx.integrityCheck()
check("one duplicate removed (\(r.duplicatesRemoved))", r.duplicatesRemoved == 1)
let left = (try? ctx.fetch(FetchDescriptor<FoodEntry>())) ?? []
check("the newer edit kept", left.count == 1 && left.first?.name == "Oats (edited)")
check("no tombstone sent", ((try? ctx.fetchCount(FetchDescriptor<Tombstone>())) ?? 0) == tombsBefore)

// An ingredient whose recipe is gone goes; a set without its workout is only reported.
ctx.insert(RecipeIngredient(recipeKey: "recipe:gone", foodKey: nil, name: "Rice", grams: 100, per100: Nutrients(kcal: 130, protein: 3, fat: 0, carbs: 28), order: 0))
ctx.insert(WorkoutSet(workoutKey: "w:missing", exerciseKey: "bench", exerciseOrder: 0, setOrder: 0, day: "2026-10-02"))
ctx.commit()
r = ctx.integrityCheck()
check("orphan ingredient removed", r.orphansRemoved == 1 && ((try? ctx.fetchCount(FetchDescriptor<RecipeIngredient>())) ?? 1) == 0)
check("loose set reported, kept", r.problems.contains { $0.contains("without a workout") } && ((try? ctx.fetchCount(FetchDescriptor<WorkoutSet>())) ?? 0) == 1)
check("problem logged", Log.problems.contains { $0.message.contains("without a workout") })

// Impossible numbers are reported.
ctx.insert(WeightEntry(day: "2026-10-03", kg: 1100)); ctx.commit()
check("bad weigh-in reported", ctx.integrityCheck().problems.contains { $0.contains("outside") })

// Backup rotation: 14 daily, then one per week for 13 weeks.
var names: [String] = []
var d = "2026-10-15"
for _ in 0..<200 { names.append("Gym backup \(d).json"); d = addDays(d, -1) }
let kept = Backup.keep(names, daily: 14, weeks: 13)
check("newest 14 kept", names.prefix(14).allSatisfy(kept.contains))
check("weekly extras cover the rest of 13 weeks (\(kept.count - 14))", (10...12).contains(kept.count - 14))
check("nothing older than 13 weeks", kept.allSatisfy { Backup.day(of: $0)! >= addDays("2026-10-15", -91) })
check("one per week", Set(kept.compactMap { Backup.day(of: $0) }.filter { $0 < addDays("2026-10-15", -13) }.map(weekStart)).count == kept.count - 14)
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED")
