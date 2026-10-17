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
check(small.kcal == 2500, "within ±50 kcal nothing changes (deadband)")
check(small.protein == 180, "protein holds when it barely changed")
let big = smoothed(current: cur, raw: Targets(kcal: 2000, protein: 180, fat: 65, carbs: 180), minFat: 40)
check(big.kcal == 2350, "a big drop moves at most 150 kcal (\(big.kcal))")
check(big.protein == 180 && big.carbs < cur.carbs && big.fat <= cur.fat + 2, "carbs (and fat) take the change, protein holds")
check(abs(kcalFromMacros(big) - big.kcal) < 15, "smoothed macros add up")
let mid = smoothed(current: cur, raw: Targets(kcal: 2700, protein: 180, fat: 88, carbs: 300), minFat: 40)
check(mid.kcal == 2640, "70% of a 200 kcal rise when sure (\(mid.kcal))")
let unsure = smoothed(current: cur, raw: Targets(kcal: 2700, protein: 180, fat: 88, carbs: 300), minFat: 40, goal: .lose, confidence: 0)
check(unsure.kcal == 2570, "35% when the estimate is unsure (\(unsure.kcal))")
let bulkCut = smoothed(current: cur, raw: Targets(kcal: 2200, protein: 180, fat: 70, carbs: 220), minFat: 40, goal: .gain, confidence: 1)
check(bulkCut.kcal == 2430, "on a bulk, at most 75 kcal down (\(bulkCut.kcal))")
check(proteinGrams(.extraHigh, weightKg: 70, body: BodyInfo(leanKg: 66, heightCm: 175)) <= 2.6 * 70 + 0.01, "protein clamped to 2,6 g/kg body weight")

// A refeed's water: a 1 kg jump flagged as a water event barely moves expenditure
let span = (0..<60).map { addDays("2026-01-01", $0) }
var flat = Dictionary(uniqueKeysWithValues: span.map { ($0, 2500.0) })
var w = span.map { DayValue(day: $0, value: 80.0) }
for i in 42...44 { w[i].value = 81.0 }                      // water after a big carb day
flat["2026-02-11"] = 3200
let plain = jointExpenditure(start: span[0], end: span.last!, initial: 2500, intake: flat, weights: w)
var ws = JointSettings(); ws.waterEvents = ["2026-02-12"]
let tagged = jointExpenditure(start: span[0], end: span.last!, initial: 2500, intake: flat, weights: w, settings: ws)
let drop = { (r: [ExpenditurePoint]) in r[41].kcal - r[46].kcal }
check(drop(tagged) < drop(plain) * 0.7, "a tagged water event moves expenditure less (\(Int(drop(plain))) → \(Int(drop(tagged))) kcal)")

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

