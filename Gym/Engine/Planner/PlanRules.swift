import Foundation

// The planner's realism rules and its inputs from your history: your usual training week, when foods
// belong (breakfast foods at breakfast), what a "main" is (oil and jam only go with one), your
// staples, and the check for entries big enough to be a typo.

struct TrainingSlot: Codable, Equatable {
    var start: Int
    var minutes: Int
    var routine: String? = nil        // the routine you do that day (its working sets size the day's carbs)
}

// MARK: Training week

enum ScheduleInference {
    struct Session: Equatable { var day: String; var start: Int; var minutes: Int }

    /// Your usual week from the last `weeks` weeks of workouts: a weekday counts when you trained on it
    /// in at least half of the weeks seen, at the median start time (to 15 min) and median length.
    /// No workouts → empty (every day a rest day).
    static func infer(_ sessions: [Session], today: String, weeks: Int = 6) -> [Int: TrainingSlot] {
        let from = addDaysKey(today, -weeks * 7)
        let recent = sessions.filter { $0.day >= from && $0.day < today && $0.minutes >= 15 }
        guard let first = recent.map({ $0.day }).min() else { return [:] }
        // Weeks actually covered: from the first workout in the window (at least 2, so one week isn't a habit).
        let seen = max(2, min(weeks, (daysBetweenKeys(first, today) + 6) / 7))
        var byDay: [String: Session] = [:]
        for s in recent where byDay[s.day].map({ s.start < $0.start }) ?? true { byDay[s.day] = s }
        let byWeekday = Dictionary(grouping: Array(byDay.values), by: { (s: Session) in weekdayOfKey(s.day) })
        func median(_ x: [Int]) -> Int {
            let s = x.sorted()
            return s.isEmpty ? 0 : s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
        }
        let length = min(180, max(30, median(byDay.values.map { $0.minutes })))
        var out: [Int: TrainingSlot] = [:]
        for (wd, s) in byWeekday where Double(s.count) >= Double(seen) / 2 {
            let start = Int((Double(median(s.map { $0.start })) / 15).rounded()) * 15
            out[wd] = TrainingSlot(start: start, minutes: length)
        }
        return out
    }
}

// MARK: When a food belongs, and what it is

enum MealBand: String, Codable, CaseIterable, Comparable {
    case breakfast, lunch, afternoon, dinner
    /// Spanish meal times: breakfast before 11:00, lunch to 16:30, merienda to 19:30, then dinner.
    static func of(minute: Int) -> MealBand {
        if minute >= 24 * 60 { return .dinner }
        if minute < 4 * 60 { return .dinner }
        if minute < 11 * 60 { return .breakfast }
        if minute < 16 * 60 + 30 { return .lunch }
        if minute < 19 * 60 + 30 { return .afternoon }
        return .dinner
    }
    var label: String { ["Breakfast", "Lunch", "Merienda", "Dinner"][MealBand.allCases.firstIndex(of: self)!] }
    static func < (a: MealBand, b: MealBand) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }

    /// Where a food belongs by its name, when your log doesn't say (empty: anywhere).
    static func guess(name: String) -> Set<MealBand> {
        let n = name.lowercased()
        let morning = ["oats", "avena", "cereal", "granola", "muesli", "yogur", "yogurt", "skyr", "tortitas", "mermelada", "jam", "croissant",
                       "tostada", "magdalena", "galleta", "cookie", "kefir", "corn flakes", "porridge"]
        let mains = ["chicken", "pollo", "arroz", "rice", "pasta", "macarrones", "rigate", "spaghetti", "espagueti", "tortellini", "salmon", "salmón",
                     "ternera", "beef", "carne", "mince", "patata", "potato", "merluza", "lentejas", "lentil", "garbanzo", "chickpea", "pizza",
                     "hamburguesa", "burger", "pavo", "turkey", "cerdo", "pork", "atún", "tuna", "gambas", "lasaña", "lasagna", "wings", "noodle"]
        if morning.contains(where: { n.contains($0) }) { return [.breakfast, .afternoon] }
        if mains.contains(where: { n.contains($0) }) { return [.lunch, .dinner] }
        return []
    }
}

