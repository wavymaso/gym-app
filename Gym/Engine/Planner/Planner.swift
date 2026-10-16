import Foundation

// The meal planner: turns the day's targets into meals built from your own foods. Deterministic
// (no model chooses anything): a local search over realistic portion steps, starting from your usual
// meals, that must meet the hard constraints and then scores the soft ones. If it can't, it relaxes
// soft rules in a fixed order and says which.

struct PlanFood: Equatable {
    var key: String
    var name: String
    var per100: (kcal: Double, protein: Double, fat: Double, carbs: Double, fibre: Double)
    var step: Double = 10                 // grams per step (a whole unit for eggs, bars…)
    var usualGrams: Double = 100
    var maxGrams: Double = 400
    var usualSlots: [Int: Double] = [:]   // slot → how often you have it there (recency-weighted)
    var frequency: Double = 0             // overall
    var uses7: Int = 0                    // times planned in the last week (variety)

    static func == (a: PlanFood, b: PlanFood) -> Bool { a.key == b.key }
    func macros(_ g: Double) -> Macros {
        Macros(kcal: per100.kcal * g / 100, protein: per100.protein * g / 100, fat: per100.fat * g / 100, carbs: per100.carbs * g / 100, fibre: per100.fibre * g / 100)
    }
}

struct Macros: Equatable {
    var kcal = 0.0, protein = 0.0, fat = 0.0, carbs = 0.0, fibre = 0.0
    static func + (a: Macros, b: Macros) -> Macros { Macros(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, fat: a.fat + b.fat, carbs: a.carbs + b.carbs, fibre: a.fibre + b.fibre) }
    static func - (a: Macros, b: Macros) -> Macros { Macros(kcal: a.kcal - b.kcal, protein: a.protein - b.protein, fat: a.fat - b.fat, carbs: a.carbs - b.carbs, fibre: a.fibre - b.fibre) }
}

struct PlanItem: Equatable { var key: String; var grams: Double }

struct PlanSlot: Equatable {
    enum Kind: String, Codable { case meal, preWorkout, postWorkout, preSleep }
    var index: Int
    var minute: Int
    var kind: Kind
    var items: [PlanItem] = []
    var eaten = false                     // already logged: fixed
    var locked = false                    // you asked to keep it as is: fixed
    var fixed: Bool { eaten || locked }
}

struct PlanTargets: Equatable {
    var kcal: Double, protein: Double, fat: Double, carbs: Double
    var fibreFloor: Double = 0
    var fatFloor: Double = 40
    var weightKg: Double = 80
}

struct PlanOptions: Equatable {
    var kcalTolerance = 0.05              // ± share of calories
    var preSleepProtein = false
    var exclusions: Set<String> = []
    var variety = 0.5                     // 0 = repeat freely, 1 = avoid repeats
}

struct DayPlan: Equatable {
    var slots: [PlanSlot]
    var totals: Macros
    var relaxed: [String]                 // soft rules given up, in order
    var reasons: [EngineReason]
    var feasible: Bool                    // all hard constraints met
    var note: String?                     // when the day can't be hit sensibly
}

enum Planner {
    // MARK: Meal times

    /// Meal slots for a day: meals spaced across waking hours, a pre-workout meal in the window before
    /// training and a post-workout meal after (registry timing entries). Fasted training: no pre-meal.
    static func slots(wake: Int, sleep: Int, meals n: Int, training: (start: Int, minutes: Int)?, fasted: Bool = false,
                      preSleep: Bool = false, eatingWindow: (start: Int, end: Int)? = nil) -> [PlanSlot] {
        let lo = eatingWindow?.start ?? wake + 30, hi = eatingWindow?.end ?? sleep - 60
        let count = max(1, n)
        var times = (0..<count).map { lo + ($0 * max(hi - lo, 60)) / max(count - 1, 1) }
        if count == 1 { times = [lo] }
        var kinds = [PlanSlot.Kind](repeating: .meal, count: count)
        if let t = training {
            let preAt = t.start - Int(Evidence.value("timing.preWorkout.carbs") * 60)       // ~2 h before
            let postAt = t.start + t.minutes + 45                                            // within the post-workout window
            // Pre: the meal nearest to (and before) the target time moves there; post: likewise after.
            if !fasted, let i = times.indices.filter({ times[$0] < t.start }).min(by: { abs(times[$0] - preAt) < abs(times[$1] - preAt) }) {
                times[i] = max(lo, min(preAt, t.start - 60)); kinds[i] = .preWorkout
            }
            if let j = times.indices.filter({ kinds[$0] == .meal && times[$0] >= t.start }).min(by: { abs(times[$0] - postAt) < abs(times[$1] - postAt) }) {
                times[j] = min(max(postAt, t.start + t.minutes + 15), hi); kinds[j] = .postWorkout
            } else if let last = times.indices.last(where: { kinds[$0] == .meal }), times[last] < t.start + t.minutes {
                times[last] = min(t.start + t.minutes + 45, hi); kinds[last] = .postWorkout
            }
        }
        if preSleep, let last = times.indices.last, kinds[last] == .meal { times[last] = max(times[last], sleep - 60); kinds[last] = .preSleep }
        let order = times.indices.sorted { times[$0] < times[$1] }
        return order.enumerated().map { PlanSlot(index: $0.offset, minute: times[$0.element], kind: kinds[$0.element]) }
    }

