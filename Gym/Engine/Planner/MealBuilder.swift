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
        // Stage 3: size only. If it doesn't fit, drop optional slots (sauce, bread, second spread, fruit)
        // one at a time; if calories are short, add an off-by-default side (pulses). Keep the best.
        var o = options; o.sizeOnly = true
        var best = Planner.plan(targets, slots: slots, foods: foods, options: o)
        var bestStructure = structure
        let dropOrder: [TemplateSlot.Kind] = [.bread, .spread, .fruit, .treat, .fatOrSauce]
        var tries = 0
        // Drop one optional bread side or spread (the one in the meal with the most carbs), to make room.
        func dropBreadOrSpread() -> Bool {
            let cands = slots.indices.compactMap { i -> (Int, String, TemplateSlot.Kind, Double)? in
                // Never from the meals around training: their fruit and jam are the carbs before and after.
                guard !slots[i].fixed, slots[i].kind != .preWorkout, slots[i].kind != .postWorkout, let st = structure[slots[i].index] else { return nil }
                for kind in [TemplateSlot.Kind.bread, .spread] { if let f = st.fill.last(where: { $0.kind == kind && !$0.keys.isEmpty }), let k = f.keys.last {
                    let carbs = best.slots.first { $0.index == slots[i].index }?.items.reduce(0.0) { a, it in a + (foods.first { $0.key == it.key }?.macros(it.grams).carbs ?? 0) } ?? 0
                    return (i, k, kind, carbs) } }
                return nil
            }
            guard let (i, k, kind, _) = cands.max(by: { $0.3 < $1.3 }) else { return false }
            slots[i].items.removeAll { $0.key == k }
            if var st = structure[slots[i].index] {
                st.dropped.append(kind.label.lowercased())
                if let j = st.fill.lastIndex(where: { $0.kind == kind && $0.keys.contains(k) }) { st.fill[j].keys.removeAll { $0 == k } }
                structure[slots[i].index] = st
            }
            return true
        }
        // A carb base squeezed under half your usual portion: drop the bread side or spread instead.
        let squeezed = best.slots.contains { sl in !sl.fixed && sl.items.contains { it in
            guard let f = foods.first(where: { $0.key == it.key }), f.role == .carbSide, structure[sl.index]?.fill.first(where: { $0.kind == .carbBase })?.keys.contains(it.key) == true else { return false }
            return it.grams < f.usualGrams * 0.5 } }
        if squeezed, dropBreadOrSpread() {
            let r = Planner.plan(targets, slots: slots, foods: foods, options: o)
            if severity(r, targets) <= severity(best, targets) + 2 { best = r; bestStructure = structure }
        }
        while !best.feasible && tries < 8 {
            tries += 1
            let over = best.totals.kcal > targets.kcal + max(40, targets.kcal * options.kcalTolerance)
            var changed = false
            if over {
                for kind in dropOrder {
                    guard let (idx, key) = slots.indices.lazy.compactMap({ i -> (Int, String)? in
                        guard !slots[i].fixed, slots[i].kind != .preWorkout, slots[i].kind != .postWorkout,
                              let st = structure[slots[i].index], let f = st.fill.last(where: { $0.kind == kind && !$0.required && !$0.keys.isEmpty }) else { return nil }
                        // Oil stays while fat is at or under its floor.
                        if kind == .fatOrSauce, best.totals.fat <= targets.fatFloor + 3, f.keys.allSatisfy({ k in foods.first { $0.key == k }?.role == .fatSource }) { return nil }
                        return (i, f.keys.last!)
                    }).first else { continue }
                    slots[idx].items.removeAll { $0.key == key }
                    if var st = structure[slots[idx].index] {
                        st.dropped.append(kind.label.lowercased())
                        if let j = st.fill.lastIndex(where: { $0.kind == kind && $0.keys.contains(key) }) { st.fill[j].keys.removeAll { $0 == key } }
                        structure[slots[idx].index] = st
                    }
                    changed = true; break
                }
            } else {
                // Short of the fat floor: olive oil (or another fat) on lunch, dinner or the meal after training.
                // Short of fibre or calories: pulses as a side.
                let wantFat = best.misses.contains("fat floor"), wantFibre = best.misses.contains("fibre") || best.totals.kcal < targets.kcal - max(40, targets.kcal * options.kcalTolerance)
                for (kind, canon) in [(TemplateSlot.Kind.fatOrSauce, wantFat ? "olive-oil" : ""), (.pulses, wantFibre ? "pulses" : "")] where !canon.isEmpty && !changed {
                    guard let i = slots.indices.first(where: { i in !slots[i].fixed && slots[i].kind != .preWorkout
                                && MealTemplates.template(for: slots[i], in: templates)?.slots.contains { $0.kind == kind && $0.allowed.contains(canon) } == true
                                && !slots[i].items.contains { it in foods.first { $0.key == it.key }?.canonical == canon } }),
                          let add = foods.filter({ $0.canonical == canon && basicOK($0) }).sorted(by: { ($0.basic ? 1 : 0, $0.key) < ($1.basic ? 1 : 0, $1.key) }).first else { continue }
                    slots[i].items.append(PlanItem(key: add.key, grams: add.usualGrams))
                    if var st = structure[slots[i].index] { st.fill.append(.init(kind: kind, keys: [add.key], required: false)); st.dropped.removeAll { $0 == kind.label.lowercased() }; structure[slots[i].index] = st }
                    if kind == .fatOrSauce { _ = dropBreadOrSpread() }      // oil needs room in the calories
                    changed = true
                }
            }
            guard changed else { break }
            let r = Planner.plan(targets, slots: slots, foods: foods, options: o)
            if r.feasible || severity(r, targets) < severity(best, targets) { best = r; bestStructure = structure }
        }
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
