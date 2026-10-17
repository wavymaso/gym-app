import SwiftData
import SwiftUI

// The meal planner in the app: your settings (synced), your foods as candidates, today's plan with
// what you've eaten fixed, and the week ahead.

/// The planner's inputs for the current data (rebuilt when saved data changes or the day turns).
private var planFoodsCache: (key: String, foods: [PlanFood])?
private var warmPlans: [String: (settings: String, plan: DayPlan)] = [:]
private var weekCache: (key: String, days: [(day: String, plan: DayPlan, foods: [String: PlanFood])])?

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
        let key = "\(ObjectIdentifier(container).hashValue)|\(dataVersion)|\(dayKey())"
        if let hit = planFoodsCache, hit.key == key { return hit.foods }
        let v = planFoodsUncached()
        planFoodsCache = (key, v)
        return v
    }

    private func planFoodsUncached() -> [PlanFood] {
        let own = planFoodsGuessed().compactMap { f -> PlanFood? in
            guard let food = food(key: f.key) else { return f }
            let t = taxonomy(of: food)
            guard t.role != .drink else { return nil }
            var g = t.role == f.role ? f : f.with(role: t.role)
            g.bands.formUnion(Taxonomy.bands(t.canonical))
            g.nova = t.nova; g.canonical = t.canonical; g.tier = t.canonical.map(Taxonomy.tier) ?? (t.role == .treat ? 3 : 2)
            return g
        }
        // Staples: your portion and meal, strongly preferred, and they stand for their canonical food
        // (Roosterz chicken as a staple is your chicken: the library's chicken steps aside, other chickens rank lower).
        let st = profile?.planner.staples ?? []
        var mine = own
        let catalog = planCatalog()
        for s in st {
            if let i = mine.firstIndex(where: { $0.key == s.key }) {
                var f = mine[i].with(role: mine[i].role, usual: s.grams)
                f.bands.insert(s.band); f.frequency += 20; f.staple = true; f.stapleBand = s.band
                mine[i] = f
            } else if var f = Planner.foods(fromStaples: [s], catalog: catalog).first, let food = food(key: s.key) {
                let t = taxonomy(of: food)
                guard t.role != .drink else { continue }
                f = f.with(role: t.role, usual: s.grams); f.bands.formUnion(Taxonomy.bands(t.canonical)); f.nova = t.nova; f.frequency = 20; f.staple = true; f.stapleBand = s.band
                mine.append(f)
            }
        }
        let stapleCanon = Set(st.compactMap { s in food(key: s.key).flatMap { taxonomy(of: $0).canonical } })
        for i in mine.indices where !mine[i].staple {
            if let f = food(key: mine[i].key), let c = taxonomy(of: f).canonical, stapleCanon.contains(c) { mine[i].frequency *= 0.3 }
        }
        // The basic foods library, always there to fill a role (those you've logged are your own foods now).
        let basics = BasicFoods.planFoods(excluding: Set(mine.map(\.key))).filter { b in !(BasicFoods.byKey[b.key]?.canonical.map(stapleCanon.contains) ?? false) }
        // The simple foods catalogue fills canonical foods neither yours nor the library cover.
        let covered = Set((mine + basics).compactMap(\.canonical))
        let removed = Set(profile?.planner.catalogRemoved ?? [])
        let simple = SimpleFoods.bundled.filter { $0.tier <= 2 && $0.availableAtMyStores && !covered.contains($0.id) && !removed.contains($0.id) && $0.role != .drink }.map { sf -> PlanFood in
            let v = sf.values
            let portion = sf.serving ?? (sf.role.isAccompaniment ? 15 : sf.role == .vegetable ? 150 : 100)
            var f = PlanFood(key: "simple:\(sf.id)", name: sf.name, per100: (v.kcal, v.protein, v.fat, v.carbs, v.fibre), step: v.kcal > 500 ? 5 : 10, usualGrams: portion,
                             usualSlots: [:], frequency: 0, bands: Taxonomy.bands(sf.id)).with(role: sf.role, usual: portion)
            f.canonical = sf.id; f.tier = sf.tier; f.nova = Taxonomy.byID[sf.id]?.nova ?? 3; f.basic = true; f.basicAllowed = (Taxonomy.byID[sf.id]?.nova ?? 3) <= 2
            return f
        }
        let weigh = profile?.planner.weighAs ?? [:]
        return (mine + basics + simple).map { f in
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
        if key.hasPrefix("simple:"), let sf = SimpleFoods.bundled.first(where: { "simple:\($0.id)" == key }) {
            let v = sf.values
            let f = Food(key: key, name: sf.name, source: "basic", per100: Nutrients(kcal: v.kcal, protein: v.protein, fat: v.fat, carbs: v.carbs, fiber: v.fibre))
            f.foodGroup = "-"; f.nova = Taxonomy.byID[sf.id]?.nova ?? 0
            f.override = Taxonomy.Override(canonical: sf.id, role: sf.role, nova: nil)
            insert(f)
            return f
        }
        guard let b = BasicFoods.byKey[key] else { return nil }
        let v = b.values
        let f = Food(key: key, name: b.name, source: "basic", per100: Nutrients(kcal: v.kcal, protein: v.protein, fat: v.fat, carbs: v.carbs, fiber: v.fibre),
                     servings: b.unit.map { [Serving(name: $0.name, grams: $0.grams)] } ?? [], isLiquid: b.liquid)
        f.weightState = b.state.rawValue; f.cookedRatio = b.ratio ?? 0; f.nova = b.nova; f.foodGroup = "-"
        insert(f)
        return f
    }

    /// A food's unit, when it comes in pieces (an egg, a bar, a slice, a scoop, a tin, a rice cake): the
    /// planner's portion step. A "1 serving (100 g)" isn't a piece.
    static func unitGrams(_ f: Food) -> Double? {
        guard let s = f.servings.first, s.grams > 0, s.name.hasPrefix("1 ") else { return nil }
        let n = s.name.lowercased()
        let piece = ["egg", "huevo", "bar", "barrita", "slice", "rebanada", "loncha", "scoop", "cacito", "tin", "lata", "tortita", "rice cake", "unidad", "unit", "piece", "pieza", "pot", "tarrina", "yogur", "pack"]
        return piece.contains(where: { n.contains($0) }) || s.grams <= 25 ? s.grams : nil      // a 50 g "serving" of dates isn't a piece
    }

    /// Your foods' names and values for the planner.
    func planCatalog() -> [String: (name: String, per100: (Double, Double, Double, Double, Double), unitGrams: Double?)] {
        let foods = (try? fetch(FetchDescriptor<Food>())) ?? []
        func unit(_ f: Food) -> Double? { ModelContext.unitGrams(f) }
        return Dictionary(foods.map { f in (f.key, (name: f.name, per100: (f.per100.kcal, f.per100.protein, f.per100.fat, f.per100.carbs, f.per100.fiber ?? 0), unitGrams: unit(f))) },
                          uniquingKeysWith: { a, _ in a })
    }

    /// Staple suggestions from your log (frequency), not yet staples or dismissed.
    func stapleSuggestions() -> [StapleSuggestions.Suggestion] {
        guard let s = profile?.planner else { return [] }
        return StapleSuggestions.suggest(loggedFoods(days: max(s.stapleWindowDays, 28) + 1), today: dayKey(), window: s.stapleWindowDays, minDays: s.stapleMinDays,
                                         staples: Set(s.staples.map(\.key)), dismissed: Set(s.dismissedStaples))
    }

    /// Before the taxonomy (name and macro rules only).
    func planFoodsGuessed() -> [PlanFood] {
        let foods = ((try? fetch(FetchDescriptor<Food>())) ?? [])
        func unit(_ f: Food) -> Double? { ModelContext.unitGrams(f) }
        let catalog = Dictionary(foods.map { f in (f.key, (name: f.name, per100: (f.per100.kcal, f.per100.protein, f.per100.fat, f.per100.carbs, f.per100.fiber ?? 0), unitGrams: unit(f))) },
                                 uniquingKeysWith: { a, _ in a })
        let profile = eatingProfile()
        if profile.enoughData { return Planner.foods(from: profile, catalog: catalog) }
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

    /// You asked (17 Oct): once staples are picked, the fibre floor goes from a fixed 19 g to 14 g per 1,000 kcal. Once.
    func applyFibreSwitch() {
        guard !UserDefaults.standard.bool(forKey: "fibreSwitch1"), let p = profile, p.planner.staples.count >= 10 else { return }
        var s = p.planner
        if s.fibreFloorGrams == 19 { s.fibreFloorGrams = 0; p.planner = s; commit() }
        UserDefaults.standard.set(true, forKey: "fibreSwitch1")
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

    typealias PlanResult = (plan: DayPlan, foods: [String: PlanFood], settings: PlannerSettings)

    /// Everything the planner needs for one day, gathered from your data (main thread); `run()` then plans
    /// it anywhere (the week view runs it in the background).
    struct PlanJob {
        var targets: PlanTargets, slots: [PlanSlot], foods: [PlanFood], templates: [MealTemplate], ctx: BuildContext, options: PlanOptions
        var previous: [Int: (items: [PlanItem], structure: MealStructure)] = [:]
        var only: Set<Int>? = nil
        var extraReasons: [EngineReason], carbs: DayPlan.Carbs, settings: PlannerSettings
        func run() -> PlanResult {
            let built = MealBuilder.plan(targets, slots: slots, foods: foods, templates: templates, ctx: ctx, options: options, previous: previous, only: only)
            var plan = built.plan
            plan.structure = built.structure
            plan.reasons += extraReasons
            plan.carbs = carbs
            return (plan, Dictionary(foods.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a }), settings)
        }
    }

    /// The plan for a day: today's (or that day's) targets, meal times around training, what's
    /// already eaten fixed, your locked meals kept.
    /// `uses`: how often each food was planned on the days before (the week view), so a week has some variety.
    /// The day's last plan is kept (in memory): after you log a meal or change one, the rest of the day
    /// starts from it and is only resized (a warm start), instead of being chosen again from scratch.
    func dayPlan(_ day: String, uses: [String: Int] = [:], style: String? = nil, offset: Int = 0, only: Set<Int>? = nil) -> PlanResult? {
        guard var job = planJob(day, uses: uses, style: style, offset: offset) else { return nil }
        let warmKey = "\(day)|\(style ?? "")|\(offset)"
        let sig = profile?.plannerJSON ?? ""
        if uses.isEmpty, let prev = warmPlans[warmKey], prev.settings == sig, prev.plan.slots.map(\.minute) == job.slots.map(\.minute) {
            for s in prev.plan.slots where !s.fixed {
                guard let st = prev.plan.structure[s.index], let now = job.slots.first(where: { $0.index == s.index }), !now.fixed else { continue }
                job.previous[s.index] = (s.items, st)
            }
            job.only = only
        }
        let r = job.run()
        if uses.isEmpty { warmPlans[warmKey] = (sig, r.plan); if warmPlans.count > 30 { warmPlans = [warmKey: (sig, r.plan)] } }
        return r
    }

    /// Plan again from scratch (a regenerate, or settings changed): forget the day's last plan.
    func forgetPlan(_ day: String) { warmPlans = warmPlans.filter { !$0.key.hasPrefix(day + "|") } }

    /// The week ahead, planned in the background (each day's inputs gathered here, the planning off the
    /// main thread), cached until your data changes.
    @MainActor func weekPlans(from start: String) async -> [(day: String, plan: DayPlan, foods: [String: PlanFood])] {
        let key = "\(start)|\(dataVersion)|\(profile?.plannerJSON.hashValue ?? 0)"
        if let hit = weekCache, hit.key == key { return hit.days }
        var uses: [String: Int] = [:], out: [(day: String, plan: DayPlan, foods: [String: PlanFood])] = []
        for i in 0..<7 {
            let d = addDays(start, i)
            guard let job = planJob(d, uses: uses) else { continue }
            let r = await Task.detached(priority: .userInitiated) { job.run() }.value
            for s in r.plan.slots where !s.eaten { for it in s.items { uses[it.key, default: 0] += 1 } }
            out.append((d, r.plan, r.foods))
        }
        weekCache = (key, out)
        return out
    }

    func planJob(_ day: String, uses: [String: Int] = [:], style: String? = nil, offset: Int = 0) -> PlanJob? {
        let style = style ?? profile?.planner.style ?? "usual"
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
        var targets = PlanTargets(kcal: t.kcal, protein: t.protein, fat: t.fat, carbs: t.carbs, fibreFloor: fibreGoal,
                                  fatFloor: min(t.fat, max(40, Evidence.value("fat.min.gPerKg") * kg)), weightKg: kg)
        // Carbs per meal: around the session, the recovery window, your preferred carb meals.
        // What's left after eaten and locked meals is shared out (a locked breakfast's carbs are already spent).
        let fixedCarbs = slots.filter(\.fixed).flatMap(\.items).reduce(0.0) { acc, it in acc + (foods.first { $0.key == it.key }?.macros(it.grams).carbs ?? 0) }
        let carb = carbMeals(day, dayCarbs: max(0, t.carbs - fixedCarbs), slots: slots, kg: kg, session: training, fasted: fasted, settings: s)
        targets.mealCarbs = carb.perSlot
        let opts = PlanOptions(preSleepProtein: s.preSleepProtein, exclusions: Set(s.exclusions), variety: s.variety, trainingCarbBoost: s.trainingCarbBoost)
        // The three-stage planner: templates, then your foods into their slots, then portions.
        if s.treatsEnabled, !slots.contains(where: { $0.templateID == "evening-snack" }) {
            slots.append(PlanSlot(index: slots.count, minute: s.sleep - 60, kind: .meal, templateID: "evening-snack"))
        }
        var bctx = BuildContext()
        bctx.patterns = mealPatterns(); bctx.usualMeals = usualMeals(); bctx.variety = s.variety; bctx.inStock = Set(s.inStock)
        bctx.removed = Set(s.catalogRemoved); bctx.sameProteinTwice = s.sameProteinTwice; bctx.treats = s.treatsEnabled
        bctx.basicStyle = style == "basic"; bctx.offset = offset
        let canonOf = Dictionary(foods.compactMap { f in f.canonical.map { (f.key, $0) } }, uniquingKeysWith: { a, _ in a })
        for (k, n) in uses { if let c = canonOf[k] { bctx.recent[c, default: 0] += n; bctx.recent["family:" + Taxonomy.family(c), default: 0] += n } }
        if style == "anything" { bctx.wholeFood = 0.3 }
        return PlanJob(targets: targets, slots: slots, foods: foods, templates: s.mealTemplates, ctx: bctx, options: opts,
                       extraReasons: carbReasons(day, t: t, kg: kg, training: training) + carb.reasons,
                       carbs: .init(gPerKg: t.carbs / kg, range: CarbPlanner.range(phase).range, rangeIsTarget: CarbPlanner.range(phase).target, intra: carb.intra, recovery: carb.recovery),
                       settings: s)
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
        guard let p = profile, !p.planner.trainingCarbBoost, !p.planner.week(p.planner.inferredWeek).isEmpty,
              p.planner.dismissedCarbProposal.isEmpty || p.planner.dismissedCarbProposal < addDays(dayKey(), -14) else { return false }
        let rec = ((try? fetch(FetchDescriptor<DecisionRecord>(sortBy: [SortDescriptor(\.day, order: .reverse)]))) ?? []).first?.record
        return rec?.reasons.contains { $0.rule == "strength drop on a fast cut" } ?? false
    }

    var phase: Phase { activeProgram.map { $0.goalValue == .lose ? .cut : $0.goalValue == .gain ? .bulk : .maintain } ?? .maintain }

    /// The carb plan for a day's meals (CarbPlanner.meals) with the sessions before and after it.
    func carbMeals(_ day: String, dayCarbs: Double, slots: [PlanSlot], kg: Double, session: TrainingSlot?, fasted: Bool, settings s: PlannerSettings) -> MealCarbs {
        func sessionOn(_ d: String) -> TrainingSlot? {
            let wd = Calendar(identifier: .gregorian).component(.weekday, from: date(fromKey: d))
            return (profile?.fastDaySet.contains(wd) ?? false) ? nil : s.training(on: d, inferred: s.inferredWeek)
        }
        var toNext: Double?, sincePrev: Double?
        if let t = session {
            let end = t.start + t.minutes
            if let n = sessionOn(addDays(day, 1)) { toNext = Double(24 * 60 - end + n.start) / 60 }
            if let pv = sessionOn(addDays(day, -1)) { sincePrev = Double(24 * 60 - (pv.start + pv.minutes) + t.start) / 60 }
        }
        let size = session.map { sessionSize($0) }
        let factor = size.map { CarbPlanner.sessionFactor(sets: $0.sets, minutes: $0.minutes, averageSets: $0.averageSets, averageMinutes: $0.averageMinutes) } ?? 1
        // Where you like your carbs, from the templates: lunch and dinner most, merienda least; a lighter dinner on rest days.
        var pref: [Int: Double] = [:]
        for sl in slots {
            switch MealTemplates.template(for: sl, in: s.mealTemplates)?.meal {
            case .breakfast: pref[sl.index] = 0.9
            case .lunch: pref[sl.index] = 1.15
            case .merienda: pref[sl.index] = 0.7
            case .dinner: pref[sl.index] = session == nil ? 0.8 : 1.0
            default: pref[sl.index] = 1
            }
        }
        return CarbPlanner.meals(dayCarbs: dayCarbs, slots: slots, kg: kg, session: session.map { ($0.start, $0.minutes) }, factor: factor, hoursToNext: toNext,
                                 previousEndedHoursAgo: sincePrev, wake: s.wake, fasted: fasted, preference: pref, settings: s.carbs)
    }

    /// Why the day has these carbs: training or rest, the session's size, the range for your phase.
    func carbReasons(_ day: String, t: Targets, kg: Double, training: TrainingSlot?) -> [EngineReason] {
        let r = CarbPlanner.range(phase)
        var out: [EngineReason] = []
        let gkg = String(format: "%.1f", t.carbs / kg)
        if let tr = training {
            let size = sessionSize(tr)
            out.append(.init(rule: "training day", detail: "A training day: fat is lowered toward its floor and carbs raised (same calories), more for a bigger session (\(Int(size.sets)) sets, \(tr.minutes) min vs your average \(Int(size.averageSets)) sets).",
                             evidence: ["carbs.dayShift.share", "carbs.performance.nuance"]))
        } else {
            out.append(.init(rule: "rest day", detail: "A rest day: a little more fat and fewer carbs, so training days can have more (the week's calories are the same).", evidence: ["carbs.dayShift.share"]))
        }
        out.append(.init(rule: "carbs per kg", detail: r.target ? "\(gkg) g/kg of carbs; the range for your phase is \(Int(r.range.lowerBound))–\(Int(r.range.upperBound)) g/kg."
                         : "\(gkg) g/kg of carbs. On a cut that's normal: the reference range for strength athletes is 4–7 g/kg and 2–5 g/kg during dieting; your calories decide, carbs are what's left.",
                         evidence: [r.id, "carbs.physique.gPerKg"]))
        return out
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
