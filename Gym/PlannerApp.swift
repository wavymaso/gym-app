import SwiftData
import SwiftUI

// The meal planner in the app: your settings (synced), your foods as candidates, today's plan with
// what you've eaten fixed, and the week ahead.

extension ModelContext {
    /// Where the planner's foods come from right now.
    enum PlanSource { case history, staples, recent }
    var planSource: PlanSource {
        if eatingProfile().enoughData { return .history }
        return (profile?.planner.staples.isEmpty ?? true) ? .recent : .staples
    }

    /// Your foods as planner candidates: from the eating profile when there's enough logging, else your
    /// staples, else your recent and favourite foods (at the meal you last had them).
    /// Roles from the taxonomy (your corrections included), with the meals a canonical food belongs
    /// in (oats and protein bars: breakfast and merienda). Drinks aren't planned.
    func planFoods() -> [PlanFood] {
        let own = planFoodsGuessed().compactMap { f -> PlanFood? in
            guard let food = food(key: f.key) else { return f }
            let t = taxonomy(of: food)
            guard t.role != .drink else { return nil }
            var g = t.role == f.role ? f : f.with(role: t.role)
            g.bands.formUnion(Taxonomy.bands(t.canonical))
            g.nova = t.nova
            return g
        }
        // The basic foods library, always there to fill a role (those you've logged are your own foods now).
        let basics = BasicFoods.planFoods(excluding: Set(own.map(\.key)))
        let weigh = profile?.planner.weighAs ?? [:]
        return (own + basics).map { f in
            var f = f
            let food = food(key: f.key)
            let b = BasicFoods.byKey[f.key]
            guard let data = food?.state ?? b?.state, let ratio = food?.ratio?.value ?? b?.ratio, abs(ratio - 1) > 0.01 else { return f }
            let mine = weigh[f.key] ?? Self.defaultWeighing(data)
            if mine != data { f.shownRatio = mine == .cooked ? ratio : 1 / ratio; f.shownUnit = mine == .cooked ? Cooking.cookedUnit : Cooking.rawUnit }
            return f
        }
    }

    /// You weigh food raw, unless it's sold cooked (its values are per cooked weight).
    static func defaultWeighing(_ data: WeightState) -> WeightState { data == .cooked ? .cooked : .raw }

    /// A basic library food as one of your foods (made the first time you log it).
    func materializeBasic(_ key: String) -> Food? {
        if let f = food(key: key) { return f }
        guard let b = BasicFoods.byKey[key] else { return nil }
        let v = b.values
        let f = Food(key: key, name: b.name, source: "basic", per100: Nutrients(kcal: v.kcal, protein: v.protein, fat: v.fat, carbs: v.carbs, fiber: v.fibre),
                     servings: b.unit.map { [Serving(name: $0.name, grams: $0.grams)] } ?? [], isLiquid: b.liquid)
        f.weightState = b.state.rawValue; f.cookedRatio = b.ratio ?? 0; f.nova = b.nova; f.foodGroup = "-"
        insert(f)
        return f
    }

    /// Before the taxonomy (name and macro rules only).
    func planFoodsGuessed() -> [PlanFood] {
        let foods = ((try? fetch(FetchDescriptor<Food>())) ?? [])
        func unit(_ f: Food) -> Double? { f.servings.first.flatMap { $0.name.hasPrefix("1 ") && $0.grams <= 150 && $0.grams > 0 ? $0.grams : nil } }
        let catalog = Dictionary(foods.map { f in (f.key, (name: f.name, per100: (f.per100.kcal, f.per100.protein, f.per100.fat, f.per100.carbs, f.per100.fiber ?? 0), unitGrams: unit(f))) },
                                 uniquingKeysWith: { a, _ in a })
        let profile = eatingProfile()
        if profile.enoughData { return Planner.foods(from: profile, catalog: catalog) }
        if let st = self.profile?.planner.staples, !st.isEmpty { return Planner.foods(fromStaples: st, catalog: catalog) }
        return foods.filter { $0.useCount > 0 || $0.isFavorite }.sorted { $0.key < $1.key }.map { f in
            let g = f.lastAmount.map { f.grams($0, unit: f.lastUnit ?? f.baseUnit) } ?? f.servings.first?.grams ?? 100
            let kcal100 = f.per100.kcal
            let role = FoodRole.guess(name: f.name, kcal: kcal100, protein: f.per100.protein, fat: f.per100.fat, carbs: f.per100.carbs)
            var bands = MealBand.guess(name: f.name)
            if let d = f.lastUsed { bands.insert(MealBand.of(minute: Calendar.current.component(.hour, from: d) * 60 + Calendar.current.component(.minute, from: d))) }
            let step = unit(f) ?? (kcal100 > 500 ? 5 : 10)
            return PlanFood(key: f.key, name: f.name, per100: (kcal100, f.per100.protein, f.per100.fat, f.per100.carbs, f.per100.fiber ?? 0),
                            step: step, usualGrams: max(g, step), usualSlots: [:], frequency: Double(f.useCount) + (f.isFavorite ? 3 : 0), bands: bands)
                .with(role: role, usual: max(g, step))
        }
    }

