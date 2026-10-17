import Foundation

// The three-stage planner. 1 Structure: each meal gets its template (pre/post-workout replace the
// meal in the training window). 2 Selection: each slot is filled with a specific food, ranked by your
// staples, your usual meals and the foods you eat together, how often you have it, the whole-food
// tier, and rotation across the week. 3 Portions: the solver only sizes the chosen foods to hit
// calories, protein, protein per meal, fat floor and fibre; if it can't, optional slots are dropped
// (or an off-by-default one added) and what failed is reported per slot.

struct MealStructure: Equatable {
    struct Fill: Equatable { var kind: TemplateSlot.Kind; var keys: [String]; var required: Bool }
    var template: String               // template name ("Lunch", "Pre-workout"…)
    var fill: [Fill]
    var unfilled: [String] = []        // required slots nothing could fill ("protein: no allowed food")
    var dropped: [String] = []         // optional slots left out to fit the day
}

struct BuildContext {
    var patterns = MealPatterns()
    var usualMeals: [UsualMeal] = []          // confirmed ones count most
    var recent: [String: Int] = [:]           // canonical → times planned on the days before (this week)
    var variety = 0.5                         // 0 same meals daily … 1 different each day
    var wholeFood = 1.0                       // weight of the lower-NOVA preference (moderate)
    var inStock: Set<String> = []             // canonical ids of tier 3 foods (and whey) you have
    var removed: Set<String> = []             // simple foods you'd never buy
    var sameProteinTwice = false              // allow the same protein at lunch and dinner
    var treats = false
    var basicStyle = false                    // "Basic": whole foods only (NOVA 1–2 or chosen basics), hard
    var offset = 0                            // regenerate: take the n-th best choice for unlocked slots
}

