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
    var nova = 0                          // NOVA group (0: unknown)
    var basic = false                     // from the basic foods library (not one of yours)
    var basicAllowed = true               // allowed in Basic style (NOVA 1–2, or chosen as a basic)
    var staple = false                    // one of your staples (preferred; a protein main staple is a primary protein source)
    var canonical: String? = nil          // what it is underneath the brand (taxonomy)
    var stapleBand: MealBand? = nil       // the meal you set it as a staple for
    var tier = 1                          // 1 whole food, 2 simple staple, 3 convenience (only when in stock)
    var shownRatio = 1.0                  // the plan shows grams × this (you weigh it cooked, values are raw: the cooked ratio)
    var shownUnit = "g"                   // "g", "g cooked", "g raw"
    var unitName: String? = nil           // the product's unit when it comes in pieces ("egg", "bar", "slice"): portions shown in units
    /// A portion the way you'd measure it: "2 bars", "3 eggs", or "210 g cooked".
    func shown(_ g: Double) -> String {
        if let u = unitName, step > 0, abs((g / step).rounded() * step - g) < 0.5 {
            let n = Int((g / step).rounded())
            return "\(n) \(n == 1 ? u : PlanFood.plural(u))"
        }
        return "\(Int((g * shownRatio).rounded())) \(shownUnit)"
    }
    static func plural(_ u: String) -> String {
        if let r = u.range(of: " (") { return plural(String(u[..<r.lowerBound])) + u[r.lowerBound...] }
        if u.hasSuffix("s") { return u }
        if u.hasSuffix("y"), !u.hasSuffix("ey") { return u.dropLast() + "ies" }
        return u + (u.hasSuffix("ch") || u.hasSuffix("sh") ? "es" : "s")
    }

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

struct PlanItem: Equatable, Codable {
    var key: String
    var grams: Double
    var pinned: Bool? = nil               // you keep this portion (a locked food, or a serving you set): never resized
    var isPinned: Bool { pinned == true }
}

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
    var templateID: String? = nil         // a meal with its own template (the evening snack)
    var fixed: Bool { eaten || locked }
    var band: MealBand { MealBand.of(minute: minute) }
}

struct PlanTargets: Equatable {
    var kcal: Double, protein: Double, fat: Double, carbs: Double
    var fibreFloor: Double = 0
    var fatFloor: Double = 40
    var weightKg: Double = 80
    var mealCarbs: [Int: Double] = [:]    // carb target per meal (slot index → g), from the carb plan
    var preWorkoutMaxFat = 12.0           // g (template: pre-workout)
    var preWorkoutMaxFibre = 6.0
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
    var sizeOnly = false                  // the foods are chosen (templates): only size them, never add, remove or swap
    var quick = false                     // a shorter search (trying out a repair)
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
    struct Carbs: Equatable { var gPerKg: Double; var range: ClosedRange<Double>; var rangeIsTarget: Bool; var intra: Double; var recovery: Bool }
    var carbs: Carbs? = nil               // the day's carbs against the range for your phase
    var structure: [Int: MealStructure] = [:]   // slot index → template used and foods per slot (three-stage planner)
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
        let allStages: [(name: String, hard: Bool, apply: (inout Weights) -> Void)] = [
            ("none", false, { _ in }),
            ("variety", false, { $0.variety = 0 }),
            ("usual meal slots", false, { $0.slotPreference = 0; $0.anySlot = true }),
            ("timing preferences", false, { $0.trainingCarbs = 0; $0.preWorkoutFat = 0; $0.preSleep = 0 }),
            ("calories within ±5%", true, { $0.tolerance = max($0.tolerance, 0.05) }),
            ("calories within ±10%", true, { $0.tolerance = max($0.tolerance, 0.10) }),
        ]
        // With templates (size only) the preferences are already decided: only the calorie band can relax,
        // and the per-meal carb targets stay.
        let stages = options.sizeOnly ? allStages.filter { $0.name == "none" || $0.hard } : allStages
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
            // Widening the calorie band only helps when calories are what's missed.
            if options.sizeOnly && !r.hard.contains("calories") { break }
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
        if b.hard.contains("meal realism") {
            let list = issues(b.slots, byKey: byKey, t: t, checkBands: !options.sizeOnly).map(\.text).filter { !$0.contains("protein of the") }
            reasons.append(.init(rule: "meal realism", detail: "Not met: \(list.joined(separator: "; ")).", evidence: []))
        }
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