    // MARK: Solve

    static func plan(_ targets: PlanTargets, slots input: [PlanSlot], foods all: [PlanFood], options: PlanOptions = PlanOptions()) -> DayPlan {
        let foods = all.filter { !options.exclusions.contains($0.key) }.sorted { ($0.frequency, $1.key) > ($1.frequency, $0.key) }
        let byKey = Dictionary(foods.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let allByKey = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var fixedTotal = Macros()
        for item in input.filter(\.fixed).flatMap(\.items) {
            if let f = allByKey[item.key] { fixedTotal = fixedTotal + f.macros(item.grams) }
        }
        let open = input.filter { !$0.fixed }
        var reasons: [EngineReason] = [.init(rule: "daily totals first", detail: "The plan has to hit the day's calories and protein; timing rules only shape how they're spread.", evidence: ["timing.totalFirst"])]

        // Eaten more than the day allows: protein and a sensible remainder, never compensation.
        let remaining = Macros(kcal: targets.kcal - fixedTotal.kcal, protein: targets.protein - fixedTotal.protein, fat: targets.fat - fixedTotal.fat,
                               carbs: targets.carbs - fixedTotal.carbs, fibre: targets.fibreFloor - fixedTotal.fibre)
        var note: String?
        var t = targets
        if !open.isEmpty, remaining.kcal < Double(open.count) * 250 {
            note = "Today's calories are mostly used. The rest of the plan aims for protein and light meals, not making up for it by eating very little; tomorrow starts fresh."
            let floorPerMeal = 250.0
            t.kcal = fixedTotal.kcal + max(remaining.kcal, Double(open.count) * floorPerMeal)
            t.fat = fixedTotal.fat; t.carbs = max(fixedTotal.carbs, targets.carbs)
            reasons.append(.init(rule: "day already full", detail: note!, evidence: ["timing.totalFirst"]))
        }
        if open.isEmpty {
            return DayPlan(slots: input, totals: fixedTotal, relaxed: [], reasons: reasons, feasible: hard(fixedTotal, t, options).isEmpty, note: note)
        }

        // Relaxation order: variety → usual slots → timing preferences → wider calorie tolerance.
        let stages: [(name: String, apply: (inout Weights) -> Void)] = [
            ("none", { _ in }),
            ("variety", { $0.variety = 0 }),
            ("usual meal slots", { $0.slotPreference = 0; $0.anySlot = true }),
            ("timing preferences", { $0.spread = 0; $0.trainingCarbs = 0; $0.preWorkoutFat = 0; $0.preSleep = 0 }),
            ("calorie tolerance ±10%", { $0.tolerance = 0.10 }),
        ]
        var w = Weights(tolerance: options.kcalTolerance, variety: options.variety)
        if note != nil { w.minMealKcal = 250 }
        var relaxed: [String] = []
        var best: (slots: [PlanSlot], score: Double, hard: [String])?
        for (si, stage) in stages.enumerated() {
            if si > 0 { stage.apply(&w); relaxed.append(stage.name) }
            let r = search(t, input: input, foods: foods, byKey: byKey, fixedTotal: fixedTotal, w: w, options: options)
            if best == nil || r.hard.count < best!.hard.count || (r.hard.count == best!.hard.count && r.score < best!.score) { best = r }
            if r.hard.isEmpty { best = r; break }
        }
        let b = best!
        let totals = b.slots.flatMap(\.items).reduce(Macros()) { $0 + (byKey[$1.key]?.macros($1.grams) ?? Macros()) } + Macros()
        let allTotals = fixedTotal + b.slots.filter { !$0.fixed }.flatMap(\.items).reduce(Macros()) { $0 + (byKey[$1.key]?.macros($1.grams) ?? Macros()) }
        _ = totals
        if !relaxed.isEmpty && !(relaxed.count == stages.count - 1 && !b.hard.isEmpty) {
            reasons.append(.init(rule: "relaxed", detail: "To fit the targets, these preferences were relaxed: \(relaxed.joined(separator: ", ")).", evidence: []))
        }
        if !b.hard.isEmpty { reasons.append(.init(rule: "can't fully fit", detail: "With your usual foods the plan misses: \(b.hard.joined(separator: ", ")). Adding a few more foods to your log will help.", evidence: [])) }
        if w.spread > 0 { reasons.append(.init(rule: "protein spread", detail: "Protein spread across meals (about 20–40 g each, every 3–4 hours).", evidence: ["timing.protein.everyHours", "protein.perMeal.gPerKg"])) }
        if input.contains(where: { $0.kind == .preWorkout }), w.trainingCarbs > 0 {
            reasons.append(.init(rule: "around training", detail: "More of the day's carbs before and after training; the meal before is lighter in fat and fibre.",
                                 evidence: ["timing.preWorkout.carbs", "timing.postWorkout.protein", "timing.preWorkout.lowFatFibre"]))
        }
        if input.contains(where: { $0.kind == .preSleep }) { reasons.append(.init(rule: "pre-sleep protein", detail: "A protein-rich last meal before bed.", evidence: ["timing.preSleep.casein"])) }
        return DayPlan(slots: b.slots, totals: allTotals, relaxed: b.hard.isEmpty ? relaxed : relaxed, reasons: reasons, feasible: b.hard.isEmpty, note: note)
    }

    struct Weights {
        var tolerance: Double
        var variety: Double
        var slotPreference = 1.0
        var anySlot = false
        var spread = 1.0
        var trainingCarbs = 1.0
        var preWorkoutFat = 1.0
        var preSleep = 1.0
        var minMealKcal = 0.0             // after a too-big day: every remaining meal still a real meal
    }

    /// Hard constraints that fail.
    static func hard(_ m: Macros, _ t: PlanTargets, _ o: PlanOptions, tolerance: Double? = nil) -> [String] {
        var out: [String] = []
        let tol = tolerance ?? o.kcalTolerance
        if abs(m.kcal - t.kcal) > max(t.kcal * tol, 60) { out.append("calories") }
        if m.protein < t.protein - 3 { out.append("protein") }
        if m.fat < t.fatFloor - 2 { out.append("fat floor") }
        if t.fibreFloor > 0, m.fibre < t.fibreFloor - 1 { out.append("fibre") }
        return out
    }

    private static func search(_ t: PlanTargets, input: [PlanSlot], foods: [PlanFood], byKey: [String: PlanFood], fixedTotal: Macros,
                               w: Weights, options: PlanOptions) -> (slots: [PlanSlot], score: Double, hard: [String]) {
        // Candidates per slot: your usual foods there first (or any of your foods once that's relaxed).
        func candidates(_ s: PlanSlot) -> [PlanFood] {
            let usual = foods.filter { ($0.usualSlots[s.index] ?? 0) > 0 }.sorted { ($0.usualSlots[s.index]!, $1.key) > ($1.usualSlots[s.index]!, $0.key) }
            let staples = foods.filter { $0.per100.protein >= 15 || $0.per100.carbs >= 50 }
            var list = Array(usual.prefix(8))
            for f in (w.anySlot ? foods : staples) where !list.contains(f) && list.count < 14 { list.append(f) }
            return list
        }
        // Start from your usual meals.
        var slots = input
        let cands = slots.map { $0.fixed ? [] : candidates($0) }
        for i in slots.indices where !slots[i].fixed && slots[i].items.isEmpty {
            slots[i].items = cands[i].filter { ($0.usualSlots[slots[i].index] ?? 0) > 0 }.prefix(3).map { PlanItem(key: $0.key, grams: $0.usualGrams) }
            if slots[i].items.isEmpty, let f = cands[i].first { slots[i].items = [PlanItem(key: f.key, grams: f.usualGrams)] }
        }
        func total(_ s: [PlanSlot]) -> Macros { s.filter { !$0.fixed }.flatMap(\.items).reduce(fixedTotal) { $0 + (byKey[$1.key]?.macros($1.grams) ?? Macros()) } }
        func score(_ s: [PlanSlot]) -> Double {
            let m = total(s)
            var x = 0.0
            // Hard constraints, heavily.
            let band = max(t.kcal * w.tolerance, 60)
            x += pow(max(0, abs(m.kcal - t.kcal) - band), 2) * 5 + pow(m.kcal - t.kcal, 2) * 0.002
            x += pow(max(0, t.protein - m.protein), 2) * 40
            x += pow(max(0, t.fatFloor - m.fat), 2) * 40
            if t.fibreFloor > 0 { x += pow(max(0, t.fibreFloor - m.fibre), 2) * 20 }
            // Soft: carbs and fat near target, not wildly over protein.
            x += pow(m.carbs - t.carbs, 2) * 0.02 + pow(m.fat - t.fat, 2) * 0.05 + pow(max(0, m.protein - t.protein * 1.15), 2) * 0.05
            let openSlots = s.filter { !$0.fixed }
            let perMeal = max(20, t.protein / Double(max(s.count, 1)))
            for sl in s {
                let mm = sl.items.reduce(Macros()) { $0 + (byKey[$1.key]?.macros($1.grams) ?? Macros()) }
                if !sl.fixed {
                    // Your foods, where you usually have them, near your usual portions.
                    for it in sl.items {
                        guard let f = byKey[it.key] else { continue }
                        let usual = f.usualSlots[sl.index] ?? 0
                        x -= w.slotPreference * 6 * min(usual, 3)
                        x += w.slotPreference * (usual == 0 ? 8 : 0)
                        x += pow((it.grams - f.usualGrams) / max(f.usualGrams, 30), 2) * 4
                        x += w.variety * Double(f.uses7) * 1.5
                    }
                    x += Double(max(0, sl.items.count - 5)) * 10
                    if w.minMealKcal > 0 { x += pow(max(0, w.minMealKcal - mm.kcal), 2) * 0.5 }
                }
                // Protein spread (registry: 20–40 g per meal).
                x += w.spread * pow(max(0, perMeal * 0.7 - mm.protein), 2) * 0.15
                // Carbs around training; lighter fat and fibre right before.
                if sl.kind == .preWorkout || sl.kind == .postWorkout { x -= w.trainingCarbs * min(mm.carbs, 120) * 0.15 }
                if sl.kind == .preWorkout { x += w.preWorkoutFat * (max(0, mm.fat - 15) * 0.8 + max(0, mm.fibre - 6) * 0.8) }
                if sl.kind == .preSleep, options.preSleepProtein { x += w.preSleep * pow(max(0, Evidence.value("timing.preSleep.casein") - mm.protein), 2) * 0.1 }
            }
            _ = openSlots
            return x
        }
        var cur = score(slots)
        // Moves, in a fixed order, until nothing improves (deterministic first-improvement).
        for _ in 0..<60 {
            var improved = false
            for i in slots.indices where !slots[i].fixed {
                // Resize
                for j in slots[i].items.indices {
                    guard let f = byKey[slots[i].items[j].key] else { continue }
                    for k in [-4.0, -1, 1, 4] {
                        var s2 = slots
                        let g = min(f.maxGrams, s2[i].items[j].grams + k * f.step)
                        if g < f.step { continue }
                        s2[i].items[j].grams = g
                        let sc = score(s2)
                        if sc < cur - 1e-9 { slots = s2; cur = sc; improved = true }
                    }
                }
                // Remove
                for j in slots[i].items.indices.reversed() where slots[i].items.count > 1 {
                    var s2 = slots; s2[i].items.remove(at: j)
                    let sc = score(s2)
                    if sc < cur - 1e-9 { slots = s2; cur = sc; improved = true; break }
                }
                // Add or swap in a candidate
                for f in cands[i] where !slots[i].items.contains(where: { $0.key == f.key }) {
                    var s2 = slots; s2[i].items.append(PlanItem(key: f.key, grams: f.usualGrams))
                    var sc = score(s2)
                    if sc < cur - 1e-9 { slots = s2; cur = sc; improved = true; continue }
                    for j in slots[i].items.indices {
                        s2 = slots; s2[i].items[j] = PlanItem(key: f.key, grams: f.usualGrams)
                        sc = score(s2)
                        if sc < cur - 1e-9 { slots = s2; cur = sc; improved = true; break }
                    }
                }
            }
            if !improved { break }
        }
        for i in slots.indices where !slots[i].fixed { slots[i].items = slots[i].items.map { PlanItem(key: $0.key, grams: ($0.grams * 10).rounded() / 10) } }
        return (slots, cur, hard(total(slots), t, options, tolerance: w.tolerance))
    }

    // MARK: From the eating profile

    /// Your foods as planner candidates (usual slots, portions and frequency from the profile).
    static func foods(from profile: EatingProfile, catalog: [String: (name: String, per100: (Double, Double, Double, Double, Double), unitGrams: Double?)]) -> [PlanFood] {
        var out: [String: PlanFood] = [:]
        for s in profile.slots {
            for u in s.foods {
                guard let c = catalog[u.key] else { continue }
                var f = out[u.key] ?? PlanFood(key: u.key, name: c.name, per100: (c.per100.0, c.per100.1, c.per100.2, c.per100.3, c.per100.4))
                f.usualSlots[s.index] = u.score
                f.frequency += u.score
                f.usualGrams = max(f.usualGrams == 100 ? 0 : f.usualGrams, u.grams)
                f.step = c.unitGrams ?? (c.per100.0 > 500 ? 5 : 10)
                f.maxGrams = max(f.step, min(f.usualGrams * 2.5, c.per100.0 > 500 ? 60 : 600))
                out[u.key] = f
            }
        }
        return out.values.sorted { $0.key < $1.key }
    }
}
