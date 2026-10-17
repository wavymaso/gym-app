// Prints a 7-day sample plan from a store (a copy of your real data). Arguments: store path, then
// optionally a sample training week like "2=18:00,4=18:00,6=18:00,7=11:00" (weekday: 1 = Sunday)
// used only when no week is set or inferred.
import Foundation
import SwiftData
setvbuf(stdout, nil, _IONBF, 0)
MainActor.assumeIsolated {
    let c = try! ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(url: URL(fileURLWithPath: CommandLine.arguments[1])))
    let ctx = c.mainContext
    guard let p = ctx.profile else { print("no profile"); exit(1) }
    UserDefaults.standard.removeObject(forKey: "fibreSwitch1"); ctx.applyFibreSwitch()
    let styleArg = CommandLine.arguments.first { $0.hasPrefix("--style=") }.map { String($0.dropFirst(8)) }
    var s = p.planner
    let inferred = ctx.inferredSchedule()
    var weekNote = s.scheduleSet ? "your own week" : inferred.isEmpty ? "none inferred" : "inferred from your workouts"
    if !s.scheduleSet, inferred.isEmpty, CommandLine.arguments.count > 2 {
        for part in CommandLine.arguments[2].split(separator: ",") {
            let kv = part.split(separator: "="), hm = kv[1].split(separator: ":")
            s.schedule[Int(kv[0])!] = TrainingSlot(start: Int(hm[0])! * 60 + Int(hm[1])!, minutes: 75)
        }
        s.scheduleSet = true; p.planner = s
        weekNote = "EXAMPLE week (you have no logged workouts yet), 75 min sessions"
    }
    let source: String = switch ctx.planSource { case .history: "your eating history"; case .staples: "your staples"; case .recent: "your recent foods (no staples picked, little food-by-food history)" }
    print("SAMPLE 7-DAY PLAN · style: \(styleArg ?? p.planner.style) · foods from \(source) · training: \(weekNote)")
    print("Settings: \(s.meals) meals, wake \(s.wake / 60):\(String(format: "%02d", s.wake % 60)), bed \(s.sleep / 60):\(String(format: "%02d", s.sleep % 60)), pre-workout snack, pre-sleep protein off\n")
    // The role audit: every food the planner can use, what it was taken for, and its limits.
    print("FOOD ROLES (correct any in Food log → Plan → Change → Planner settings → Food roles)")
    let corrected = p.planner.roles
    for role in FoodRole.allCases {
        let list = ctx.planFoods().filter { $0.role == role && !$0.basic }.sorted { $0.name < $1.name }
        guard !list.isEmpty else { continue }
        print("  \(role.label.uppercased())")
        for f in list {
            let meals = f.bands.isEmpty ? "any meal" : f.bands.sorted().map(\.label).joined(separator: "/")
            print(String(format: "    %-46@ %3.0f–%3.0f g a meal, up to %d× a day, %@ · %3.0f kcal %4.1f g protein per 100 g%@", f.name as NSString,
                         f.minGrams, f.maxGrams, f.maxPerDay, meals as NSString, f.per100.kcal, f.per100.protein, (corrected[f.key] != nil ? " (your choice)" : "") as NSString))
        }
    }
    print("")
    if p.refeedWeekday > 0, p.refeedExtraKcal > 0 {
        print("Note: you have a weekly refeed on \(["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][p.refeedWeekday]) (+\(Int(p.refeedExtraKcal)) kcal, taken back evenly from the other 6 days).")
    }
    print("Training days get +\(Int(p.highDayExtra)) kcal (your distribution), following \(p.planner.trainingWeekdays == nil ? "your picked days" : "the training week").\n")
    let start = addDays(dayKey(), 1)
    var uses: [String: Int] = [:]
    for i in 0..<7 {
        let d = addDays(start, i)
        guard let r = ctx.dayPlan(d, uses: uses, style: styleArg), let t = ctx.dayTargets(on: d) else { print("\(d): no targets"); continue }
        for sl in r.plan.slots { for it in sl.items { uses[it.key, default: 0] += 1 } }
        let tr = r.settings.training(on: d, inferred: inferred)
        let wd = date(fromKey: d).formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Locale(identifier: "en_GB")))
        print("── \(wd) · \(tr.map { String(format: "training %02d:%02d", $0.start / 60, $0.start % 60) } ?? "rest day")")
        for sl in r.plan.slots {
            let m = sl.items.reduce(Macros()) { $0 + (r.foods[$1.key]?.macros($1.grams) ?? Macros()) }
            let kind = ["meal": "", "preWorkout": " (before training)", "postWorkout": " (after training)", "preSleep": " (before bed)"][sl.kind.rawValue] ?? ""
            let short = r.plan.shortMeals.contains { $0.index == r.plan.slots.firstIndex(of: sl) } ? "  ⚠ below the \(Int(PlanTargets(kcal: 0, protein: 0, fat: 0, carbs: 0, weightKg: trendSeries(ctx.weightValues, through: d).last?.trend ?? 80).minProtein(sl.kind))) g minimum" : ""
            let target = r.plan.slots.firstIndex(of: sl).flatMap { _ in r.plan.slots.isEmpty ? nil : nil } ?? 0
            _ = target
            print(String(format: "  %02d:%02d %@%@ · %d kcal, %d g protein, %d g carbs%@", sl.minute / 60 % 24, sl.minute % 60, sl.band.label, kind, Int(m.kcal), Int(m.protein), Int(m.carbs), short as NSString))
            if let st = r.plan.structure[sl.index] {
                print("     template: \(st.template)\(st.dropped.isEmpty ? "" : " (dropped to fit: \(st.dropped.joined(separator: ", ")))")\(st.unfilled.isEmpty ? "" : " ⚠ NOT FILLED: \(st.unfilled.joined(separator: "; "))")")
                for f in st.fill where !f.keys.isEmpty {
                    for k in f.keys {
                        guard let it = sl.items.first(where: { $0.key == k }), let pf = r.foods[k] else { continue }
                        let mm = pf.macros(it.grams)
                        print("     · \(f.kind.label): \(pf.name), \(pf.shown(it.grams))  (\(Int(mm.kcal)) kcal, \(Int(mm.protein)) P, \(Int(mm.carbs)) C, \(Int(mm.fat)) F)")
                    }
                }
                for it in sl.items where !st.fill.contains(where: { $0.keys.contains(it.key) }) { print("     · \(r.foods[it.key]?.name ?? it.key), \(Int(it.grams)) g") }
            } else {
                for it in sl.items { print("     \(sl.locked ? "🔒 " : "")\(r.foods[it.key]?.name ?? it.key), \(r.foods[it.key]?.shown(it.grams) ?? "\(Int(it.grams)) g")") }
            }
        }
        let tot = r.plan.totals
        let kg = trendSeries(ctx.weightValues, through: d).last?.trend ?? 80
        let fatFloor = min(t.fat, max(40, Evidence.value("fat.min.gPerKg") * kg))
        let fibreFloor = p.planner.fibreFloor(kcal: t.kcal, custom: p.customGoals["fiber"])
        let dk = tot.kcal - t.kcal
        print(String(format: "  Day: %d kcal (target %d, %@%d, %+.1f%%) · protein %d (min %d) · fat %d (target %d, floor %d) · carbs %d (target %d) · fibre %d (floor %d)",
                     Int(tot.kcal.rounded()), Int(t.kcal.rounded()), (dk >= 0 ? "+" : "") as NSString, Int(dk.rounded()), dk / t.kcal * 100, Int(tot.protein.rounded()), Int(t.protein.rounded()), Int(tot.fat.rounded()), Int(t.fat.rounded()), Int(fatFloor.rounded()),
                     Int(tot.carbs.rounded()), Int(t.carbs.rounded()), Int(tot.fibre.rounded()), Int(fibreFloor.rounded())))
        if let c = r.plan.carbs {
            print(String(format: "  Carbs: %d g = %.1f g/kg (%@ %d–%d g/kg)%@%@", Int(tot.carbs.rounded()), c.gPerKg, (c.rangeIsTarget ? "target" : "cut reference") as NSString, Int(c.range.lowerBound), Int(c.range.upperBound),
                         (c.recovery ? " · RECOVERY WINDOW (next session < 24 h)" : "") as NSString, (c.intra > 0 ? " · \(Int(c.intra)) g during training" : "") as NSString))
        }
        for reason in r.plan.reasons where ["training day", "rest day", "before training", "recovery window", "back-to-back sessions", "fasted training", "carbs during training"].contains(reason.rule) {
            print("    why (\(reason.rule)): \(reason.detail)")
        }
        if !r.plan.relaxed.isEmpty { print("  Preferences relaxed: \(r.plan.relaxed.joined(separator: ", "))") }
        if !r.plan.relaxedHard.isEmpty { print("  HARD LIMIT WIDENED: \(r.plan.relaxedHard.joined(separator: " → "))") }
        if !r.plan.misses.isEmpty { print("  ⚠ HARD CONSTRAINTS NOT MET: \(r.plan.misses.joined(separator: ", "))") }
        for reason in r.plan.reasons where ["meal realism", "slot not filled"].contains(reason.rule) { print("    · \(reason.detail)") }
        for m in r.plan.shortMeals { print("    · \(Planner.mealName(r.plan.slots[m.index])): \(Int(m.protein)) g protein of the \(Int(m.needed)) g minimum (no protein food for that meal)") }
        print("")
    }
}