    static let proteinFatTolerance = 2.0

    /// Hard constraints that fail.
    static func hard(_ m: Macros, _ t: PlanTargets, _ o: PlanOptions, tolerance: Double? = nil) -> [String] {
        var out: [String] = []
        let tol = tolerance ?? o.kcalTolerance
        if abs(m.kcal - t.kcal) > max(t.kcal * tol, 40) { out.append("calories") }
        // Protein and the fat floor: a gap of up to 2 g counts as met (rounding, not worth another change).
        if m.protein < t.protein - proteinFatTolerance { out.append("protein") }
        if m.fat < t.fatFloor - proteinFatTolerance { out.append("fat floor") }
        if t.fibreFloor > 0, m.fibre < t.fibreFloor - 0.5 { out.append("fibre") }
        return out
    }

    private static func search(_ t: PlanTargets, input: [PlanSlot], foods: [PlanFood], byKey: [String: PlanFood], fixedTotal: Macros,
                               w: Weights, options: PlanOptions) -> (slots: [PlanSlot], score: Double, hard: [String]) {
        // Candidates per slot: your usual foods there first (or any of your foods once that's relaxed).
        func fits(_ f: PlanFood, _ s: PlanSlot) -> Bool { s.anyBand || f.bands.isEmpty || f.bands.contains(s.band) }
        // How much you have this food at this meal: from your log by slot, or a staple's chosen meal.
        func affinity(_ f: PlanFood, _ s: PlanSlot) -> Double {
            if let u = f.usualSlots[s.index] { return u }
            return f.usualSlots.isEmpty && f.bands.contains(s.band) ? 2 : 0
        }
        func candidates(_ s: PlanSlot) -> [PlanFood] {
            let foods = foods.filter { fits($0, s) }
            // Your usual foods for this meal first; then your other foods, most eaten first; then the
            // basic foods library, at least a couple per role so any role can be filled.
            let usual = foods.filter { affinity($0, s) > 0 && !$0.basic }.sorted { (affinity($0, s), $1.key) > (affinity($1, s), $0.key) }
            var list = Array(usual.prefix(8))
            // Before training: low-fat, low-fibre foods first (the meal has fat and fibre caps).
            let others = s.kind == .preWorkout ? foods.sorted { ($0.per100.fat + $0.per100.fibre * 2, $0.key) < ($1.per100.fat + $1.per100.fibre * 2, $1.key) } : foods
            for f in others where !f.basic && !list.contains(f) && list.count < 16 { list.append(f) }
            var perRole: [FoodRole: Int] = [:]
            for f in list { perRole[f.role, default: 0] += 1 }
            for f in foods where f.basic && !list.contains(f) && (perRole[f.role] ?? 0) < 3 { list.append(f); perRole[f.role, default: 0] += 1 }
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
        // The search runs on a compact copy: foods by index, values per gram, so a move costs a few
        // array reads (no name lookups). Same rules and scoring as `issues` and the weights below.
        var keys: [String] = [], idx: [String: Int] = [:]
        func reg(_ k: String) -> Int { if let i = idx[k] { return i }; idx[k] = keys.count; keys.append(k); return keys.count - 1 }
        for s in slots { for it in s.items { _ = reg(it.key) } }
        let candIdx = cands.map { $0.map { reg($0.key) } }
        let pf: [PlanFood?] = keys.map { byKey[$0] }
        let nF = keys.count, nS = slots.count
        let kc = pf.map { ($0?.per100.kcal ?? 0) / 100 }, pr = pf.map { ($0?.per100.protein ?? 0) / 100 }
        let ft = pf.map { ($0?.per100.fat ?? 0) / 100 }, cb = pf.map { ($0?.per100.carbs ?? 0) / 100 }, fb = pf.map { ($0?.per100.fibre ?? 0) / 100 }
        let known = pf.map { $0 != nil }
        let roleOf: [FoodRole?] = pf.map { $0?.role }
        let isCore = roleOf.map { $0?.isCore ?? false }, isAcc = roleOf.map { $0?.isAccompaniment ?? false }
        let isTreat = roleOf.map { $0 == .treat }, isPM = roleOf.map { $0 == .proteinMain }, isCS = roleOf.map { $0 == .carbSide }, isDrink = roleOf.map { $0 == .drink }
        let step = pf.map { $0?.step ?? 10 }, maxG = pf.map { $0?.maxGrams ?? 400 }, lowG = pf.map { max($0?.step ?? 10, $0?.minGrams ?? 0) }
        let usualG = pf.map { $0?.usualGrams ?? 100 }, uses7 = pf.map { Double($0?.uses7 ?? 0) }, maxDay = pf.map { $0?.maxPerDay ?? 99 }
        let basic = pf.map { $0?.basic ?? false }, stapleBonus = pf.map { f -> Double in f?.staple == true ? (f!.role == .proteinMain ? 8 : 4) : 0 }
        let fixed = slots.map(\.fixed), kind = slots.map(\.kind)
        let aff: [[Double]] = slots.map { s in pf.map { $0.map { affinity($0, s) } ?? 0 } }
        let inBand: [[Bool]] = slots.map { s in pf.map { f in f.map { fits($0, s) } ?? true } }
        let minP = slots.map { t.minProtein($0.kind) }
        let mealCarb: [Double?] = slots.map { t.mealCarbs[$0.index] }
        let checkBands = !options.sizeOnly
        let perMeal = max(20, t.protein / Double(max(nS, 1)))
        let band = max(t.kcal * w.tolerance, 40)
        var F = slots.map { $0.items.map { idx[$0.key]! } }, G = slots.map { $0.items.map(\.grams) }
        // Foods you keep at a portion are never resized, removed or swapped.
        var pinnedAt = Set<Int>()
        for (i, s) in slots.enumerated() { for it in s.items where it.isPinned { pinnedAt.insert(i * nF + idx[it.key]!) } }
        var counts = [Int](repeating: 0, count: nF)
        // Realism (hard) and the score together: a core food in every meal (protein main, carb side, dairy
        // or protein snack); condiments and fats only alongside one; a treat never alone and once a day;
        // at most two protein mains and two carb sides a meal; foods only at their meals; no food in
        // more meals than allowed; each meal's protein minimum and the pre-workout fat and fibre caps (graded).
        func eval(_ F: [[Int]], _ G: [[Double]]) -> (v: Int, sc: Double) {
            var v = 0, x = 0.0, treats = 0
            var tk = fixedTotal.kcal, tp = fixedTotal.protein, tf = fixedTotal.fat, tc = fixedTotal.carbs, tfi = fixedTotal.fibre
            for i in 0..<nF { counts[i] = 0 }
            for s in 0..<nS {
                let fs = F[s], gs = G[s]
                var mk = 0.0, mp = 0.0, mf = 0.0, mc = 0.0, mfi = 0.0
                for j in fs.indices {
                    let f = fs[j], g = gs[j]
                    var dup = false
                    for q in 0..<j where fs[q] == f { dup = true; break }
                    if !dup { counts[f] += 1 }
                    mk += kc[f] * g; mp += pr[f] * g; mf += ft[f] * g; mc += cb[f] * g; mfi += fb[f] * g
                }
                if !fixed[s] {
                    tk += mk; tp += mp; tf += mf; tc += mc; tfi += mfi
                    var core = false, acc = 0, tr = 0, pm = 0, cs = 0, drink = false
                    for j in fs.indices {
                        let f = fs[j]
                        if known[f] {
                            if isCore[f] { core = true }; if isAcc[f] { acc += 1 }; if isTreat[f] { tr += 1 }
                            if isPM[f] { pm += 1 }; if isCS[f] { cs += 1 }; if isDrink[f] { drink = true }
                        }
                        if checkBands && !inBand[s][f] { v += 1 }
                        // Your foods, where you usually have them, near your usual portions.
                        guard known[f] else { continue }
                        let u = aff[s][f]
                        x -= w.slotPreference * 6 * min(u, 3)
                        x += w.slotPreference * (u == 0 ? 8 : 0)
                        if basic[f] { x += 6 }               // the library fills gaps; your own foods come first
                        x -= stapleBonus[f]
                        x += pow((gs[j] - usualG[f]) / max(usualG[f], 30), 2) * 4
                        x += w.variety * uses7[f] * 1.5
                    }
                    treats += tr
                    if !fs.isEmpty && !core { v += 1 }
                    if acc > 2 { v += 1 }; if tr > 1 { v += 1 }; if pm > 2 { v += 1 }; if cs > 2 { v += 1 }; if drink { v += 1 }
                    if fs.count > 6 { v += 1 }
                    if mp < minP[s] - 0.5 { v += 1 + Int((minP[s] - mp) / 3) }
                    if kind[s] == .preWorkout {
                        if mf > t.preWorkoutMaxFat + 0.5 { v += 1 + Int((mf - t.preWorkoutMaxFat) / 3) }
                        if mfi > t.preWorkoutMaxFibre + 0.5 { v += 1 + Int((mfi - t.preWorkoutMaxFibre) / 1.5) }
                    }
                    x += Double(max(0, fs.count - 5)) * 10
                    if w.minMealKcal > 0 { x += pow(max(0, w.minMealKcal - mk), 2) * 0.5 }
                }
                // Protein spread (registry: 20–40 g per meal), and no 200 g-protein dinners.
                x += w.spread * pow(max(0, perMeal * 0.7 - mp), 2) * 0.15
                x += pow(max(0, mp - max(70, perMeal * 1.6)), 2) * 0.3
                // Carbs where the carb plan puts them (else simply more around training); lighter fat and fibre right before.
                let around = kind[s] == .preWorkout || kind[s] == .postWorkout
                if let target = mealCarb[s], !fixed[s] { x += w.trainingCarbs * pow(mc - target, 2) * (around ? 0.25 : 0.08) }
                else if t.mealCarbs.isEmpty, around { x -= w.trainingCarbs * min(mc, 120) * 0.15 }
                if kind[s] == .preWorkout { x += w.preWorkoutFat * (max(0, mf - 15) * 0.8 + max(0, mfi - 6) * 0.8) }
                if kind[s] == .preSleep, options.preSleepProtein { x += w.preSleep * pow(max(0, Evidence.value("timing.preSleep.casein") - mp), 2) * 0.1 }
            }
            for f in 0..<nF where known[f] && counts[f] > maxDay[f] { v += counts[f] - maxDay[f] }
            if treats > 1 { v += treats - 1 }
            // Hard constraints, heavily. Aim at the target: every kcal away costs, outside the band far more.
            let over = max(0, abs(tk - t.kcal) - band)
            // Inside the band calories count as met: only a light pull toward the middle, so fibre can still move them.
            x += pow(over, 2) * 5 + over * 30 + pow(tk - t.kcal, 2) * 0.4
            // Floors: quadratic, plus a linear part so small shortfalls (half a gram) still get closed.
            x += pow(max(0, t.protein - tp), 2) * 40 + max(0, t.protein - tp) * 60
            x += pow(max(0, t.fatFloor - tf), 2) * 40 + max(0, t.fatFloor - tf) * 50
            // Fibre comes last: linear and cheaper per gram than protein, the fat floor or calories outside
            // the band, so it never displaces them (it still beats every soft preference).
            if t.fibreFloor > 0 { x += max(0, t.fibreFloor - tfi) * 40 }
            // Soft: carbs and fat near target, not wildly over protein.
            x += pow(tc - t.carbs, 2) * 0.05 + pow(tf - t.fat, 2) * 0.3 + pow(max(0, tp - t.protein * 1.15), 2) * 0.05
            return (v, x)
        }
        var (curV, cur) = eval(F, G)
        // Moves until nothing improves: each round tries every resize, removal, addition and swap in
        // every meal and takes the best (ties: the first, so it stays deterministic).
        for _ in 0..<(options.quick ? 40 : 120) {
            var bestMove: (F: [[Int]], G: [[Double]], v: Int, sc: Double)?
            func consider(_ F2: [[Int]], _ G2: [[Double]]) {
                let (v2, sc) = eval(F2, G2)
                guard v2 <= curV, v2 < curV || sc < cur - 1e-9 else { return }
                if let b = bestMove, (b.v, b.sc) <= (v2, sc) { return }
                bestMove = (F2, G2, v2, sc)
            }
            for i in 0..<nS where !fixed[i] {
                for j in F[i].indices {
                    let f = F[i][j], g0 = G[i][j]
                    guard known[f], !pinnedAt.contains(i * nF + f) else { continue }
                    for k in [-4.0, -1, 1, 4] {
                        let g = min(maxG[f], g0 + k * step[f])
                        if g < lowG[f] - 1e-9 || g == g0 { continue }
                        var G2 = G; G2[i][j] = g; consider(F, G2)
                    }
                }
                if options.sizeOnly { continue }
                if F[i].count > 1 {
                    for j in F[i].indices where !pinnedAt.contains(i * nF + F[i][j]) { var F2 = F, G2 = G; F2[i].remove(at: j); G2[i].remove(at: j); consider(F2, G2) }
                }
                for f in candIdx[i] where !F[i].contains(f) {
                    var F2 = F, G2 = G; F2[i].append(f); G2[i].append(usualG[f]); consider(F2, G2)
                    for j in F[i].indices where !pinnedAt.contains(i * nF + F[i][j]) { F2 = F; G2 = G; F2[i][j] = f; G2[i][j] = usualG[f]; consider(F2, G2) }
                }
            }
            // Paired moves: one food up a step while another goes down (more oil, less rice), so the
            // search can trade between macros without passing through a worse day.
            if bestMove == nil {
                let pos = (0..<nS).flatMap { i in fixed[i] ? [] : F[i].indices.map { (i, $0) } }
                for (ia, ja) in pos {
                    let fa = F[ia][ja]
                    guard known[fa], !pinnedAt.contains(ia * nF + fa) else { continue }
                    let up = min(maxG[fa], G[ia][ja] + step[fa])
                    guard up > G[ia][ja] else { continue }
                    for (ib, jb) in pos where !(ib == ia && jb == ja) {
                        let fbi = F[ib][jb]
                        guard known[fbi], roleOf[fbi] != roleOf[fa], !pinnedAt.contains(ib * nF + fbi) else { continue }
                        let down = G[ib][jb] - step[fbi]
                        guard down >= lowG[fbi] - 1e-9 else { continue }
                        var G2 = G; G2[ia][ja] = up; G2[ib][jb] = down; consider(F, G2)
                    }
                }
            }
            guard let m = bestMove else { break }
            F = m.F; G = m.G; curV = m.v; cur = m.sc
        }
        for i in slots.indices where !slots[i].fixed {
            slots[i].items = zip(F[i], G[i]).map { f, g in
                pinnedAt.contains(i * nF + f) ? PlanItem(key: keys[f], grams: g, pinned: true) : PlanItem(key: keys[f], grams: (g * 10).rounded() / 10)
            }
        }
        func total(_ s: [PlanSlot]) -> Macros { s.filter { !$0.fixed }.flatMap(\.items).reduce(fixedTotal) { $0 + (byKey[$1.key]?.macros($1.grams) ?? Macros()) } }
        let shortCount = shortMeals(slots, t, byKey).count
        let realism = issues(slots, byKey: byKey, t: t, checkBands: !options.sizeOnly).filter { !$0.text.contains("protein of the") }
        return (slots, cur, hard(total(slots), t, options, tolerance: w.tolerance) + (shortCount > 0 ? ["protein per meal"] : [])
                + (realism.isEmpty ? [] : ["meal realism"]))
    }

    /// The realism rules that a plan breaks, each with its meal and weight (the search minimises the
    /// total; the plan reports the text). `checkBands`: foods only at their usual meals (off when
    /// templates decide which meal a food belongs to).
    static func issues(_ s: [PlanSlot], byKey: [String: PlanFood], t: PlanTargets, checkBands: Bool = true) -> [(weight: Int, text: String)] {
        var out: [(Int, String)] = []
        var count: [String: Int] = [:]
        for sl in s {
            for k in Set(sl.items.map(\.key)) { count[k, default: 0] += 1 }
            guard !sl.fixed else { continue }
            let meal = mealName(sl)
            let roles = sl.items.compactMap { byKey[$0.key]?.role }
            if !sl.items.isEmpty && !roles.contains(where: \.isCore) { out.append((1, "\(meal): no protein, carb base or dairy")) }
            if roles.filter(\.isAccompaniment).count > 2 { out.append((1, "\(meal): more than two condiments or fats")) }
            if roles.filter({ $0 == .treat }).count > 1 { out.append((1, "\(meal): more than one treat")) }
            if roles.filter({ $0 == .proteinMain }).count > 2 { out.append((1, "\(meal): more than two protein mains")) }
            if roles.filter({ $0 == .carbSide }).count > 2 { out.append((1, "\(meal): more than two carb sides")) }
            if roles.contains(.drink) { out.append((1, "\(meal): a drink")) }
            if sl.items.count > 6 { out.append((1, "\(meal): more than six foods")) }
            // The protein minimum for this meal (hard; reported if your foods can't reach it).
            let p = sl.items.reduce(0.0) { $0 + (byKey[$1.key]?.macros($1.grams).protein ?? 0) }
            // Graded, so the search sees every step toward the minimum.
            if p < t.minProtein(sl.kind) - 0.5 { out.append((1 + Int((t.minProtein(sl.kind) - p) / 3), "\(meal): \(Int(p)) g protein of the \(Int(t.minProtein(sl.kind))) g minimum")) }
            // Before training: fat and fibre caps (hard), graded so every step toward the cap counts.
            if sl.kind == .preWorkout {
                let fat = sl.items.reduce(0.0) { $0 + (byKey[$1.key]?.macros($1.grams).fat ?? 0) }
                let fib = sl.items.reduce(0.0) { $0 + (byKey[$1.key]?.macros($1.grams).fibre ?? 0) }
                if fat > t.preWorkoutMaxFat + 0.5 { out.append((1 + Int((fat - t.preWorkoutMaxFat) / 3), "meal before training: \(Int(fat)) g fat (cap \(Int(t.preWorkoutMaxFat)) g)")) }
                if fib > t.preWorkoutMaxFibre + 0.5 { out.append((1 + Int((fib - t.preWorkoutMaxFibre) / 1.5), "meal before training: \(Int(fib)) g fibre (cap \(Int(t.preWorkoutMaxFibre)) g)")) }
            }
            if checkBands {
                for it in sl.items { if let f = byKey[it.key], !(sl.anyBand || f.bands.isEmpty || f.bands.contains(sl.band)) { out.append((1, "\(meal): \(f.name) isn't a \(sl.band.label.lowercased()) food")) } }
            }
        }
        for (k, n) in count { if let f = byKey[k], n > f.maxPerDay { out.append((n - f.maxPerDay, "\(f.name) in \(n) meals (at most \(f.maxPerDay))")) } }
        let treats = s.filter { !$0.fixed }.flatMap(\.items).filter { byKey[$0.key]?.role == .treat }.count
        if treats > 1 { out.append((treats - 1, "\(treats) treats in the day (one at most)")) }
        return out
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
