import Foundation

// Meal templates: the structure of each meal, before any food is chosen. A template is a list of
// slots (carb base, protein, vegetable…); each slot allows some canonical foods, has a default and is
// required or optional. The planner fills the slots (your staples, foods you eat together, simple
// whole foods), then sizes the portions. Seeded from how you eat (your log, 14–16 Oct 2026) and the
// brief; editable in Planner settings.

struct TemplateSlot: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case carbBase, protein, vegetable, bread, pulses, fatOrSauce, spread, fruit, carb, treat
        var label: String {
            ["carbBase": "Carb base", "protein": "Protein", "vegetable": "Vegetable", "bread": "Bread (side)", "pulses": "Pulses (side)", "fatOrSauce": "Olive oil or sauce",
             "spread": "Spread", "fruit": "Fruit", "carb": "Carb", "treat": "Treat"][rawValue]!
        }
    }
    var id: String { "\(kind.rawValue)\(required ? "" : "?")" }
    var kind: Kind
    var allowed: [String]          // canonical food ids, in order of preference when nothing else decides
    var defaultFood: String
    var required: Bool
    var maxFoods = 1               // a spread slot can take two (peanut butter and jam)
    var defaultOn = true           // optional slots: planned unless calories are tight (then dropped first)
    var maxUnits: [String: Int] = [:]   // per canonical food: at most this many units (3 chocolate rice cakes)

    init(kind: Kind, allowed: [String], defaultFood: String, required: Bool, maxFoods: Int = 1, defaultOn: Bool = true, maxUnits: [String: Int] = [:]) {
        self.kind = kind; self.allowed = allowed; self.defaultFood = defaultFood; self.required = required
        self.maxFoods = maxFoods; self.defaultOn = defaultOn; self.maxUnits = maxUnits
    }
}

struct MealTemplate: Codable, Equatable, Identifiable {
    enum Meal: String, Codable, CaseIterable {
        case breakfast, lunch, merienda, dinner, preWorkout, postWorkout, eveningSnack
        var label: String { ["breakfast": "Breakfast", "lunch": "Lunch", "merienda": "Merienda", "dinner": "Dinner", "preWorkout": "Pre-workout", "postWorkout": "Post-workout",
                             "eveningSnack": "Evening snack"][rawValue]! }
    }
    /// How the portions lean (the solver's soft targets for this meal).
    struct Emphasis: Codable, Equatable {
        var carbShare: Double? = nil      // share of the day's carbs this meal should take (nil: no lean)
        var maxFat: Double? = nil         // g
        var maxFibre: Double? = nil       // g
        var lighterCarbOnRestDays = false
    }
    var id: String
    var meal: Meal
    var name: String
    var slots: [TemplateSlot]
    var emphasis = Emphasis()
    var note = ""

    var required: [TemplateSlot] { slots.filter(\.required) }
}

enum MealTemplates {
    // Canonical food groups used by the slots.
    static let proteins = ["chicken-breast", "chicken", "chicken-thigh", "salmon", "beef-mince", "beef", "turkey", "tuna-tinned", "eggs", "egg-whites", "white-fish", "prawns"]
    static let dairyProteins = ["skyr", "queso-fresco-batido", "yogurt", "cottage-cheese"]
    static let mainCarbs = ["pasta", "white-rice", "potato", "sweet-potato", "bread", "wholemeal-bread", "pulses", "couscous"]
    static let breakfastCarbs = ["rice-cakes-chocolate", "rice-cakes", "bread", "wholemeal-bread", "oats"]
    static let lunchCarbs = ["pasta", "white-rice", "potato", "sweet-potato", "pulses", "couscous", "bread"]
    static let sauces = ["olive-oil", "tomato-sauce", "sauce", "mayonnaise", "aioli"]
    static let treats = ["biscuits", "popcorn", "crisps", "chocolate", "ice-cream", "pastry", "rice-cakes-chocolate", "protein-bar"]
    static let vegetables = ["vegetables", "veg-mix", "spinach", "tomato"]
    static let fruits = ["banana", "apple", "berries", "dates", "fruit"]

