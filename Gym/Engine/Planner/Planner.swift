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
    var minGrams: Double = 0
    var usualSlots: [Int: Double] = [:]   // slot → how often you have it there (recency-weighted)
    var frequency: Double = 0             // overall
    var uses7: Int = 0                    // times planned in the last week (variety)
    var bands: Set<MealBand> = []         // meals it belongs in (empty: any)
    var role: FoodRole = .proteinMain
    var maxPerDay = 2                     // meals a day it can appear in

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

struct PlanItem: Equatable, Codable { var key: String; var grams: Double }

struct PlanSlot: Equatable {
    enum Kind: String, Codable { case meal, preWorkout, postWorkout, preSleep }
    var index: Int
    var minute: Int
    var kind: Kind
    var items: [PlanItem] = []
    var eaten = false                     // already logged: fixed
    var locked = false                    // you asked to keep it as is: fixed
    var provisional = false               // eaten but not confirmed (looked too big): not counted yet
    var anyBand = false                   // Ramadan: iftar to suhoor, so breakfast foods are fine at night
    var fixed: Bool { eaten || locked }
    var band: MealBand { MealBand.of(minute: minute) }
}

struct PlanTargets: Equatable {
    var kcal: Double, protein: Double, fat: Double, carbs: Double
    var fibreFloor: Double = 0
    var fatFloor: Double = 40
    var weightKg: Double = 80
    /// Protein every meal must reach (g): ~0.3 g/kg, ~0.4 g/kg before and after training (registry).
    var mealProtein: Double { (weightKg * Evidence.value("protein.perMeal.min.gPerKg")).rounded() }
    var trainingMealProtein: Double { (weightKg * Evidence.value("protein.perMeal.gPerKg")).rounded() }
    func minProtein(_ k: PlanSlot.Kind) -> Double { k == .preWorkout || k == .postWorkout ? trainingMealProtein : mealProtein }
}

struct PlanOptions: Equatable {
    var kcalTolerance = 0.015             // ± share of calories that counts as on target (at least 40 kcal); ±5% / ±10% only when a day can't fit
    var preSleepProtein = false
    var exclusions: Set<String> = []
    var variety = 0.5                     // 0 = repeat freely, 1 = avoid repeats
    var trainingCarbBoost = false         // accepted proposal: even more of the day's carbs around training
}

