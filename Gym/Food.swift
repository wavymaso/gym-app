import Foundation
import SwiftData

// Your foods and what you ate. Entries keep their own copy of the nutrition, so
// editing or deleting a food never changes days you've already logged.

/// A food you've used or made: from a database, your own, or a recipe.
@Model final class Food {
    var syncID: String = ""                   // the same on the Mac and the iPhone (Sync.swift)
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    @Attribute(.unique) var key: String       // off:<barcode> | usda:<fdcId> | custom:<id> | recipe:<id>
    var name: String
    var brand: String?
    var barcode: String?
    var source: String                        // off | usda | custom | recipe
    var per100: Nutrients                     // per 100 g (100 ml for drinks)
    var servings: [Serving]
    var isLiquid: Bool
    var isFavorite: Bool
    var verified: Bool = false                // you checked the numbers against the packet
    var useCount: Int
    var lastUsed: Date?
    var lastAmount: Double?                   // the amount you used last time, offered again
    var lastUnit: String?
    var recipeServings: Double?               // recipes: how many servings it makes
    var weightState: String = ""              // what the values are per: "raw" (or dry) | "cooked" | "" (not set: guessed from the name)
    var cookedRatio: Double = 0               // cooked ÷ raw weight, from a batch you weighed (0: typical value)
    var nova: Int = 0                         // NOVA group from the database (0: not known)
    var foodGroup: String = ""                // the database's food group (Open Food Facts PNNS group, or USDA category); "-" looked up, none
    var taxonomyOverride: String = ""         // your corrections (JSON Taxonomy.Override): canonical food, role, NOVA
    var taxonomySuggestion: String = ""       // the local AI's suggestion (JSON Taxonomy.Suggestion): canonical food and role only
    var createdAt: Date

    init(key: String, name: String, brand: String? = nil, barcode: String? = nil, source: String, per100: Nutrients,
         servings: [Serving] = [], isLiquid: Bool = false) {
        self.key = key; self.name = name; self.brand = brand; self.barcode = barcode; self.source = source
        self.per100 = per100; self.servings = servings; self.isLiquid = isLiquid; self.isFavorite = false
        self.useCount = 0; self.createdAt = Date()
    }

    var baseUnit: String { isLiquid ? "ml" : "g" }

    /// Units you can log this food in: its servings, then g (or ml), the other weight (cooked or raw)
    /// when it's known, and oz.
    var units: [String] { servings.map(\.name) + [baseUnit] + (otherWeightUnit.map { [$0] } ?? []) + ["oz"] }

    /// Raw or cooked: yours, else guessed from the name.
    var state: WeightState? {
        if let s = WeightState(rawValue: weightState) { return s }
        if source == "recipe" { return .raw }                 // a recipe's values are per gram of its raw ingredients
        return isLiquid ? nil : Cooking.guessState(name)
    }
    /// Cooked ÷ raw: your batch, else the typical value for this kind of food.
    var ratio: (value: Double, measured: Bool, what: String)? {
        if cookedRatio > 0 { return (cookedRatio, true, "your batch") }
        if source == "recipe" { return nil }                  // only a weighed batch tells
        return Cooking.guessRatio(name).map { ($0.ratio, false, $0.what) }
    }
    /// "g cooked" for raw/dry values, "g raw" for cooked ones.
    var otherWeightUnit: String? {
        guard let s = state, let r = ratio, abs(r.value - 1) > 0.01 else { return nil }
        return s == .raw ? Cooking.cookedUnit : Cooking.rawUnit
    }

    func grams(_ amount: Double, unit: String) -> Double {
        switch unit {
        case "g", "ml": return amount
        case Cooking.cookedUnit, Cooking.rawUnit:
            guard let s = state, let r = ratio else { return amount }
            return Cooking.grams(amount, weighedAs: unit == Cooking.cookedUnit ? .cooked : .raw, dataIs: s, ratio: r.value)
        case "oz": return amount * 28.349523125
        default: return amount * (servings.first { $0.name == unit }?.grams ?? 100)
        }
    }

    func nutrients(_ amount: Double, unit: String) -> Nutrients { per100.scaled(grams(amount, unit: unit) / 100) }

    /// What to offer when you pick this food: last time's amount, else one serving, else 100 g.
    var suggestedAmount: (Double, String) {
        if let a = lastAmount, let u = lastUnit, units.contains(u) { return (a, u) }
        if let s = servings.first { return (1, s.name) }
        return (100, baseUnit)
    }
}

/// One ingredient of a recipe (a copy of the food's nutrition at the time).
@Model final class RecipeIngredient {
    var syncID: String = ""                   // the same on the Mac and the iPhone (Sync.swift)
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var recipeKey: String
    var foodKey: String?
    var name: String
    var grams: Double
    var per100: Nutrients
    var order: Int

