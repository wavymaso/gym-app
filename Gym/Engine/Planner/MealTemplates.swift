import Foundation

// Meal templates: the structure of each meal, before any food is chosen. A template is a list of
// slots (carb base, protein, vegetable…); each slot allows some canonical foods, has a default and is
// required or optional. The planner fills the slots (your staples, foods you eat together, simple
// whole foods), then sizes the portions. Seeded from how you eat (your log, 14–16 Oct 2026) and the
// brief; editable in Planner settings.

struct TemplateSlot: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case carbBase, protein, vegetable, bread, fatOrSauce, spread, fruit, carb
        var label: String {
            ["carbBase": "Carb base", "protein": "Protein", "vegetable": "Vegetable", "bread": "Bread (side)", "fatOrSauce": "Olive oil or sauce",
             "spread": "Spread", "fruit": "Fruit", "carb": "Carb"][rawValue]!
        }
    }
    var id: String { "\(kind.rawValue)\(required ? "" : "?")" }
    var kind: Kind
    var allowed: [String]          // canonical food ids, in order of preference when nothing else decides
    var defaultFood: String
    var required: Bool
    var maxFoods = 1               // a spread slot can take two (peanut butter and jam)
}

struct MealTemplate: Codable, Equatable, Identifiable {
    enum Meal: String, Codable, CaseIterable {
        case breakfast, lunch, merienda, dinner, preWorkout, postWorkout
        var label: String { ["breakfast": "Breakfast", "lunch": "Lunch", "merienda": "Merienda", "dinner": "Dinner", "preWorkout": "Pre-workout", "postWorkout": "Post-workout"][rawValue]! }
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
    static let breakfastCarbs = ["rice-cakes", "bread", "wholemeal-bread", "oats"]
    static let vegetables = ["vegetables", "veg-mix", "spinach", "tomato"]
    static let fruits = ["banana", "apple", "berries", "dates", "fruit"]

    static let defaults: [MealTemplate] = [
        .init(id: "breakfast", meal: .breakfast, name: "Breakfast", slots: [
            .init(kind: .carbBase, allowed: breakfastCarbs, defaultFood: "rice-cakes", required: true),
            .init(kind: .spread, allowed: ["peanut-butter", "jam", "honey"], defaultFood: "peanut-butter", required: true, maxFoods: 2),
            .init(kind: .protein, allowed: ["eggs", "egg-whites"] + dairyProteins, defaultFood: "skyr", required: true),
            .init(kind: .fruit, allowed: fruits, defaultFood: "banana", required: false),
        ], note: "From your breakfasts: rice cakes, jam, peanut butter and a banana. The protein is new: your breakfasts had almost none."),
        .init(id: "lunch", meal: .lunch, name: "Lunch", slots: [
            .init(kind: .carbBase, allowed: ["pasta", "white-rice", "potato", "sweet-potato", "pulses", "couscous", "bread"], defaultFood: "potato", required: true),
            .init(kind: .protein, allowed: proteins, defaultFood: "chicken", required: true),
            .init(kind: .vegetable, allowed: vegetables, defaultFood: "spinach", required: true),
            .init(kind: .bread, allowed: ["bread", "wholemeal-bread"], defaultFood: "bread", required: false),
            .init(kind: .fatOrSauce, allowed: ["olive-oil", "tomato-sauce", "sauce", "mayonnaise", "aioli"], defaultFood: "tomato-sauce", required: false),
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
            .init(kind: .bread, allowed: ["bread", "wholemeal-bread"], defaultFood: "bread", required: false),
            .init(kind: .fatOrSauce, allowed: ["olive-oil", "tomato-sauce", "sauce", "mayonnaise", "aioli"], defaultFood: "olive-oil", required: false),
        ], emphasis: .init(lighterCarbOnRestDays: true), note: "Same structure as lunch; a lighter carb portion on rest days."),
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
    ]

    /// Every canonical id a template uses must exist.
    static func unknownFoods(_ ts: [MealTemplate]) -> [String] {
        Array(Set(ts.flatMap { $0.slots.flatMap { $0.allowed + [$0.defaultFood] } }).filter { Taxonomy.byID[$0] == nil }).sorted()
    }
}
