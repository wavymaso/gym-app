import SwiftData
import SwiftUI

// The meal planner in the app: your settings (synced), your foods as candidates, today's plan with
// what you've eaten fixed, and the week ahead.

struct TrainingSlot: Codable, Equatable { var start: Int; var minutes: Int }

struct PlannerSettings: Codable, Equatable {
    var meals = 4
    var wake = 7 * 60
    var sleep = 23 * 60
    var schedule: [Int: TrainingSlot] = [:]          // weekday → session
    var overrides: [String: TrainingSlot] = [:]      // day → session (start < 0 = rest)
    var fastedMorning = false
    var preSleepProtein = false
    var exclusions: [String] = []                    // food keys
    var variety = 0.5
    var locks: [Int: [PlanItem]] = [:]               // slot → the meal you always want there
    var iftar = 19 * 60 + 30, suhoor = 28 * 60 + 30  // Ramadan window (suhoor after midnight)
    var trainingCarbBoost = false                    // accepted from the engine's proposal
    var dismissedCarbProposal = ""                   // day you said no (asked again after 2 weeks)

    func training(on day: String) -> TrainingSlot? {
        if let o = overrides[day] { return o.start < 0 ? nil : o }
        return schedule[Calendar(identifier: .gregorian).component(.weekday, from: date(fromKey: day))]
    }
}


extension Profile {
    var planner: PlannerSettings {
        get { (try? JSONDecoder().decode(PlannerSettings.self, from: Data(plannerJSON.utf8))) ?? PlannerSettings() }
        set { plannerJSON = String(decoding: (try? JSONEncoder().encode(newValue)) ?? Data(), as: UTF8.self) }
    }
}

extension ModelContext {
    /// Your foods as planner candidates: from the eating profile when there's enough logging, otherwise
    /// from your recent and favourite foods (placed by the time of day you last had them).
    func planFoods() -> [PlanFood] {
        let foods = ((try? fetch(FetchDescriptor<Food>(predicate: #Predicate { $0.useCount > 0 || $0.isFavorite }))) ?? [])
        func unit(_ f: Food) -> Double? { f.servings.first.flatMap { $0.name.hasPrefix("1 ") && $0.grams <= 150 && $0.grams > 0 ? $0.grams : nil } }
        let profile = eatingProfile()
        if profile.enoughData {
            let catalog = Dictionary(foods.map { f in (f.key, (name: f.name, per100: (f.per100.kcal, f.per100.protein, f.per100.fat, f.per100.carbs, f.per100.fiber ?? 0), unitGrams: unit(f))) },
                                     uniquingKeysWith: { a, _ in a })
            return Planner.foods(from: profile, catalog: catalog)
        }
        let n = max(1, (profile.mealsPerDay > 0 ? profile.mealsPerDay : 4))
        return foods.sorted { $0.key < $1.key }.map { f in
            let slot: Int = f.lastUsed.map { d in
                let m = Calendar.current.component(.hour, from: d) * 60 + Calendar.current.component(.minute, from: d)
                return min(n - 1, max(0, Int(Double(m - 7 * 60) / (16.0 * 60) * Double(n))))
            } ?? 0
            let g = f.lastAmount.map { f.grams($0, unit: f.lastUnit ?? f.baseUnit) } ?? f.servings.first?.grams ?? 100
            let kcal100 = f.per100.kcal
            return PlanFood(key: f.key, name: f.name, per100: (kcal100, f.per100.protein, f.per100.fat, f.per100.carbs, f.per100.fiber ?? 0),
                            step: unit(f) ?? (kcal100 > 500 ? 5 : 10), usualGrams: max(g, 10),
                            maxGrams: max(10, min(g * 2.5, kcal100 > 500 ? 60 : 600)),
                            usualSlots: [slot: Double(f.useCount) + (f.isFavorite ? 3 : 0)], frequency: Double(f.useCount))
        }
    }

    /// The plan for a day: today's (or that day's) targets, meal times around training, what's
    /// already eaten fixed, your locked meals kept.
    func dayPlan(_ day: String) -> (plan: DayPlan, foods: [String: PlanFood], settings: PlannerSettings)? {
        guard let p = profile, let t = dayTargets(on: day) else { return nil }
        let s = p.planner
        var foods = planFoods()
        let wd = Calendar(identifier: .gregorian).component(.weekday, from: date(fromKey: day))
        let fasting = p.fastDaySet.contains(wd)
        let training = fasting ? nil : s.training(on: day)
        let fasted = s.fastedMorning && (training.map { $0.start < s.wake + 90 } ?? false)
        var slots = Planner.slots(wake: s.wake, sleep: s.sleep, meals: fasting ? 2 : s.meals, training: training.map { ($0.start, $0.minutes) },
                                  fasted: fasted, preSleep: s.preSleepProtein, eatingWindow: ramadanActive ? (s.iftar, s.suhoor) : nil)
        // What you've eaten: each entry to the nearest slot (by time), which becomes fixed.
        let cal = Calendar.current
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
        }
        for i in slots.indices where !slots[i].eaten { if let l = s.locks[i], !l.isEmpty { slots[i].items = l; slots[i].locked = true } }
        let kg = trendSeries(weightValues, through: day).last?.trend ?? 80
        let fibreGoal = p.customGoals["fiber"] ?? Evidence.value("fibre.per1000kcal") * t.kcal / 1000 * 0.7
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
        for it in slot.items where !it.key.hasPrefix("entry:") {
            if let f = food(key: it.key) { _ = log(f, amount: it.grams.rounded(), unit: f.baseUnit, day: day, time: time) }
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