enum MealBuilder {
    /// Stage 2 for one meal: a food for each slot of its template. `taken` are canonical ids already in
    /// today's other meals (for the lunch/dinner protein rule).
    static func select(_ template: MealTemplate, slot: PlanSlot, foods: [PlanFood], ctx: BuildContext, taken: [String: MealBand], usedToday: [String: Int] = [:],
                       budget: Double? = nil) -> (items: [PlanItem], structure: MealStructure) {
        var chosen: [PlanFood] = []
        var fills: [MealStructure.Fill] = []
        var unfilled: [String] = []
        let band = slot.band
        func allowed(_ f: PlanFood, _ ts: TemplateSlot) -> Bool {
            guard let c = f.canonical, ts.allowed.contains(c), !ctx.removed.contains(c) else { return false }
            if Taxonomy.needsStock(c) && !ctx.inStock.contains(c) { return false }
            // Basic: your staples and the basic foods library only, NOVA 1–2 (or a basic you chose despite its NOVA).
            if ctx.basicStyle && !((f.staple || f.basic) && ((1...2).contains(f.nova) || (f.basic && f.basicAllowed))) { return false }
            return true
        }
        func score(_ f: PlanFood, _ ts: TemplateSlot) -> Double {
            let c = f.canonical ?? f.key
            var x = 0.0
            // A staple counts most at the meal you set it for (eggs as a lunch staple aren't a merienda default).
            if f.staple { x += f.stapleBand == nil || f.stapleBand == band ? 3 : 0.8 }
            // Macro fit: a protein slot wants a lean, protein-dense food (a cut has little fat to spare);
            // carb slots want carbs, not fat.
            let kcal = max(f.per100.kcal, 1)
            if ts.kind == .protein { x += 8 * (f.per100.protein * 4 / kcal - 0.55) }
            if ts.kind == .vegetable || ts.kind == .pulses { x += 0.4 * f.per100.fibre }          // fibre for the floor
            // The meal's share of the day: a food whose smallest sensible portion takes more than its part of
            // the meal's calories ranks lower (no 288-kcal dates in a 350-kcal merienda).
            if let b = budget, b > 0 {
                let share: Double = [.protein: 0.5, .carbBase: 0.45, .carb: 0.45, .bread: 0.2, .fruit: 0.2, .spread: 0.12, .fatOrSauce: 0.12, .pulses: 0.2, .vegetable: 0.15, .treat: 0.3][ts.kind] ?? 0.3
                let minKcal = max(f.minGrams, f.step) * kcal / 100
                x -= 4 * max(0, minKcal / (share * b) - 1)
            }
            if [.carbBase, .carb, .bread].contains(ts.kind) { x -= 4 * (f.per100.fat * 9 / kcal) }
            let others = chosen.compactMap(\.canonical)
            for u in ctx.usualMeals where u.band == band && u.foods.contains(c) {
                let overlap = Double(others.filter { u.foods.contains($0) }.count + 1) / Double(u.foods.count)
                x += (u.confirmed ? 5 : 2) * overlap
            }
            x += 3 * ctx.patterns.fit(c, with: others, at: band)
            x += log1p(ctx.patterns.frequency(c, at: band) + (f.staple ? 0 : f.frequency) / 5)
            x += Double(2 - f.tier) * 0.8                                   // tier 1 +0.8, tier 2 0, tier 3 −0.8
            x -= ctx.wholeFood * 0.4 * Double(max(0, f.nova - 1))
            x -= ctx.variety * 1.2 * Double(ctx.recent[c] ?? 0)             // rotation across the week
            if ts.kind == .protein { x -= ctx.variety * 0.8 * Double(ctx.recent["family:" + Taxonomy.family(c)] ?? 0) }
            if c == ts.defaultFood { x += 0.5 }
            if f.basic { x -= 0.5 }
            return x
        }
        for ts in template.slots {
            guard ts.required || ts.defaultOn else { fills.append(.init(kind: ts.kind, keys: [], required: false)); continue }
            var pool = foods.filter { allowed($0, ts) && !chosen.contains($0) && (usedToday[$0.key] ?? 0) < $0.maxPerDay }
            // One protein main per family a day (no turkey before and after training, no chicken at lunch and
            // dinner) unless you allow repeats; never a tier 3 food as a meal's only protein.
            if ts.kind == .protein {
                if !ctx.sameProteinTwice { pool = pool.filter { f in f.role != .proteinMain || taken["family:" + Taxonomy.family(f.canonical ?? "")] == nil } }
                pool = pool.filter { $0.tier < 3 }
            }
            // One food per canonical (your own product first: staples, then most eaten).
            var best: [String: PlanFood] = [:]
            for f in pool { let c = f.canonical ?? f.key; if let b = best[c], score(b, ts) >= score(f, ts) { continue }; best[c] = f }
            let ranked = best.values.sorted { (score($0, ts), $1.key) > (score($1, ts), $0.key) }
            guard !ranked.isEmpty else {
                if ts.required { unfilled.append("\(ts.kind.label.lowercased()): none of the allowed foods is available") }
                fills.append(.init(kind: ts.kind, keys: [], required: ts.required)); continue
            }
            let pick = ranked[min(ctx.offset, ranked.count - 1)]
            var picks = [pick]
            // A spread slot can take a second food you eat with the first (peanut butter and jam).
            if ts.maxFoods > 1, let second = ranked.dropFirst().first(where: { ctx.patterns.association(pick.canonical ?? "", $0.canonical ?? "", at: band) > 0.3 }) { picks.append(second) }
            chosen += picks
            fills.append(.init(kind: ts.kind, keys: picks.map(\.key), required: ts.required))
        }
        let items = chosen.map { f -> PlanItem in
            var g = f.usualGrams
            if let units = template.slots.first(where: { $0.allowed.contains(f.canonical ?? "") })?.maxUnits[f.canonical ?? ""] { g = min(g, Double(units) * f.step) }
            return PlanItem(key: f.key, grams: g)
        }
        return (items, MealStructure(template: template.name, fill: fills, unfilled: unfilled))
    }