extension FoodRole {
    /// The role rules give a food from its name and macros (no category data): the taxonomy's rules.
    static func guess(name: String, kcal: Double, protein: Double, fat: Double, carbs: Double) -> FoodRole {
        Taxonomy.classify(.init(name: name, brand: nil, source: "custom", kcal: kcal, protein: protein, fat: fat, carbs: carbs)).role
    }
}

// MARK: Staples (cold start)

/// What kind of condiment: limits per meal and per day.
enum CondimentKind {
    case oil, spread, sauce
    static func of(_ name: String, fat: Double) -> CondimentKind {
        let n = name.lowercased()
        if fat >= 80 || n.contains("aceite") || n.contains(" oil") || n.hasPrefix("oil") { return .oil }
        if ["mermelada", "jam", "miel", "honey", "crema de", "peanut butter", "mantequilla", "butter", "nutella", "sirope", "syrup", "cacahuete", "hummus", "nata", "cream cheese"]
            .contains(where: { n.contains($0) }) { return .spread }
        return .sauce
    }
    /// Most per meal (g): oil 15, honey 20, spreads 30, tomato sauces 100, other sauces 60.
    static func cap(_ name: String, fat: Double) -> Double {
        let n = name.lowercased()
        if ["almendra", "almond", "nuez", "walnut", "anacardo", "cashew", "pistacho", "avellana", "frutos secos", "nuts"].contains(where: { n.contains($0) }) && !n.contains("crema") && !n.contains("butter") { return 30 }
        if n.contains("aguacate") || n.contains("avocado") { return 100 }
        switch of(name, fat: fat) {
        case .oil: return 15
        case .spread: return n.contains("miel") || n.contains("honey") || n.contains("sirope") || n.contains("syrup") ? 20 : 30
        case .sauce: return n.contains("tomate") || n.contains("tomato") ? 100 : 60
        }
    }
    /// Meals a day it can appear in: oil twice (cooking), everything else once.
    static func perDay(_ name: String, fat: Double) -> Int { of(name, fat: fat) == .oil ? 2 : 1 }
}

/// Realistic portions around your usual one: half to about one and a half times it; condiments kept
/// to a serving (spreads 30 g, sauces 60 g, oil 15 g, never over 150 kcal), so last week's 500 g of
/// sauce doesn't become the plan's portion.
enum Portion {
    static func bounds(usual: Double, kcal100: Double, role: FoodRole, step: Double, name: String = "", fat: Double = 0, carbs100: Double = 0) -> (usual: Double, min: Double, max: Double) {
        var hi = usual * (role.isProteinSource && role != .proteinSnack ? 2.0 : 1.6)
        if role.isAccompaniment { hi = min(usual * 1.25, CondimentKind.cap(name, fat: fat), max(step, 15000 / max(kcal100, 1))) }
        // A treat stays at your portion; a protein snack too when it comes in units (a bar), but a powder can scale.
        if role == .treat || (role == .proteinSnack && step >= usual) { hi = min(hi, usual) }
        let st = role.isAccompaniment ? min(step, 5) : step
        hi = max(st, (hi / st).rounded(.down) * st)
        let u = min(usual, hi)
        // Carb sides can shrink further (75 g of dry pasta is a normal portion when your usual is 250 g).
        var lo = min(u, max(st, (u * (role == .carbSide ? 0.3 : 0.5) / st).rounded() * st))
        // …but a carb base is still a carb base: at least about 25 g of carbs.
        if role == .carbSide, carbs100 > 0 { lo = min(u, max(lo, (2500 / carbs100 / st).rounded(.up) * st)) }
        return (u, lo, hi)
    }
    /// The most of a food in one meal, whatever your usual portion (one 250 g tub of queso batido). When a
    /// meal's minimum can't be met within it, the planner adds a second food from the slot instead.
    static let absoluteMax: [String: Double] = [
        "queso-fresco-batido": 250, "skyr": 250, "yogurt": 250, "cottage-cheese": 250, "milk": 400, "protein-shake": 60,
        "eggs": 240, "egg-whites": 300, "tuna-tinned": 168, "salmon": 250, "white-fish": 300, "prawns": 250,
        "chicken": 300, "chicken-breast": 300, "chicken-thigh": 300, "turkey": 300, "beef": 300, "beef-mince": 250, "pork": 250, "ham": 150,
        "white-rice": 150, "pasta": 150, "couscous": 120, "oats": 100, "potato": 500, "sweet-potato": 450, "bread": 120, "wholemeal-bread": 120,
        "rice-cakes": 60, "pulses": 250, "nuts": 40, "peanut-butter": 32, "olive-oil": 15, "oil": 15, "banana": 240, "dates": 80,
    ]
    /// Vegetables at lunch and dinner: at least this much.
    static let vegetableMin = 150.0

