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
    print("SAMPLE 7-DAY PLAN · foods from \(source) · training: \(weekNote)")
    print("Settings: \(s.meals) meals, wake \(s.wake / 60):\(String(format: "%02d", s.wake % 60)), bed \(s.sleep / 60):\(String(format: "%02d", s.sleep % 60)), pre-workout snack, pre-sleep protein off\n")
    if CommandLine.arguments.contains("--foods") {
        for f in ctx.planFoods() { print(String(format: "  %-45@ %-9@ %@  usual %4.0f [%3.0f–%3.0f] step %3.0f  %4.0f kcal %4.1f P /100g  freq %.0f", f.name as NSString, f.role.rawValue as NSString,
                                              f.bands.sorted().map(\.rawValue).joined(separator: ",") as NSString, f.usualGrams, f.minGrams, f.maxGrams, f.step, f.per100.kcal, f.per100.protein, f.frequency)) }
    }
    let start = addDays(dayKey(), 1)
    var uses: [String: Int] = [:]
    for i in 0..<7 {
        let d = addDays(start, i)
        guard let r = ctx.dayPlan(d, uses: uses), let t = ctx.dayTargets(on: d) else { print("\(d): no targets"); continue }
        for sl in r.plan.slots { for it in sl.items { uses[it.key, default: 0] += 1 } }
        let tr = r.settings.training(on: d, inferred: inferred)
        let wd = date(fromKey: d).formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Locale(identifier: "en_GB")))
        print("── \(wd) · \(tr.map { String(format: "training %02d:%02d", $0.start / 60, $0.start % 60) } ?? "rest day")")
        for sl in r.plan.slots {
            let m = sl.items.reduce(Macros()) { $0 + (r.foods[$1.key]?.macros($1.grams) ?? Macros()) }
            let kind = ["meal": "", "preWorkout": " (before training)", "postWorkout": " (after training)", "preSleep": " (before bed)"][sl.kind.rawValue] ?? ""
            print(String(format: "  %02d:%02d %@%@ · %d kcal, %d g protein", sl.minute / 60 % 24, sl.minute % 60, sl.band.label, kind, Int(m.kcal), Int(m.protein)))
            for it in sl.items { print("     \(r.foods[it.key]?.name ?? it.key), \(Int(it.grams)) g") }
        }
        let tot = r.plan.totals
        print(String(format: "  Day: %d kcal (target %d) · P %d (%d) · F %d (%d) · C %d (%d) · fibre %d g", Int(tot.kcal), Int(t.kcal), Int(tot.protein), Int(t.protein),
                     Int(tot.fat), Int(t.fat), Int(tot.carbs), Int(t.carbs), Int(tot.fibre)))
        if !r.plan.relaxed.isEmpty { print("  Relaxed: \(r.plan.relaxed.joined(separator: ", "))") }
        if !r.plan.feasible { print("  ⚠ Doesn't fully fit: \(r.plan.reasons.first { $0.rule == "can't fully fit" }?.detail ?? "")") }
        print("")
    }
}