    init(recipeKey: String, foodKey: String?, name: String, grams: Double, per100: Nutrients, order: Int) {
        self.recipeKey = recipeKey; self.foodKey = foodKey; self.name = name; self.grams = grams
        self.per100 = per100; self.order = order
    }

    var nutrients: Nutrients { per100.scaled(grams / 100) }
}

/// Something you ate, at a time on a day.
@Model final class FoodEntry {
    var syncID: String = ""                   // the same on the Mac and the iPhone (Sync.swift)
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var day: String
    var time: Date
    var name: String
    var brand: String?
    var foodKey: String?                      // nil for a quick add
    var amount: Double
    var unit: String
    var grams: Double
    var nutrients: Nutrients
    var createdAt: Date

    init(day: String, time: Date, name: String, brand: String?, foodKey: String?, amount: Double, unit: String, grams: Double,
         nutrients: Nutrients) {
        self.day = day; self.time = time; self.name = name; self.brand = brand; self.foodKey = foodKey
        self.amount = amount; self.unit = unit; self.grams = grams; self.nutrients = nutrients; self.createdAt = Date()
    }

    var isQuickAdd: Bool { foodKey == nil }

    /// "150 g", "1 serving (125 g)", "2 × 1 cup, cooked".
    var amountText: String {
        if isQuickAdd { return "Quick add" }
        let a = number(amount, digits: amount == amount.rounded() ? 0 : 1)
        if unit == "g" || unit == "ml" || unit == "oz" || unit == Cooking.cookedUnit || unit == Cooking.rawUnit { return "\(a) \(unit)" }
        return amount == 1 ? unit : "\(a) × \(unit)"
    }
}

extension ModelContext {
    func food(key: String) -> Food? {
        try? fetch(FetchDescriptor<Food>(predicate: #Predicate { $0.key == key })).first
    }

    /// Save a database result as one of your foods (or refresh the one you have).
    func food(for r: FoodResult) -> Food {
        if let f = food(key: r.key) {
            f.name = r.name; f.brand = r.brand; f.per100 = r.per100; f.isLiquid = r.isLiquid
            if !r.servings.isEmpty { f.servings = r.servings }
            return f
        }
        let f = Food(key: r.key, name: r.name, brand: r.brand, barcode: r.barcode, source: r.source, per100: r.per100,
                     servings: r.servings, isLiquid: r.isLiquid)
        if let n = r.nova { f.nova = n }
        if let g = r.group { f.foodGroup = g }
        insert(f)
        return f
    }

    func entries(on day: String) -> [FoodEntry] {
        (try? fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.day == day }, sortBy: [SortDescriptor(\.time)]))) ?? []
    }

    /// Log an amount of a food, and remember it for next time.
    @discardableResult
    func log(_ food: Food, amount: Double, unit: String, day: String, time: Date) -> FoodEntry {
        let e = FoodEntry(day: day, time: time, name: food.name, brand: food.brand, foodKey: food.key, amount: amount, unit: unit,
                          grams: food.grams(amount, unit: unit), nutrients: food.nutrients(amount, unit: unit))
        insert(e)
        food.useCount += 1; food.lastUsed = Date(); food.lastAmount = amount; food.lastUnit = unit
        commit()
        return e
    }

    /// Copy every entry from one day to another, at the same times of day.
    func copyEntries(from source: String, to target: String) -> Int {
        let cal = Calendar.current
        let targetDate = date(fromKey: target)
        var n = 0
        for e in entries(on: source) {
            let hm = cal.dateComponents([.hour, .minute], from: e.time)
            let t = cal.date(bySettingHour: hm.hour ?? 12, minute: hm.minute ?? 0, second: 0, of: targetDate) ?? targetDate
            insert(FoodEntry(day: target, time: t, name: e.name, brand: e.brand, foodKey: e.foodKey, amount: e.amount, unit: e.unit,
                             grams: e.grams, nutrients: e.nutrients))
            n += 1
        }
        commit()
        return n
    }

    func ingredients(of recipeKey: String) -> [RecipeIngredient] {
        (try? fetch(FetchDescriptor<RecipeIngredient>(predicate: #Predicate { $0.recipeKey == recipeKey },
                                                      sortBy: [SortDescriptor(\.order)]))) ?? []
    }
}

/// A recipe's nutrition per 100 g, and its serving, from its ingredients.
func recipeTotals(_ ingredients: [(grams: Double, per100: Nutrients)], servings: Double) -> (per100: Nutrients, serving: Serving)? {
    let total = ingredients.reduce(0) { $0 + $1.grams }
    guard total > 0, servings > 0 else { return nil }
    let sum = ingredients.reduce(Nutrients.zero) { $0 + $1.per100.scaled($1.grams / 100) }
    return (sum.scaled(100 / total), Serving(name: "1 serving", grams: total / servings))
}

/// When a new entry on a day is timed: now for today, midday for other days.
func defaultTime(for day: String) -> Date {
    if day == dayKey() { return Date() }
    return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date(fromKey: day)) ?? Date()
}
