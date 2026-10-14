import Foundation
import SwiftData

// The coaching rules: protein by lean mass and training, guardrails, check-in smoothing,
// collaborative rescaling, and fixing a half-logged day with an estimate.
var failed = 0
func check(_ ok: Bool, _ what: String) { if !ok { failed += 1; print("FAIL \(what)") } }

// Protein
let heavy = BodyInfo(leanKg: nil, heightCm: 180, training: .resistance)
let p110 = proteinGrams(.high, weightKg: 110, body: heavy)
check(abs(p110 - 2.4 * 27 * 1.8 * 1.8) < 0.5, "a heavy lifter's protein is capped at a BMI-27 weight (\(p110))")
check(proteinGrams(.high, weightKg: 70, body: heavy) == 2.4 * 70, "a lean person uses their weight")
let lean = BodyInfo(leanKg: 65, heightCm: 180, training: .resistance)
check(abs(proteinGrams(.high, weightKg: 85, body: lean) - 2.8 * 65) < 0.01, "lean mass used when known")
let cardio = BodyInfo(leanKg: 65, heightCm: 180, training: .aerobic)
check(proteinGrams(.high, weightKg: 85, body: cardio) < proteinGrams(.high, weightKg: 85, body: lean), "less protein for cardio")
check(proteinGrams(.high, weightKg: 85, body: nil) == 2.4 * 85, "old rule without body info")

// Guardrails
let keto = makeTargets(expenditure: 2000, weightKg: 100, sex: .male, goal: .lose, ratePercent: 1.0, diet: .lowFat, protein: .extraHigh,
                       body: BodyInfo(leanKg: 75, heightCm: 185, training: .resistance, floorKcal: nil, guardrails: true))
check(keto.fat >= 50, "coached keeps fat at 0,5 g/kg or more (\(keto.fat))")
check(keto.kcal >= 1500, "coached calorie floor (\(keto.kcal))")
let mine = makeTargets(expenditure: 1500, weightKg: 70, sex: .male, goal: .lose, ratePercent: 1.0, diet: .balanced, protein: .high,
                       body: BodyInfo(leanKg: nil, heightCm: 175, training: .resistance, floorKcal: 1800, guardrails: true))
check(mine.kcal == 1800, "your own floor (\(mine.kcal))")
let free = makeTargets(expenditure: 1500, weightKg: 70, sex: .male, goal: .lose, ratePercent: 1.0, diet: .balanced, protein: .high,
                       body: BodyInfo(leanKg: nil, heightCm: 175, training: .resistance, floorKcal: 1800, guardrails: false))
check(free.kcal < 1500, "no floor without guardrails (\(free.kcal))")
let kcalFromMacros = { (t: Targets) in t.protein * 4 + t.fat * 9 + t.carbs * 4 }
check(abs(kcalFromMacros(keto) - keto.kcal) < 15, "macros add up to the calories")

// Smoothing
let cur = Targets(kcal: 2500, protein: 180, fat: 80, carbs: 263)
let small = smoothed(current: cur, raw: Targets(kcal: 2540, protein: 182, fat: 82, carbs: 270), minFat: 40)
check(small.kcal == 2540, "small changes go straight through")
check(small.protein == 180, "protein holds when it barely changed")
let big = smoothed(current: cur, raw: Targets(kcal: 2000, protein: 180, fat: 65, carbs: 180), minFat: 40)
check(big.kcal == 2300, "a big drop moves at most 200 kcal (\(big.kcal))")
check(big.protein == 180 && big.carbs < cur.carbs && big.fat < cur.fat, "carbs and fat take the change")
check(abs(kcalFromMacros(big) - big.kcal) < 15, "smoothed macros add up")
let mid = smoothed(current: cur, raw: Targets(kcal: 2700, protein: 180, fat: 88, carbs: 300), minFat: 40)
check(mid.kcal == 2620, "60% of a 200 kcal rise (\(mid.kcal))")

// Collaborative
let collab = rescaled(Targets(kcal: 2400, protein: 200, fat: 60, carbs: 265), toKcal: 2600)
check(collab.protein == 200, "your protein kept")
check(abs(collab.fat * 9 / (collab.fat * 9 + collab.carbs * 4) - 540.0 / (540 + 1060)) < 0.01, "your carb/fat split kept")
check(abs(kcalFromMacros(collab) - 2600) < 10, "new calories")

// A half-logged day, estimated
let c = try! ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
let ctx = ModelContext(c)
let d = "2026-10-12"
ctx.insert(FoodEntry(day: d, time: Date(), name: "Breakfast", brand: nil, foodKey: nil, amount: 1, unit: "", grams: 0,
                     nutrients: Nutrients(kcal: 800, protein: 50, fat: 30, carbs: 82)))
let n = DayNote(day: d, partial: true); ctx.insert(n); ctx.commit()
check(ctx.partialDays.contains(d), "marked partial")
let added = ctx.estimateDay(d, totalKcal: 2600)
check(added == 1800, "the difference is added (\(added))")
check(abs(ctx.entries(on: d).reduce(0) { $0 + $1.nutrients.kcal } - 2600) < 0.5, "the day now totals the estimate")
check(!ctx.partialDays.contains(d), "and counts again")
let est = ctx.entries(on: d).first { $0.name.hasPrefix("Unlogged") }!.nutrients
check(abs(est.protein / est.kcal - 50.0 / 800) < 0.01, "estimate in the day's own macro proportions")

// Refeeds and diet breaks
let prof = Profile(sex: .male, birthDate: Date(timeIntervalSince1970: 0), heightCm: 180, activity: .moderate, weightUnit: .kg, energyUnit: .kcal)
prof.refeedWeekday = 7; prof.refeedExtraKcal = 600            // Saturday
let base = Targets(kcal: 2200, protein: 190, fat: 65, carbs: 200)
let week = (0..<7).map { addDays("2026-10-12", $0) }          // Monday to Sunday
let adjusted = week.map { prof.refeed(base, on: $0) }
check(abs(adjusted.reduce(0) { $0 + $1.kcal } - 7 * 2200) < 1, "refeed keeps the week's calories")
check(adjusted[5].carbs == 350 && adjusted[5].protein == 190, "Saturday: +150 g carbs, same protein")
check(abs(adjusted[0].kcal - 2100) < 0.5, "other days give back 100 kcal each")
prof.dietBreakStart = "2026-10-20"; prof.dietBreakEnd = "2026-11-02"
check(prof.inDietBreak("2026-10-25") && !prof.inDietBreak("2026-11-03") && !prof.inDietBreak("2026-10-19"), "diet break dates")
let m = maintenance(base, expenditure: 2750)
check(m.kcal == 2750 && m.protein == 190, "diet break: maintenance calories, same protein (\(m.kcal))")
check(abs(m.fat * 9 / (m.fat * 9 + m.carbs * 4) - 585.0 / (585 + 800)) < 0.01, "and the same carb/fat split")
check(weekStart("2026-10-18") == "2026-10-12" && weekStart("2026-10-12") == "2026-10-12", "weeks start on Monday")

print(failed == 0 ? "ALL PASSED" : "\(failed) FAILED")
exit(failed == 0 ? 0 : 1)