    /// How far a plan is from its hard constraints (lower is better): protein and the per-meal minimum
    /// first, then calories, then the fat floor and fibre.
    static func severity(_ p: DayPlan, _ t: PlanTargets) -> Double {
        let band = max(40, t.kcal * 0.015)
        return max(0, t.protein - p.totals.protein) * 4 + p.shortMeals.reduce(0) { $0 + ($1.needed - $1.protein) * 3 }
            + max(0, abs(p.totals.kcal - t.kcal) - band) / 10 + max(0, t.fatFloor - p.totals.fat) * 2 + max(0, t.fibreFloor - p.totals.fibre) * 1.5
            + Double(p.misses.contains("meal realism") ? 20 : 0)
    }

    /// Stages 1–3 for a day.
    static func plan(_ targets: PlanTargets, slots input: [PlanSlot], foods all: [PlanFood], templates: [MealTemplate], ctx: BuildContext,
                     options: PlanOptions = PlanOptions()) -> (plan: DayPlan, structure: [Int: MealStructure]) {
        var foods = all.filter { !options.exclusions.contains($0.key) }
        func basicOK(_ f: PlanFood) -> Bool { !ctx.basicStyle || ((f.staple || f.basic) && ((1...2).contains(f.nova) || (f.basic && f.basicAllowed))) }
        // Portion limits: an absolute maximum per food in a meal (one tub of queso batido) and at least
        // 150 g of vegetables.
        for i in foods.indices {
            if let c = foods[i].canonical, let mx = Portion.absoluteMax[c] {
                foods[i].maxGrams = max(foods[i].step, min(foods[i].maxGrams, mx))
                foods[i].usualGrams = min(foods[i].usualGrams, foods[i].maxGrams); foods[i].minGrams = min(foods[i].minGrams, foods[i].maxGrams)
            }
            if foods[i].role == .vegetable {
                foods[i].minGrams = max(foods[i].minGrams, Portion.vegetableMin); foods[i].maxGrams = max(foods[i].maxGrams, 2 * Portion.vegetableMin)
                foods[i].usualGrams = max(foods[i].usualGrams, Portion.vegetableMin)
            }
        }
        // Template limits on units (3 chocolate rice cakes) become portion caps.
        for t in templates { for ts in t.slots { for (c, n) in ts.maxUnits { for i in foods.indices where foods[i].canonical == c { foods[i].maxGrams = min(foods[i].maxGrams, Double(n) * foods[i].step) } } } }
        var slots = input
        var structure: [Int: MealStructure] = [:]
        var taken: [String: MealBand] = [:]
        func mark(_ key: String, _ band: MealBand) {
            guard let c = foods.first(where: { $0.key == key })?.canonical else { return }
            taken[c] = band; taken["family:" + Taxonomy.family(c)] = band
        }
        var used: [String: Int] = [:]
        for s in slots where s.fixed { for it in s.items { mark(it.key, s.band); used[it.key, default: 0] += 1 } }
        // Each open meal's calorie budget: what's left of the day after eaten and locked meals, by the
        // meal's carb weight (or evenly).
        let byKey = Dictionary(foods.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let fixedKcal = slots.filter(\.fixed).flatMap(\.items).reduce(0.0) { $0 + (byKey[$1.key]?.macros($1.grams).kcal ?? 0) }
        let open = slots.filter { !$0.fixed }
        let weights = Dictionary(open.map { s in (s.index, max(0.3, targets.mealCarbs[s.index].map { $0 / max(targets.carbs / Double(max(open.count, 1)), 1) } ?? 1)) }, uniquingKeysWith: { a, _ in a })
        let wsum = weights.values.reduce(0, +)
        func budget(_ s: PlanSlot) -> Double { max(150, (targets.kcal - fixedKcal) * (weights[s.index] ?? 1) / max(wsum, 1)) }
        // Stage 1 + 2.
        for i in slots.indices where !slots[i].fixed {
            guard let t = MealTemplates.template(for: slots[i], in: templates) else { continue }
            let (items, st) = select(t, slot: slots[i], foods: foods, ctx: ctx, taken: taken, usedToday: used, budget: budget(slots[i]))
            for it in items { used[it.key, default: 0] += 1 }
            slots[i].items = items
            structure[slots[i].index] = st
            for it in items { mark(it.key, slots[i].band) }
        }
        // Stage 3: size only, then repair. When a hard constraint is missed, first fill the optional slot that
        // fixes it, re-solve, and keep the change only if the day gets closer: oil or peanut butter for the
        // fat floor; vegetables, pulses or fruit for fibre; a second protein for a meal short of its
        // minimum; a carb (fruit, jam, dates…) for the meal before training; and when the day runs over,
        // optional items out (bread, spread, fruit, sauce). Misses are reported only if nothing fixes them.
        var o = options; o.sizeOnly = true
        func solve(quick: Bool = false) -> DayPlan { var q = o; q.quick = quick; return Planner.plan(targets, slots: slots, foods: foods, options: q) }
        var best = solve()
        // Repairs start from the sized plan (a warm start): one change then settles in a few steps.
        var bestSlots = best.slots.count == slots.count ? best.slots : slots, bestStructure = structure
        var coldSlots = slots                    // the same plan at usual portions (for a cold start)
        slots = bestSlots
        func meal(_ i: Int) -> MealTemplate? { MealTemplates.template(for: slots[i], in: templates) }
        func canon(_ key: String) -> String? { byKey[key]?.canonical }
        func usedCount(_ key: String) -> Int { slots.reduce(0) { $0 + ($1.items.contains { $0.key == key } ? 1 : 0) } }
        // Your best food for a slot kind in a meal, among `allowed`, not already there or used up today.
        func pick(_ i: Int, allowed: [String], rank: (PlanFood) -> Double) -> PlanFood? {
            foods.filter { f in guard let c = f.canonical, allowed.contains(c), basicOK(f), !ctx.removed.contains(c) else { return false }
                if Taxonomy.needsStock(c) && !ctx.inStock.contains(c) { return false }
                return !slots[i].items.contains { $0.key == f.key } && usedCount(f.key) < f.maxPerDay }
                .max { (rank($0) + ($0.staple ? 2 : 0) + log1p($0.frequency) - ($0.basic ? 0.5 : 0), $1.key) < (rank($1) + ($1.staple ? 2 : 0) + log1p($1.frequency) - ($1.basic ? 0.5 : 0), $0.key) }
        }
        // A repair only uses a slot the meal's template has, with foods it allows there.
        func slotFor(_ i: Int, _ kinds: [TemplateSlot.Kind], _ wanted: [String]) -> (kind: TemplateSlot.Kind, allowed: [String])? {
            for k in kinds { if let ts = meal(i)?.slots.first(where: { $0.kind == k }) {
                let a = wanted.filter { ts.allowed.contains($0) }
                if !a.isEmpty { return (k, a) } } }
            return nil
        }
        func add(_ i: Int, _ f: PlanFood, _ kind: TemplateSlot.Kind) {
            slots[i].items.append(PlanItem(key: f.key, grams: f.usualGrams))
            if var st = structure[slots[i].index] { st.fill.append(.init(kind: kind, keys: [f.key], required: false)); st.dropped.removeAll { $0 == kind.label.lowercased() }; structure[slots[i].index] = st }
        }
        func remove(_ i: Int, _ key: String, _ kind: TemplateSlot.Kind) {
            slots[i].items.removeAll { $0.key == key }
            if var st = structure[slots[i].index] {
                st.dropped.append(kind.label.lowercased())
                if let j = st.fill.lastIndex(where: { $0.keys.contains(key) }) { st.fill[j].keys.removeAll { $0 == key } }
                structure[slots[i].index] = st
            }
        }
        func preCarbsShort(_ p: DayPlan) -> Double {
            guard let sl = p.slots.first(where: { $0.kind == .preWorkout && !$0.fixed }), let t = targets.mealCarbs[sl.index] else { return 0 }
            let c = sl.items.reduce(0.0) { $0 + (byKey[$1.key]?.macros($1.grams).carbs ?? 0) }
            return max(0, t * 0.85 - c)
        }
        func score(_ p: DayPlan) -> Double { severity(p, targets) + preCarbsShort(p) / 4 }
        var repairsTried: [String] = []
        for _ in 0..<12 {
            var candidates: [(String, () -> Void)] = []
            let open = slots.indices.filter { !slots[$0].fixed }
            let mainMeals = open.filter { slots[$0].kind != .preWorkout && [MealTemplate.Meal.lunch, .dinner, .postWorkout].contains(meal($0)?.meal ?? .breakfast) }
            let lightMeals = open.filter { [MealTemplate.Meal.breakfast, .merienda].contains(meal($0)?.meal ?? .lunch) }
            // Over calories: optional items out (never around training, never the oil while fat is at its floor).
            if best.totals.kcal > targets.kcal + max(40, targets.kcal * options.kcalTolerance) {
                for i in open where slots[i].kind != .preWorkout && slots[i].kind != .postWorkout {
                    for f in structure[slots[i].index]?.fill ?? [] where !f.required && [.bread, .spread, .fruit, .treat, .fatOrSauce].contains(f.kind) {
                        for k in f.keys {
                            if byKey[k]?.role == .fatSource, best.totals.fat <= targets.fatFloor + 3 { continue }
                            candidates.append(("drop \(f.kind.label)", { remove(i, k, f.kind) }))
                        }
                    }
                }
            }
            // A carb base squeezed under half its usual portion: the bread side or spread goes instead.
            for sl in best.slots where !sl.fixed && sl.kind != .preWorkout && sl.kind != .postWorkout {
                guard let i = slots.firstIndex(where: { $0.index == sl.index }), let st = structure[sl.index],
                      let base = st.fill.first(where: { $0.kind == .carbBase })?.keys.first, let it = sl.items.first(where: { $0.key == base }),
                      let f = byKey[base], it.grams < f.usualGrams * 0.5 else { continue }
                for fl in st.fill where [.bread, .spread].contains(fl.kind) { for k in fl.keys { candidates.append(("drop \(fl.kind.label) for the carb base", { remove(i, k, fl.kind) })) } }
            }
            // Fat floor: olive oil at lunch, dinner or after training; peanut butter (or nuts) at breakfast or merienda.
            if best.misses.contains("fat floor") {
                for i in mainMeals { if let sl = slotFor(i, [.fatOrSauce], ["olive-oil", "oil"]), let f = pick(i, allowed: sl.allowed, rank: { _ in 0 }) { candidates.append(("oil for the fat floor", { add(i, f, sl.kind) })) } }
                for i in lightMeals { if let sl = slotFor(i, [.spread], ["peanut-butter", "nuts"]), let f = pick(i, allowed: sl.allowed, rank: { $0.per100.protein / 10 }) { candidates.append(("peanut butter for the fat floor", { add(i, f, sl.kind) })) } }
            }
            // Fibre: vegetables or pulses at lunch and dinner, fruit at breakfast and merienda.
            if best.misses.contains("fibre") {
                for i in mainMeals {
                    if let sl = slotFor(i, [.vegetable], MealTemplates.vegetables), let f = pick(i, allowed: sl.allowed, rank: { $0.per100.fibre }) { candidates.append(("vegetables for fibre", { add(i, f, sl.kind) })) }
                    if let sl = slotFor(i, [.pulses], ["pulses"]), let f = pick(i, allowed: sl.allowed, rank: { $0.per100.fibre }) { candidates.append(("pulses for fibre", { add(i, f, sl.kind) })) }
                }
                for i in lightMeals {
                    if let sl = slotFor(i, [.fruit, .carb], MealTemplates.fruits), let f = pick(i, allowed: sl.allowed, rank: { $0.per100.fibre * 100 / max($0.per100.kcal, 1) }) { candidates.append(("fruit for fibre", { add(i, f, sl.kind) })) }
                }
            }
            // A meal short of its protein minimum (or the day short of protein): a second protein from that meal's protein slot.
            let short = Set(best.shortMeals.map { best.slots[$0.index].index })
            for i in open where short.contains(slots[i].index) || (best.misses.contains("protein") && slots[i].kind != .preWorkout) {
                guard let ts = meal(i)?.slots.first(where: { $0.kind == .protein }) else { continue }
                let have = Set(slots[i].items.compactMap { canon($0.key).map(Taxonomy.family) })
                if let f = pick(i, allowed: ts.allowed.filter { !have.contains(Taxonomy.family($0)) }, rank: { 8 * $0.per100.protein * 4 / max($0.per100.kcal, 1) }) {
                    candidates.append(("a second protein", { add(i, f, .protein) }))
                }
            }
            // The meal before training short of its carbs: a carb from its template (fruit, jam, dates, rice cakes…).
            if preCarbsShort(best) > 0, let i = open.first(where: { slots[$0].kind == .preWorkout }), let t = meal(i) {
                for ts in t.slots where [.carb, .fruit, .spread].contains(ts.kind) {
                    if let f = pick(i, allowed: ts.allowed, rank: { $0.per100.carbs / 10 - $0.per100.fat - $0.per100.fibre }) { candidates.append(("a carb before training", { add(i, f, ts.kind) })) }
                }
            }
            // Try each; keep the best improvement.
            var improved: (score: Double, slots: [PlanSlot], structure: [Int: MealStructure], plan: DayPlan, name: String)?
            let base = score(best)
            // Warm start first (fast); if nothing helps, the same repairs from usual portions (a cold start
            // can find a different balance).
            for start in [bestSlots, coldSlots] {
                for (name, apply) in candidates {
                    slots = start; structure = bestStructure
                    apply()
                    let r = solve()
                    let sc = score(r)
                    if sc < (improved?.score ?? base) - 0.01 { improved = (sc, slots, structure, r, name) }
                }
                if improved != nil { break }
            }
            slots = bestSlots; structure = bestStructure
            guard var m = improved else { break }
            // The chosen repair gets the full search.
            slots = m.slots; structure = m.structure
            let full = solve()
            if score(full) <= m.score { m.plan = full }
            best = m.plan; coldSlots = m.slots; bestSlots = m.plan.slots.count == m.slots.count ? m.plan.slots : m.slots; bestStructure = m.structure; slots = bestSlots; structure = m.structure
            repairsTried.append(m.name)
            if best.feasible && preCarbsShort(best) == 0 { break }
        }
        if preCarbsShort(best) > 0 {
            best.misses.append("pre-workout carbs")
            best.reasons.append(.init(rule: "pre-workout carbs", detail: "The meal before training is \(Int(preCarbsShort(best) / 0.85)) g short of its carb target with the foods allowed in it.", evidence: ["carbs.preWorkout.gPerKg"]))
        }
        if !repairsTried.isEmpty { best.reasons.append(.init(rule: "repaired", detail: "To meet the targets: \(repairsTried.joined(separator: ", ")).", evidence: [])) }
        structure = bestStructure
        // Report what the structure couldn't do.
        for (i, st) in structure where !st.unfilled.isEmpty {
            let name = st.template.lowercased()
            best.reasons.append(.init(rule: "slot not filled", detail: "\(st.template): \(st.unfilled.joined(separator: "; ")). Add a staple for it or allow more foods in the \(name) template.", evidence: []))
            _ = i
        }
        best.reasons.insert(.init(rule: "meal structure", detail: "Each meal follows its template (Planner settings → Meal templates); the foods are chosen from your staples, your usual meals and simple whole foods, then only the portions are sized to your targets.", evidence: ["timing.totalFirst"]), at: 0)
        return (best, structure)
    }
}