    static let defaults: [MealTemplate] = [
        .init(id: "breakfast", meal: .breakfast, name: "Breakfast", slots: [
            .init(kind: .carbBase, allowed: breakfastCarbs, defaultFood: "rice-cakes-chocolate", required: true, maxUnits: ["rice-cakes-chocolate": 3]),
            .init(kind: .spread, allowed: ["peanut-butter", "jam", "honey"], defaultFood: "peanut-butter", required: false, maxFoods: 2, defaultOn: true),
            .init(kind: .protein, allowed: ["eggs", "skyr", "egg-whites", "queso-fresco-batido", "yogurt", "cottage-cheese"], defaultFood: "eggs", required: true),
            .init(kind: .fruit, allowed: fruits, defaultFood: "banana", required: false),
        ], note: "From your breakfasts: rice cakes, jam, peanut butter and a banana. The protein is new: your breakfasts had almost none."),
        .init(id: "lunch", meal: .lunch, name: "Lunch", slots: [
            .init(kind: .carbBase, allowed: lunchCarbs, defaultFood: "potato", required: true),
            .init(kind: .protein, allowed: proteins, defaultFood: "chicken", required: true),
            .init(kind: .vegetable, allowed: vegetables, defaultFood: "spinach", required: true),
            .init(kind: .pulses, allowed: ["pulses"], defaultFood: "pulses", required: false, defaultOn: false),
            .init(kind: .bread, allowed: ["bread", "wholemeal-bread"], defaultFood: "bread", required: false),
            .init(kind: .fatOrSauce, allowed: sauces, defaultFood: "tomato-sauce", required: false),
        ], note: "From your lunches: chicken with potatoes or pasta, tomato sauce, spinach, sourdough on the side."),
        .init(id: "merienda", meal: .merienda, name: "Merienda", slots: [
            .init(kind: .protein, allowed: dairyProteins + ["tuna-tinned", "eggs"], defaultFood: "queso-fresco-batido", required: true),
            .init(kind: .carb, allowed: fruits + ["bread", "wholemeal-bread", "rice-cakes", "oats"], defaultFood: "banana", required: true),
            .init(kind: .spread, allowed: ["peanut-butter", "jam", "honey"], defaultFood: "jam", required: false),
        ], note: "From your meriendas: bread or fruit with jam and peanut butter. The protein is new."),
        .init(id: "dinner", meal: .dinner, name: "Dinner", slots: [
            .init(kind: .carbBase, allowed: ["potato", "sweet-potato", "white-rice", "pasta", "pulses", "bread"], defaultFood: "potato", required: true),
            .init(kind: .protein, allowed: proteins, defaultFood: "salmon", required: true),
            .init(kind: .vegetable, allowed: vegetables, defaultFood: "veg-mix", required: true),
            .init(kind: .pulses, allowed: ["pulses"], defaultFood: "pulses", required: false, defaultOn: false),
            .init(kind: .bread, allowed: ["bread", "wholemeal-bread"], defaultFood: "bread", required: false),
            .init(kind: .fatOrSauce, allowed: sauces, defaultFood: "olive-oil", required: false),
        ], emphasis: .init(lighterCarbOnRestDays: true), note: "Same structure and lists as lunch; a lighter carb portion on rest days."),
        .init(id: "pre-workout", meal: .preWorkout, name: "Pre-workout", slots: [
            .init(kind: .carb, allowed: ["white-rice", "rice-cakes", "bread", "oats", "potato", "banana", "dates"], defaultFood: "rice-cakes", required: true),
            .init(kind: .protein, allowed: dairyProteins + ["chicken", "chicken-breast", "turkey", "tuna-tinned", "egg-whites"], defaultFood: "skyr", required: true),
            .init(kind: .fruit, allowed: ["banana", "dates", "apple"], defaultFood: "banana", required: false),
            .init(kind: .spread, allowed: ["jam", "honey"], defaultFood: "jam", required: false),
        ], emphasis: .init(carbShare: 0.3, maxFat: 12, maxFibre: 6), note: "Carb-forward, moderate protein, low fat and fibre (registry: timing.preWorkout.*)."),
        .init(id: "post-workout", meal: .postWorkout, name: "Post-workout", slots: [
            .init(kind: .protein, allowed: proteins + dairyProteins, defaultFood: "chicken", required: true),
            .init(kind: .carbBase, allowed: ["white-rice", "pasta", "potato", "sweet-potato", "bread"], defaultFood: "white-rice", required: true),
            .init(kind: .vegetable, allowed: vegetables, defaultFood: "veg-mix", required: false),
            .init(kind: .fatOrSauce, allowed: ["olive-oil", "tomato-sauce", "sauce"], defaultFood: "tomato-sauce", required: false),
        ], emphasis: .init(carbShare: 0.3), note: "Protein plus a main carb (registry: timing.postWorkout.protein)."),
        .init(id: "evening-snack", meal: .eveningSnack, name: "Evening snack", slots: [
            .init(kind: .treat, allowed: treats, defaultFood: "biscuits", required: true),
        ], note: "Only when treats are on: one treat a day, after dinner."),
    ]

    /// The template for a planned meal: the pre- and post-workout templates replace the meal in that
    /// window (they never add meals); otherwise by the time of day.
    static func template(for slot: PlanSlot, in ts: [MealTemplate] = defaults) -> MealTemplate? {
        let meal: MealTemplate.Meal
        switch slot.kind {
        case .preWorkout: meal = .preWorkout
        case .postWorkout: meal = .postWorkout
        default:
            switch slot.band {
            case .breakfast: meal = .breakfast
            case .lunch: meal = .lunch
            case .afternoon: meal = .merienda
            case .dinner: meal = .dinner
            }
        }
        return ts.first { $0.meal == meal }
    }

    /// Every canonical id a template uses must exist.
    static func unknownFoods(_ ts: [MealTemplate]) -> [String] {
        Array(Set(ts.flatMap { $0.slots.flatMap { $0.allowed + [$0.defaultFood] } }).filter { Taxonomy.byID[$0] == nil }).sorted()
    }
}