struct DayPlan: Equatable {
    struct ShortMeal: Equatable { var index: Int; var protein: Double; var needed: Double }
    var slots: [PlanSlot]
    var totals: Macros
    var relaxed: [String]                 // preferences given up, in order
    var relaxedHard: [String] = []        // hard limits widened (calorie band), in order
    var misses: [String] = []             // hard constraints still not met
    var shortMeals: [ShortMeal] = []      // meals your foods can't bring to their protein minimum
    var kcalBand: Double = 0              // ± kcal the plan was held to
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
        // Spanish meal times when they fit your day: breakfast, lunch at 14:00, merienda, dinner at 21:30.
        let anchors: [Int: [Int]] = [3: [8 * 60 + 30, 14 * 60, 21 * 60 + 30], 4: [8 * 60, 14 * 60, 18 * 60, 21 * 60 + 30],
                                     5: [8 * 60, 11 * 60, 14 * 60, 18 * 60, 21 * 60 + 30], 6: [8 * 60, 11 * 60, 14 * 60, 17 * 60, 19 * 60 + 30, 21 * 60 + 45]]
        if eatingWindow == nil, let a = anchors[count] { times = a.map { min(max($0, lo), hi) } }
        var kinds = [PlanSlot.Kind](repeating: .meal, count: count)
        if let t = training {
            let end = t.start + t.minutes
            let preBy = Int(Evidence.value("timing.preWorkout.carbs") * 60)          // ~2 h before
            let postWithin = Int(Evidence.value("timing.postWorkout.protein") * 60)  // ~2 h after
            // Nothing during the session: a meal in [start − 60, end + 30] moves before or after it.
            for i in times.indices where times[i] >= t.start - 60 && times[i] <= end + 30 {
                times[i] = times[i] < (t.start + end) / 2 && !fasted ? max(lo, t.start - 90) : min(hi, end + 45)
            }
            // Before: the last meal before training, 1–3 h before (fasted: none).
            if !fasted, let i = times.indices.filter({ times[$0] < t.start }).max(by: { times[$0] < times[$1] }), t.start - times[i] <= 4 * 60 {
                times[i] = min(max(times[i], t.start - max(preBy, 60) - 60), t.start - 60); kinds[i] = .preWorkout
            }
            // After: the first meal after, within the post-workout window (moved earlier if needed).
            if let j = times.indices.filter({ times[$0] > end }).min(by: { times[$0] < times[$1] }) {
                times[j] = min(times[j], end + postWithin - 15); kinds[j] = .postWorkout
            } else if let last = times.indices.max(by: { times[$0] < times[$1] }), kinds[last] == .meal {
                times[last] = min(end + 45, hi); kinds[last] = .postWorkout
            }
        }
        if preSleep, let last = times.indices.last, kinds[last] == .meal { times[last] = max(times[last], sleep - 60); kinds[last] = .preSleep }
        let order = times.indices.sorted { times[$0] < times[$1] }
        return order.enumerated().map { PlanSlot(index: $0.offset, minute: times[$0.element], kind: kinds[$0.element], anyBand: eatingWindow != nil) }
    }

    // MARK: Solve

    static func plan(_ targets: PlanTargets, slots input: [PlanSlot], foods all: [PlanFood], options: PlanOptions = PlanOptions()) -> DayPlan {
        let foods = all.filter { !options.exclusions.contains($0.key) }.sorted { ($0.frequency, $1.key) > ($1.frequency, $0.key) }
        let byKey = Dictionary(foods.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let allByKey = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var fixedTotal = Macros()
        for item in input.filter({ $0.fixed && !$0.provisional }).flatMap(\.items) {
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
            note = "The rest of the plan aims for protein and light meals, not making up for it by eating very little; tomorrow starts fresh."
            let floorPerMeal = 250.0
            t.kcal = fixedTotal.kcal + max(remaining.kcal, Double(open.count) * floorPerMeal)
            t.fat = fixedTotal.fat; t.carbs = max(fixedTotal.carbs, targets.carbs)
            reasons.append(.init(rule: "day already full", detail: note!, evidence: ["timing.totalFirst"]))
        }
        if open.isEmpty {
            return DayPlan(slots: input, totals: fixedTotal, relaxed: [], reasons: reasons, feasible: hard(fixedTotal, t, options).isEmpty, note: note)
        }

        // Relaxation order: preferences first (variety → usual slots → timing preferences), then the one
        // hard limit that may widen, the calorie band (±5%, then ±10%), always reported. Protein (day and
        // per meal), the fat floor and the fibre floor never relax.
        let stages: [(name: String, hard: Bool, apply: (inout Weights) -> Void)] = [
            ("none", false, { _ in }),
            ("variety", false, { $0.variety = 0 }),
            ("usual meal slots", false, { $0.slotPreference = 0; $0.anySlot = true }),
            ("timing preferences", false, { $0.trainingCarbs = 0; $0.preWorkoutFat = 0; $0.preSleep = 0 }),
            ("calories within ±5%", true, { $0.tolerance = max($0.tolerance, 0.05) }),
            ("calories within ±10%", true, { $0.tolerance = max($0.tolerance, 0.10) }),
        ]
        var w = Weights(tolerance: options.kcalTolerance, variety: options.variety)
        if note != nil { w.minMealKcal = 250 }
        if options.trainingCarbBoost { w.trainingCarbs = 2.5 }
        var relaxed: [String] = []
        var best: (slots: [PlanSlot], score: Double, hard: [String])?
        var bestStage = 0
        for (si, stage) in stages.enumerated() {
            if si > 0 { stage.apply(&w); relaxed.append(stage.name) }
            let r = search(t, input: input, foods: foods, byKey: byKey, fixedTotal: fixedTotal, w: w, options: options)
            // Relaxing only helps if it fixes something: keep the earliest stage with the fewest misses.
            if best == nil || r.hard.count < best!.hard.count { best = r; bestStage = si }
            if r.hard.isEmpty { break }
        }
        let b = best!
        relaxed = Array(relaxed.prefix(bestStage))
        let relaxedHard = relaxed.filter { n in stages.contains { $0.name == n && $0.hard } }
        relaxed = relaxed.filter { n in !relaxedHard.contains(n) }
        var tolUsed = options.kcalTolerance
        if relaxedHard.contains("calories within ±5%") { tolUsed = max(tolUsed, 0.05) }
        if relaxedHard.contains("calories within ±10%") { tolUsed = max(tolUsed, 0.10) }
        let short = shortMeals(b.slots, t, byKey)
        let totals = b.slots.flatMap(\.items).reduce(Macros()) { $0 + (byKey[$1.key]?.macros($1.grams) ?? Macros()) } + Macros()
        if b.hard.contains("meal realism") { reasons.append(.init(rule: "meal realism", detail: "Some meals couldn't be built the usual way (a main food in each, foods at their usual meals). Adding staples helps.", evidence: [])) }
        let allTotals = fixedTotal + b.slots.filter { !$0.fixed }.flatMap(\.items).reduce(Macros()) { $0 + (byKey[$1.key]?.macros($1.grams) ?? Macros()) }
        _ = totals
        if !relaxed.isEmpty {
            reasons.append(.init(rule: "relaxed", detail: "To fit the targets, these preferences were relaxed: \(relaxed.joined(separator: ", ")).", evidence: []))
        }
        if !relaxedHard.isEmpty {
            reasons.append(.init(rule: "calorie band widened", detail: "The day couldn't be planned within ±\(Int(max(t.kcal * options.kcalTolerance, 40))) kcal of the target, so it was allowed \(relaxedHard.last!.replacingOccurrences(of: "calories within ", with: "")).", evidence: []))
        }
        for m in short {
            reasons.append(.init(rule: "protein per meal", detail: "The \(mealName(b.slots[m.index])) reaches \(Int(m.protein)) g protein of the \(Int(m.needed)) g minimum: none of your foods for that meal has enough protein. Add a protein staple for it (yogurt, eggs, whey, tuna…).", evidence: ["protein.perMeal.min.gPerKg", "protein.perMeal.gPerKg"]))
        }
        if !b.hard.isEmpty { reasons.append(.init(rule: "can't fully fit", detail: "With your usual foods the plan misses: \(b.hard.joined(separator: ", ")). Adding a few more foods to your log will help.", evidence: [])) }
        if w.spread > 0 { reasons.append(.init(rule: "protein spread", detail: "Protein spread across meals (about 20–40 g each, every 3–4 hours).", evidence: ["timing.protein.everyHours", "protein.perMeal.gPerKg"])) }
        if input.contains(where: { $0.kind == .preWorkout }), w.trainingCarbs > 0 {
            reasons.append(.init(rule: "around training", detail: "More of the day's carbs before and after training; the meal before is lighter in fat and fibre.",
                                 evidence: ["timing.preWorkout.carbs", "timing.postWorkout.protein", "timing.preWorkout.lowFatFibre"]))
        }
        if input.contains(where: { $0.kind == .preSleep }) { reasons.append(.init(rule: "pre-sleep protein", detail: "A protein-rich last meal before bed.", evidence: ["timing.preSleep.casein"])) }
        return DayPlan(slots: b.slots, totals: allTotals, relaxed: relaxed, relaxedHard: relaxedHard, misses: b.hard, shortMeals: short,
                       kcalBand: max(t.kcal * tolUsed, 40), reasons: reasons, feasible: b.hard.isEmpty, note: note)
    }

    static func mealName(_ s: PlanSlot) -> String {
        switch s.kind {
        case .preWorkout: return "meal before training"
        case .postWorkout: return "meal after training"
        case .preSleep: return "meal before bed"
        case .meal: return s.band.label.lowercased()
        }
    }

    /// Open meals below their protein minimum.
    static func shortMeals(_ slots: [PlanSlot], _ t: PlanTargets, _ byKey: [String: PlanFood]) -> [DayPlan.ShortMeal] {
        slots.indices.compactMap { i in
            let s = slots[i]
            guard !s.fixed else { return nil }
            let p = s.items.reduce(0.0) { $0 + (byKey[$1.key]?.macros($1.grams).protein ?? 0) }
            let need = t.minProtein(s.kind)
            return p < need - 0.5 ? .init(index: i, protein: p, needed: need) : nil
        }
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
        if abs(m.kcal - t.kcal) > max(t.kcal * tol, 40) { out.append("calories") }
        if m.protein < t.protein - 0.5 { out.append("protein") }
        if m.fat < t.fatFloor - 0.5 { out.append("fat floor") }
        if t.fibreFloor > 0, m.fibre < t.fibreFloor - 0.5 { out.append("fibre") }
        return out
    }

    private static func search(_ t: PlanTargets, input: [PlanSlot], foods: [PlanFood], byKey: [String: PlanFood], fixedTotal: Macros,
                               w: Weights, options: PlanOptions) -> (slots: [PlanSlot], score: Double, hard: [String]) {
        var cur = 0.0
        // Candidates per slot: your usual foods there first (or any of your foods once that's relaxed).
        func fits(_ f: PlanFood, _ s: PlanSlot) -> Bool { s.anyBand || f.bands.isEmpty || f.bands.contains(s.band) }
        // How much you have this food at this meal: from your log by slot, or a staple's chosen meal.
        func affinity(_ f: PlanFood, _ s: PlanSlot) -> Double {
            if let u = f.usualSlots[s.index] { return u }
            return f.usualSlots.isEmpty && f.bands.contains(s.band) ? 2 : 0
        }
        func candidates(_ s: PlanSlot) -> [PlanFood] {
            let foods = foods.filter { fits($0, s) }
            let usual = foods.filter { affinity($0, s) > 0 }.sorted { (affinity($0, s), $1.key) > (affinity($1, s), $0.key) }
            let staples = foods.filter { $0.per100.protein >= 15 || $0.per100.carbs >= 50 }
            var list = Array(usual.prefix(8))
            for f in (w.anySlot ? foods : staples) where !list.contains(f) && list.count < 14 { list.append(f) }
            return list
        }
        // Start from your usual meals.
        var slots = input
        let cands = slots.map { $0.fixed ? [] : candidates($0) }
        for i in slots.indices where !slots[i].fixed && slots[i].items.isEmpty {
            var items = cands[i].filter { affinity($0, slots[i]) > 0 }.prefix(3).map { PlanItem(key: $0.key, grams: $0.usualGrams) }
            // A meal starts from a core food (protein main, carb side, dairy, protein snack); the rest come with it.
            if !items.contains(where: { byKey[$0.key]?.role.isCore == true }), let m = cands[i].first(where: { $0.role.isCore }) {
                items.insert(PlanItem(key: m.key, grams: m.usualGrams), at: 0)
            }
            // Protein first: each meal starts with a protein food sized for its share of the day's protein.
            let share = max(t.minProtein(slots[i].kind), t.protein / Double(max(slots.count, 1)) * 0.8)
            let have = items.reduce(0.0) { $0 + (byKey[$1.key]?.macros($1.grams).protein ?? 0) }
            if have < share {
                let used = Dictionary(slots.prefix(i).flatMap { $0.items.map(\.key) }.map { ($0, 1) }, uniquingKeysWith: +)
                if let pf = cands[i].filter({ f in f.role.isProteinSource && f.per100.protein >= 8 && (used[f.key] ?? 0) < f.maxPerDay && !items.contains(where: { $0.key == f.key }) })
                    .max(by: { (affinity($0, slots[i]), $0.per100.protein, $1.key) < (affinity($1, slots[i]), $1.per100.protein, $0.key) }) {
                    let g = min(pf.maxGrams, max(pf.minGrams, pf.step, ((share - have) / pf.per100.protein * 100 / pf.step).rounded() * pf.step))
                    items.insert(PlanItem(key: pf.key, grams: g), at: 0)
                }
            }
            slots[i].items = Array(items.prefix(5))
            if slots[i].items.isEmpty, let f = cands[i].first { slots[i].items = [PlanItem(key: f.key, grams: f.usualGrams)] }
        }
        // Realism (hard): a core food in every meal (protein main, carb side, dairy or protein snack);
        // condiments and fats only alongside one; a treat never alone and once a day; at most two protein
        // mains and two carb sides a meal; foods only at their meals; no food in more meals than allowed.
        func violations(_ s: [PlanSlot]) -> Int {
            var v = 0
            var count: [String: Int] = [:]
            for sl in s {
                for k in Set(sl.items.map(\.key)) { count[k, default: 0] += 1 }
                guard !sl.fixed else { continue }
                let roles = sl.items.compactMap { byKey[$0.key]?.role }
                if !sl.items.isEmpty && !roles.contains(where: \.isCore) { v += 1 }
                if roles.filter(\.isAccompaniment).count > 2 { v += 1 }
                if roles.filter({ $0 == .treat }).count > 1 { v += 1 }
                if roles.filter({ $0 == .proteinMain }).count > 2 { v += 1 }
                if roles.filter({ $0 == .carbSide }).count > 2 { v += 1 }
                if roles.contains(.drink) { v += 1 }
                if sl.items.count > 5 { v += 1 }
                // The protein minimum for this meal (hard; reported if your foods can't reach it).
                let p = sl.items.reduce(0.0) { $0 + (byKey[$1.key]?.macros($1.grams).protein ?? 0) }
                if p < t.minProtein(sl.kind) - 0.5 { v += 1 }
                for it in sl.items { if let f = byKey[it.key], !fits(f, sl) { v += 1 } }
            }
            for (k, n) in count { if let f = byKey[k], n > f.maxPerDay { v += n - f.maxPerDay } }
            let treats = s.filter { !$0.fixed }.flatMap(\.items).filter { byKey[$0.key]?.role == .treat }.count
            if treats > 1 { v += treats - 1 }
            return v
        }
        var curV = violations(slots)
        func total(_ s: [PlanSlot]) -> Macros { s.filter { !$0.fixed }.flatMap(\.items).reduce(fixedTotal) { $0 + (byKey[$1.key]?.macros($1.grams) ?? Macros()) } }
        func score(_ s: [PlanSlot]) -> Double {
            let m = total(s)
            var x = 0.0
            // Hard constraints, heavily.
            // Aim at the target: every kcal away costs, and going outside the band costs far more.
            let band = max(t.kcal * w.tolerance, 40)
            x += pow(max(0, abs(m.kcal - t.kcal) - band), 2) * 5 + pow(m.kcal - t.kcal, 2) * 0.4
            x += pow(max(0, t.protein - m.protein), 2) * 40
            x += pow(max(0, t.fatFloor - m.fat), 2) * 40
            if t.fibreFloor > 0 { x += pow(max(0, t.fibreFloor - m.fibre), 2) * 20 }
            // Soft: carbs and fat near target, not wildly over protein.
            x += pow(m.carbs - t.carbs, 2) * 0.05 + pow(m.fat - t.fat, 2) * 0.3 + pow(max(0, m.protein - t.protein * 1.15), 2) * 0.05
            let openSlots = s.filter { !$0.fixed }
            let perMeal = max(20, t.protein / Double(max(s.count, 1)))
            for sl in s {
                let mm = sl.items.reduce(Macros()) { $0 + (byKey[$1.key]?.macros($1.grams) ?? Macros()) }
                if !sl.fixed {
                    // Your foods, where you usually have them, near your usual portions.
                    for it in sl.items {
                        guard let f = byKey[it.key] else { continue }
                        let usual = affinity(f, sl)
                        x -= w.slotPreference * 6 * min(usual, 3)
                        x += w.slotPreference * (usual == 0 ? 8 : 0)
                        x += pow((it.grams - f.usualGrams) / max(f.usualGrams, 30), 2) * 4
                        x += w.variety * Double(f.uses7) * 1.5
                    }
                    x += Double(max(0, sl.items.count - 5)) * 10
                    if w.minMealKcal > 0 { x += pow(max(0, w.minMealKcal - mm.kcal), 2) * 0.5 }
                }
                // Protein spread (registry: 20–40 g per meal), and no 200 g-protein dinners.
                x += w.spread * pow(max(0, perMeal * 0.7 - mm.protein), 2) * 0.15
                x += pow(max(0, mm.protein - max(70, perMeal * 1.6)), 2) * 0.3
                // Carbs around training; lighter fat and fibre right before.
                if sl.kind == .preWorkout || sl.kind == .postWorkout { x -= w.trainingCarbs * min(mm.carbs, 120) * 0.15 }
                if sl.kind == .preWorkout { x += w.preWorkoutFat * (max(0, mm.fat - 15) * 0.8 + max(0, mm.fibre - 6) * 0.8) }
                if sl.kind == .preSleep, options.preSleepProtein { x += w.preSleep * pow(max(0, Evidence.value("timing.preSleep.casein") - mm.protein), 2) * 0.1 }
            }
            _ = openSlots
            return x
        }
        cur = score(slots)
        // Moves until nothing improves: each round tries every resize, removal, addition and swap in
        // every meal and takes the best (ties: the first, so it stays deterministic).
        for _ in 0..<120 {
            var bestMove: (slots: [PlanSlot], v: Int, sc: Double)?
            func consider(_ s2: [PlanSlot]) {
                let v2 = violations(s2)
                guard v2 <= curV else { return }
                let sc = score(s2)
                guard v2 < curV || sc < cur - 1e-9 else { return }
                if let b = bestMove, (b.v, b.sc) <= (v2, sc) { return }
                bestMove = (s2, v2, sc)
            }
            for i in slots.indices where !slots[i].fixed {
                for j in slots[i].items.indices {
                    guard let f = byKey[slots[i].items[j].key] else { continue }
                    for k in [-4.0, -1, 1, 4] {
                        let g = min(f.maxGrams, slots[i].items[j].grams + k * f.step)
                        if g < max(f.step, f.minGrams) - 1e-9 || g == slots[i].items[j].grams { continue }
                        var s2 = slots; s2[i].items[j].grams = g; consider(s2)
                    }
                }
                if slots[i].items.count > 1 {
                    for j in slots[i].items.indices { var s2 = slots; s2[i].items.remove(at: j); consider(s2) }
                }
                for f in cands[i] where !slots[i].items.contains(where: { $0.key == f.key }) {
                    var s2 = slots; s2[i].items.append(PlanItem(key: f.key, grams: f.usualGrams)); consider(s2)
                    for j in slots[i].items.indices { s2 = slots; s2[i].items[j] = PlanItem(key: f.key, grams: f.usualGrams); consider(s2) }
                }
            }
            guard let m = bestMove else { break }
            slots = m.slots; curV = m.v; cur = m.sc
        }
        for i in slots.indices where !slots[i].fixed { slots[i].items = slots[i].items.map { PlanItem(key: $0.key, grams: ($0.grams * 10).rounded() / 10) } }
        let shortCount = shortMeals(slots, t, byKey).count
        return (slots, cur, hard(total(slots), t, options, tolerance: w.tolerance) + (shortCount > 0 ? ["protein per meal"] : [])
                + (curV - shortCount > 0 ? ["meal realism"] : []))
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
                f.bands.insert(MealBand.of(minute: s.typicalMinute))
                f = f.with(role: FoodRole.guess(name: c.name, kcal: c.per100.0, protein: c.per100.1, fat: c.per100.2, carbs: c.per100.3))
                out[u.key] = f
            }
        }
        return out.values.map { f in var f = f; f.bands.formUnion(MealBand.guess(name: f.name)); return f }.sorted { $0.key < $1.key }
    }

    /// Your staples as planner candidates: your portion, at your meal (cold start).
    static func foods(fromStaples staples: [Staple], catalog: [String: (name: String, per100: (Double, Double, Double, Double, Double), unitGrams: Double?)]) -> [PlanFood] {
        staples.compactMap { st in
            guard let c = catalog[st.key] else { return nil }
            let role = FoodRole.guess(name: c.name, kcal: c.per100.0, protein: c.per100.1, fat: c.per100.2, carbs: c.per100.3)
            let step = c.unitGrams ?? (c.per100.0 > 500 ? 5 : 10)
            return PlanFood(key: st.key, name: c.name, per100: (c.per100.0, c.per100.1, c.per100.2, c.per100.3, c.per100.4), step: step,
                            usualGrams: st.grams, usualSlots: [:], frequency: 5, bands: [st.band]).with(role: role, usual: st.grams)
        }.sorted { $0.key < $1.key }
    }
}
