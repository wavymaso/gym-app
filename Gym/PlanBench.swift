import Foundation
import SwiftData

// Planner timing on the device: launch with `-planBench` (tools/plan-bench.sh) and the app prints how
// long each stage of today's plan and the week takes, then quits. Nothing is saved.

extension ModelContext {
    @MainActor func planBench() async {
        func ms(_ f: () -> Void) -> Double { let t = Date(); f(); return Date().timeIntervalSince(t) * 1000 }
        func out(_ s: String) { FileHandle.standardOutput.write((s + "\n").data(using: .utf8)!) }
        let today = dayKey(), tomorrow = addDays(today, 1)
        out("PLANBENCH start \(today)")
        out(String(format: "PLANBENCH planFoods (first) %.0f ms, cached %.1f ms", ms { _ = planFoods() }, ms { _ = planFoods() }))
        out(String(format: "PLANBENCH mealPatterns+usualMeals %.1f ms", ms { _ = mealPatterns(); _ = usualMeals() }))
        forgetPlan(today); forgetPlan(tomorrow)
        out(String(format: "PLANBENCH today cold %.0f ms", ms { _ = dayPlan(today) }))
        out(String(format: "PLANBENCH tomorrow (full day) cold %.0f ms", ms { _ = dayPlan(tomorrow) }))
        out(String(format: "PLANBENCH tomorrow warm, nothing changed %.0f ms", ms { _ = dayPlan(tomorrow) }))
        // A log: the first open meal eaten as planned but 20% bigger; the rest of the day resizes from the last plan.
        if let base = dayPlan(tomorrow), var job = planJob(tomorrow), let i = job.slots.firstIndex(where: { !$0.fixed }) {
            let planned = base.plan.slots.first { $0.index == job.slots[i].index }?.items ?? []
            job.slots[i].items = planned.map { PlanItem(key: $0.key, grams: $0.grams * 1.2) }; job.slots[i].eaten = true
            for s in base.plan.slots where !s.fixed && s.index != job.slots[i].index { if let st = base.plan.structure[s.index] { job.previous[s.index] = (s.items, st) } }
            var r: PlanResult?
            out(String(format: "PLANBENCH re-solve after a log (rest of the day) %.0f ms", ms { r = job.run() }))
            out("PLANBENCH   → misses \(r?.plan.misses ?? [])")
            // A swap: one meal changed (its protein replaced), only that meal resized first.
            var job2 = planJob(tomorrow)!
            for s in base.plan.slots where !s.fixed { if let st = base.plan.structure[s.index] { job2.previous[s.index] = (s.items, st) } }
            if let lunch = base.plan.slots.first(where: { !$0.fixed && $0.items.count > 2 }) {
                var items = lunch.items; items[0].grams += 30
                job2.previous[lunch.index]?.items = items
                job2.only = [lunch.index]
                out(String(format: "PLANBENCH re-solve after a swap (one meal) %.0f ms", ms { r = job2.run() }))
                out("PLANBENCH   → \(r?.plan.reasons.contains { $0.rule == "re-planned" } == true ? "only that meal" : "whole day") misses \(r?.plan.misses ?? [])")
            }
        }
        var days: [String] = []
        let t0 = Date()
        var uses: [String: Int] = [:]
        for i in 0..<7 {
            let d = addDays(today, i)
            let t = ms {
                guard let job = planJob(d, uses: uses) else { return }
                let r = job.run()
                for s in r.plan.slots where !s.eaten { for it in s.items { uses[it.key, default: 0] += 1 } }
            }
            days.append(String(format: "%@ %.0f", String(d.suffix(5)), t))
        }
        out("PLANBENCH week days " + days.joined(separator: ", "))
        out(String(format: "PLANBENCH week total %.0f ms", Date().timeIntervalSince(t0) * 1000))
        let t1 = Date()
        _ = await weekPlans(from: addDays(today, 7))
        out(String(format: "PLANBENCH week in the background (wall time, main thread free) %.0f ms", Date().timeIntervalSince(t1) * 1000))
        out("PLANBENCH done")
        exit(0)
    }
}