    /// Keep the stored inferred week current (targets read it). Call after workouts change.
    func refreshTrainingWeek() {
        guard let p = profile else { return }
        let w = inferredSchedule()
        guard p.planner.inferredWeek != w else { return }
        var s = p.planner; s.inferredWeek = w; p.planner = s; commit()
    }

    /// Your usual training week from the last 6 weeks: workouts logged here plus Apple Health.
    func inferredSchedule() -> [Int: TrainingSlot] {
        let from = Calendar.current.date(byAdding: .day, value: -43, to: Date())!
        let ws = (try? fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.start >= from }))) ?? []
        let cal = Calendar.current
        var sessions = ws.compactMap { w -> ScheduleInference.Session? in
            guard let end = w.end else { return nil }
            return .init(day: w.day, start: cal.component(.hour, from: w.start) * 60 + cal.component(.minute, from: w.start), minutes: Int(end.timeIntervalSince(w.start) / 60))
        }
        let own = Set(sessions.map(\.day))
        for (d, t) in profile?.planner.healthSessions ?? [:] where !own.contains(d) { sessions.append(.init(day: d, start: t.start, minutes: t.minutes)) }
        return ScheduleInference.infer(sessions, today: dayKey())
    }

    /// The plan for a day: today's (or that day's) targets, meal times around training, what's
    /// already eaten fixed, your locked meals kept.
    /// `uses`: how often each food was planned on the days before (the week view), so a week has some variety.
    func dayPlan(_ day: String, uses: [String: Int] = [:]) -> (plan: DayPlan, foods: [String: PlanFood], settings: PlannerSettings)? {
        guard let p = profile, let t = dayTargets(on: day) else { return nil }
        let s = p.planner
        var foods = planFoods().map { f in var f = f; f.uses7 = uses[f.key] ?? 0; return f }
        let wd = Calendar(identifier: .gregorian).component(.weekday, from: date(fromKey: day))
        let fasting = p.fastDaySet.contains(wd)
        let training = fasting ? nil : s.training(on: day, inferred: inferredSchedule())
        let fasted = s.fastedMorning && (training.map { $0.start < s.wake + 90 } ?? false)
        var slots = Planner.slots(wake: s.wake, sleep: s.sleep, meals: fasting ? 2 : s.meals, training: training.map { ($0.start, $0.minutes) },
                                  fasted: fasted, preSleep: s.preSleepProtein, eatingWindow: ramadanActive ? (s.iftar, s.suhoor) : nil)
        // What you've eaten: each entry to the nearest slot (by time), which becomes fixed. A meal that
        // looks too big and isn't confirmed yet stays fixed but isn't counted.
        let cal = Calendar.current
        let unconfirmed = Set(largeFlags(on: day).flatMap(\.ids))
        for e in entries(on: day) {
            var m = cal.component(.hour, from: e.time) * 60 + cal.component(.minute, from: e.time)
            if ramadanActive, m < 5 * 60 { m += 24 * 60 }
            guard let i = slots.indices.min(by: { abs(slots[$0].minute - m) < abs(slots[$1].minute - m) }) else { continue }
            let key: String
            if let k = e.foodKey, foods.contains(where: { $0.key == k }) { key = k } else {
                key = "entry:\(e.syncID)"
                let g = max(e.grams, 1)
                foods.append(PlanFood(key: key, name: e.name, per100: (e.nutrients.kcal / g * 100, e.nutrients.protein / g * 100, e.nutrients.fat / g * 100,
                                                                         e.nutrients.carbs / g * 100, (e.nutrients.fiber ?? 0) / g * 100), usualGrams: g))
            }
            slots[i].items.append(PlanItem(key: key, grams: max(e.grams, 1))); slots[i].eaten = true
            if unconfirmed.contains(e.syncID) { slots[i].provisional = true }
        }
        for i in slots.indices where !slots[i].eaten { if let l = s.locks[i], !l.isEmpty { slots[i].items = l; slots[i].locked = true } }
        let kg = trendSeries(weightValues, through: day).last?.trend ?? 80
        let fibreGoal = p.planner.fibreFloor(kcal: t.kcal, custom: p.customGoals["fiber"])
        let targets = PlanTargets(kcal: t.kcal, protein: t.protein, fat: t.fat, carbs: t.carbs, fibreFloor: fibreGoal,
                                  fatFloor: min(t.fat, max(40, Evidence.value("fat.min.gPerKg") * kg)), weightKg: kg)
        let plan = Planner.plan(targets, slots: slots, foods: foods, options: PlanOptions(preSleepProtein: s.preSleepProtein, exclusions: Set(s.exclusions), variety: s.variety, trainingCarbBoost: s.trainingCarbBoost))
        return (plan, Dictionary(foods.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a }), s)
    }

    /// The first plan of each day, kept so the check-in can compare planned with eaten (context only).
    func recordPlan(_ day: String, _ plan: DayPlan) {
        guard day == dayKey() else { return }
        var log = UserDefaults.standard.dictionary(forKey: "planLog") as? [String: [Double]] ?? [:]
        if log[day] == nil { log[day] = [plan.totals.kcal, plan.totals.protein] }
        log = log.filter { $0.key >= addDays(dayKey(), -30) }
        UserDefaults.standard.set(log, forKey: "planLog")
    }

    /// Last 7 days: how many planned days you ate within 10% of the plan's calories with its protein.
    func planAdherence() -> (followed: Int, planned: Int)? {
        let log = UserDefaults.standard.dictionary(forKey: "planLog") as? [String: [Double]] ?? [:]
        let intake = dailyIntake()
        let days = (1...7).map { addDays(dayKey(), -$0) }.filter { log[$0] != nil && intake[$0] != nil }
        guard !days.isEmpty else { return nil }
        let followed = days.filter { d in
            let p = log[d]!, eaten = entries(on: d).reduce(0) { $0 + $1.nutrients.protein }
            return abs(intake[d]! - p[0]) <= p[0] * 0.1 && eaten >= p[1] * 0.9
        }.count
        return (followed, days.count)
    }

    /// The engine's training flag on training days becomes a proposal: more carbs before training.
    var carbProposal: Bool {
        guard let p = profile, !p.planner.trainingCarbBoost, !p.planner.schedule.isEmpty,
              p.planner.dismissedCarbProposal.isEmpty || p.planner.dismissedCarbProposal < addDays(dayKey(), -14) else { return false }
        let rec = ((try? fetch(FetchDescriptor<DecisionRecord>(sortBy: [SortDescriptor(\.day, order: .reverse)]))) ?? []).first?.record
        return rec?.reasons.contains { $0.rule == "strength drop on a fast cut" } ?? false
    }

    /// Log a planned meal as eaten, at its time.
    func eat(_ slot: PlanSlot, foods: [String: PlanFood], day: String) {
        let base = date(fromKey: day)
        let time = Calendar.current.date(byAdding: .minute, value: slot.minute, to: base) ?? Date()
        let shown = Dictionary(planFoods().map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for it in slot.items where !it.key.hasPrefix("entry:") {
            guard let f = food(key: it.key) ?? materializeBasic(it.key) else { continue }
            // Logged as you weigh it (e.g. 210 g cooked), so the entry reads the way you measured.
            if let p = shown[it.key], p.shownUnit != "g", f.units.contains(p.shownUnit) {
                _ = log(f, amount: (it.grams * p.shownRatio).rounded(), unit: p.shownUnit, day: day, time: time)
            } else {
                _ = log(f, amount: it.grams.rounded(), unit: f.baseUnit, day: day, time: time)
            }
        }
        commit()
    }
}