    static func perDay(_ role: FoodRole, name: String, fat: Double) -> Int {
        switch role {
        case .treat, .proteinSnack: return 1
        case .condiment, .fatSource: return CondimentKind.perDay(name, fat: fat)
        case .drink: return 0
        default: return 2
        }
    }
}

extension PlanFood {
    /// The same food with another role (your correction): portion limits and meals a day follow it.
    func with(role r: FoodRole, usual: Double? = nil) -> PlanFood {
        var f = self
        f.role = r
        if r.isAccompaniment { f.step = min(f.step, 5) }
        let b = Portion.bounds(usual: usual ?? usualGrams, kcal100: per100.kcal, role: r, step: f.step, name: name, fat: per100.fat, carbs100: per100.carbs)
        (f.usualGrams, f.minGrams, f.maxGrams) = (b.usual, b.min, b.max)
        f.maxPerDay = Portion.perDay(r, name: name, fat: per100.fat)
        return f
    }
}

/// A food you eat regularly, with your usual portion and meal: what the planner uses until your log
/// has enough history.
struct Staple: Codable, Equatable, Identifiable {
    var key: String
    var grams: Double
    var band: MealBand
    var suggested = false            // confirmed from a frequency suggestion (manual ones win)
    var id: String { key }

    init(key: String, grams: Double, band: MealBand, suggested: Bool = false) { self.key = key; self.grams = grams; self.band = band; self.suggested = suggested }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key); grams = try c.decode(Double.self, forKey: .grams); band = try c.decode(MealBand.self, forKey: .band)
        suggested = try c.decodeIfPresent(Bool.self, forKey: .suggested) ?? false
    }
}

// MARK: Large entries

/// An entry or meal big enough that it may be a typo (a serving count, raw vs cooked). Until you
/// confirm it, its day stays out of expenditure and the plan doesn't count it.
enum LargeEntryRule {
    static let kcal = 1500.0
    static let shareOfTarget = 0.6
    static let mealGapMinutes = 45

    struct Entry: Equatable { var id: String; var minute: Int; var kcal: Double; var name: String }
    struct Flag: Equatable {
        var ids: [String]          // the entries (one, or the whole meal)
        var kcal: Double
        var minute: Int
        var single: Bool           // one entry by itself
        var names: [String]        // biggest first
    }

    static func isLarge(_ kcal: Double, target: Double?) -> Bool {
        kcal >= Self.kcal || (target.map { $0 > 0 && kcal >= $0 * shareOfTarget } ?? false)
    }

    /// Meals are entries within 45 minutes of the one before. A large entry is flagged by itself; its
    /// meal is flagged too only if the rest of the meal is large without it.
    static func flags(_ entries: [Entry], target: Double?, confirmed: Set<String>) -> [Flag] {
        let es = entries.sorted { ($0.minute, $0.id) < ($1.minute, $1.id) }
        var meals: [[Entry]] = []
        for e in es {
            if let last = meals.last?.last, e.minute - last.minute <= mealGapMinutes { meals[meals.count - 1].append(e) } else { meals.append([e]) }
        }
        var out: [Flag] = []
        for m in meals {
            let singles = m.filter { isLarge($0.kcal, target: target) }
            for s in singles where !confirmed.contains(s.id) {
                out.append(Flag(ids: [s.id], kcal: s.kcal, minute: s.minute, single: true, names: [s.name]))
            }
            let total = m.reduce(0) { $0 + $1.kcal }
            let ids = m.map { $0.id }
            let rest = total - singles.reduce(0) { $0 + $1.kcal }
            if m.count > 1, isLarge(total, target: target), !ids.allSatisfy({ confirmed.contains($0) }), singles.isEmpty || isLarge(rest, target: target) {
                out.append(Flag(ids: ids, kcal: total, minute: m[0].minute, single: false, names: m.sorted { $0.kcal > $1.kcal }.map { $0.name }))
            }
        }
        return out
    }
}