// Scales: a second scale reading 0,8 kg heavy is worked out and evened out
let c2 = ModelContext(try! ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
let pr = Profile(sex: .male, birthDate: Date(timeIntervalSince1970: 0), heightCm: 180, activity: .moderate, weightUnit: .kg, energyUnit: .kcal)
c2.insert(pr)
for i in 0..<30 {
    let d = addDays(dayKey(), -29 + i)
    let w = WeightEntry(day: d, kg: 90 - Double(i) * 0.05)
    if i % 5 == 2 { w.kg += 0.8; w.scale = "Madrid" }
    c2.insert(w)
}
c2.commit()
let madrid = c2.estimatedScaleOffsets()["Madrid"] ?? 0
check(abs(madrid + 0.8) < 0.15, "Madrid scale offset worked out (\(String(format: "%.2f", madrid)))")
pr.scaleOffsetMap = ["Madrid": madrid]
let vals = c2.weightValues
check(vals.allSatisfy { abs($0.value - (90 - Double(daysBetween(addDays(dayKey(), -29), $0.day)) * 0.05)) < 0.2 }, "readings corrected to the main scale")
check(pr.scaleOffsetMap["Madrid"].map { abs($0 - madrid) < 0.01 } == true, "offsets saved on the profile")

// Phases: a cut that reached its weight hands over to the next phase
c2.startProgram(goal: .lose, ratePercent: 0.5, diet: .balanced, protein: .high, weightKg: 89, expenditure: 2800, sex: .male, reason: "goal")
pr.phaseEnd = "kg:89.5"
pr.phases = [PhaseStep(goal: GoalType.maintain.rawValue, ratePercent: 0, weeks: 4), PhaseStep(goal: GoalType.gain.rawValue, ratePercent: 0.25, untilKg: 95)]
check(c2.phaseDone, "cut done at the target weight")
c2.startNextPhase()
check(c2.activeProgram?.goalValue == .maintain && pr.phaseEnd == "day:\(addDays(dayKey(), 28))", "maintenance for 4 weeks starts (\(pr.phaseEnd))")
check(pr.phases.count == 1 && pr.phases[0].goalValue == .gain, "the bulk waits next")
check(!c2.phaseDone, "maintenance not done yet")

// Shadow log
pr.shadowEntries += [ShadowEntry(day: dayKey(), currentKcal: 2500, proposedKcal: 2400, rawKcal: 2300, expenditure: 2700, weekChangeKg: -0.4)]
check(pr.shadowEntries.count == 1 && pr.shadowEntries[0].proposedKcal == 2400, "shadow check-ins are logged")

// Per-day plan (collaborative): used for its weekday, rescaled at a check-in
let c3 = ModelContext(try! ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
let p3 = Profile(sex: .male, birthDate: Date(timeIntervalSince1970: 0), heightCm: 180, activity: .moderate, weightUnit: .kg, energyUnit: .kcal)
c3.insert(p3)
c3.startProgram(goal: .lose, ratePercent: 0.5, diet: .balanced, protein: .high, weightKg: 90, expenditure: 2800, sex: .male, reason: "goal")
c3.activeProgram?.mode = "collaborative"
let monday = addDays(weekStart(dayKey()), 7)
p3.weekPlan = [2: Targets(kcal: 2600, protein: 190, fat: 70, carbs: 302)]
c3.commit()
check(c3.dayTargets(on: monday)?.kcal == 2600, "Monday uses your own plan")
check(c3.dayTargets(on: addDays(monday, 1))?.kcal != 2600, "other days use the program")
let base3 = c3.targets()!.targets.kcal
c3.finishCheckIn(apply: Targets(kcal: base3 * 1.1, protein: 190, fat: 70, carbs: 300), expenditure: 2900)
let mon = p3.weekPlan[2]!
check(abs(mon.kcal - roundTo(2600 * 1.1, 10)) < 1 && mon.protein == 190, "check-in rescales the plan, protein kept (\(mon.kcal))")

do {
// Training days in the calorie distribution follow the training week (set, or inferred from workouts).
let pt = Profile(sex: .male, birthDate: Date(timeIntervalSince1970: 0), heightCm: 180, activity: .moderate, weightUnit: .kg, energyUnit: .kcal)
pt.highDays = "1,2,3,4,5,6,7"; pt.highDayExtra = 250              // every day marked: no difference (the user's setting)
let baseT = Targets(kcal: 2200, protein: 190, fat: 60, carbs: 230)
let kcalOn: (Int) -> Double = { wd in pt.adjust(baseT, on: (0..<7).map { addDays("2026-10-18", $0) }.first { Calendar(identifier: .gregorian).component(.weekday, from: date(fromKey: $0)) == wd }!).kcal }
check(Set((1...7).map(kcalOn)).count == 1, "all 7 days marked: every day the same")
var ps = pt.planner; ps.inferredWeek = [2: TrainingSlot(start: 1080, minutes: 75), 4: TrainingSlot(start: 1080, minutes: 75), 6: TrainingSlot(start: 1080, minutes: 75)]; pt.planner = ps
check(pt.highDaySet == [2, 4, 6], "training days follow the inferred week (\(pt.highDaySet))")
check(kcalOn(2) == kcalOn(4) && kcalOn(4) == kcalOn(6) && kcalOn(2) - kcalOn(3) == 250, "every training day gets the training-day target (\(kcalOn(2)) vs \(kcalOn(3)))")
check(abs((1...7).map(kcalOn).reduce(0, +) - 7 * 2200) < 0.01, "week total unchanged")
ps.schedule = [7: TrainingSlot(start: 660, minutes: 90)]; ps.scheduleSet = true; pt.planner = ps
check(pt.highDaySet == [7], "your own week wins over the inferred one")
ps.highDaysFollowTraining = false; pt.planner = ps
check(pt.highDaySet == Set(1...7), "turned off: your picked days")

// Raw or cooked: log either weight.
let pasta = Food(key: "p", name: "Pipe Rigate", source: "off", per100: Nutrients(kcal: 347, protein: 12, fat: 1.5, carbs: 70))
check(pasta.state == .raw && pasta.units.contains(Cooking.cookedUnit), "dry pasta: values raw, can log cooked")
check(abs(pasta.grams(200, unit: Cooking.cookedUnit) - 200 / 2.35) < 0.01, "200 g cooked pasta = 85 g dry (typical ratio)")
pasta.cookedRatio = 2.5
check(abs(pasta.grams(250, unit: Cooking.cookedUnit) - 100) < 0.01, "your batch ratio wins (250 g cooked = 100 g dry)")
let chicken = Food(key: "c", name: "Premium Roasted Chicken", source: "custom", per100: Nutrients(kcal: 115, protein: 24, fat: 2, carbs: 0))
check(chicken.state == .cooked && !chicken.units.contains(Cooking.rawUnit), "sold cooked (roast chicken): the typical ratio is never applied")
chicken.cookedRatio = 0.7
check(chicken.units.contains(Cooking.rawUnit) && abs(chicken.grams(100, unit: Cooking.rawUnit) - 70) < 0.01, "…only a batch you weighed converts it")
let potato = Food(key: "pt", name: "Potatoes, flesh and skin, raw", source: "usda", per100: Nutrients(kcal: 77, protein: 2, fat: 0.1, carbs: 17))
check(abs(potato.grams(925, unit: Cooking.cookedUnit) - 925 / 0.83) < 0.01, "925 g baked potato = 1 114 g raw")
let recipe = Food(key: "recipe:x", name: "Pasta bake", source: "recipe", per100: Nutrients(kcal: 200, protein: 10, fat: 5, carbs: 30))
check(recipe.state == .raw && recipe.otherWeightUnit == nil, "recipe: no cooked unit until you weigh a batch")
recipe.cookedRatio = Cooking.ratio(raw: 1200, cooked: 1800)!
check(abs(recipe.grams(300, unit: Cooking.cookedUnit) - 200) < 0.01, "batch 1 200 g raw → 1 800 g cooked: 300 g cooked = 200 g of ingredients")
let milk = Food(key: "m", name: "Leche", source: "off", per100: Nutrients(kcal: 46, protein: 3, fat: 1.5, carbs: 5), isLiquid: true)
check(milk.otherWeightUnit == nil, "liquids: no raw/cooked")

}

print(failed == 0 ? "ALL PASSED" : "\(failed) FAILED")
exit(failed == 0 ? 0 : 1)