/// Aisles for the grocery list (by name, Spanish and English).
enum Aisle: String, CaseIterable {
    case produce = "Fruit & veg", meatFish = "Meat & fish", dairy = "Dairy & eggs", bakery = "Bread & bakery", pantry = "Pantry", snacks = "Snacks & sweets", drinks = "Drinks", other = "Other"
    static func of(_ name: String) -> Aisle {
        let n = name.lowercased()
        func any(_ w: [String]) -> Bool { w.contains { n.contains($0) } }
        if any(["banana", "plátano", "platano", "apple", "manzana", "broccoli", "brócoli", "espinaca", "spinach", "potato", "patata", "tomate", "tomato", "lettuce", "lechuga", "onion", "cebolla", "pepper", "pimiento", "carrot", "zanahoria", "berries", "fresa", "orange", "naranja", "date", "dátil", "avocado", "aguacate", "fruit", "fruta", "veg"]) { return .produce }
        if any(["chicken", "pollo", "beef", "ternera", "mince", "salmon", "salmón", "tuna", "atún", "turkey", "pavo", "pork", "cerdo", "fish", "pescado", "merluza", "gambas", "prawn", "lamb", "cordero", "ham", "jamón"]) { return .meatFish }
        if any(["yogur", "yogurt", "milk", "leche", "queso", "cheese", "egg", "huevo", "cottage", "skyr", "kefir", "cream", "nata", "butter", "mantequilla"]) && !any(["peanut", "cacahuete"]) { return .dairy }
        if any(["bread", "pan ", "pan,", "sourdough", "tortitas", "wrap", "bagel", "baguette", "bollo"]) { return .bakery }
        if any(["chocolate", "galleta", "cookie", "palomitas", "popcorn", "pepero", "barebells", "bar", "chips", "patatas fritas", "candy", "gominola", "dulce", "biscuit"]) { return .snacks }
        if any(["water", "agua", "coke", "cola", "juice", "zumo", "coffee", "café", "tea", "té", "drink", "bebida", "beer", "cerveza"]) { return .drinks }
        if any(["rice", "arroz", "pasta", "oats", "avena", "oil", "aceite", "peanut", "cacahuete", "whey", "protein", "proteína", "flour", "harina", "lentil", "lenteja", "beans", "judía", "garbanzo", "chickpea", "sauce", "salsa", "mermelada", "jam", "honey", "miel", "tortellini", "noodle"]) { return .pantry }
        return .other
    }
}
