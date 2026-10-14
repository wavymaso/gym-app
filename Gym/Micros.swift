import Foundation

// Vitamins and minerals: what they're called, their unit, where each database keeps them,
// and a daily reference (adult; EU/US reference intakes). Limits (like cholesterol) are maximums.

struct Micro: Identifiable {
    let key: String
    let label: String
    let unit: String              // "mg" or "µg"
    let usda: Int                 // FoodData Central nutrient id
    let off: String               // Open Food Facts field, in grams per 100 g
    let male: Double
    let female: Double
    var isLimit = false
    var offFactor: Double? = nil  // overrides the g → mg/µg scale (alcohol is % vol on Open Food Facts)
    var id: String { key }

    func target(_ sex: Sex) -> Double { sex == .female ? female : male }

    /// Open Food Facts gives grams; ours are mg or µg.
    var offScale: Double { offFactor ?? (unit == "mg" ? 1_000 : unit == "g" ? 1 : 1_000_000) }

    static let all: [Micro] = [
        Micro(key: "potassium", label: "Potassium", unit: "mg", usda: 1092, off: "potassium_100g", male: 3400, female: 2600),
        Micro(key: "calcium", label: "Calcium", unit: "mg", usda: 1087, off: "calcium_100g", male: 1000, female: 1000),
        Micro(key: "magnesium", label: "Magnesium", unit: "mg", usda: 1090, off: "magnesium_100g", male: 400, female: 310),
        Micro(key: "iron", label: "Iron", unit: "mg", usda: 1089, off: "iron_100g", male: 8, female: 18),
        Micro(key: "zinc", label: "Zinc", unit: "mg", usda: 1095, off: "zinc_100g", male: 11, female: 8),
        Micro(key: "vitC", label: "Vitamin C", unit: "mg", usda: 1162, off: "vitamin-c_100g", male: 90, female: 75),
        Micro(key: "vitD", label: "Vitamin D", unit: "µg", usda: 1114, off: "vitamin-d_100g", male: 15, female: 15),
        Micro(key: "vitA", label: "Vitamin A", unit: "µg", usda: 1106, off: "vitamin-a_100g", male: 900, female: 700),
        Micro(key: "vitE", label: "Vitamin E", unit: "mg", usda: 1109, off: "vitamin-e_100g", male: 15, female: 15),
        Micro(key: "vitK", label: "Vitamin K", unit: "µg", usda: 1185, off: "vitamin-k_100g", male: 120, female: 90),
        Micro(key: "b12", label: "Vitamin B12", unit: "µg", usda: 1178, off: "vitamin-b12_100g", male: 2.4, female: 2.4),
        Micro(key: "folate", label: "Folate", unit: "µg", usda: 1177, off: "vitamin-b9_100g", male: 400, female: 400),
        Micro(key: "cholesterol", label: "Cholesterol", unit: "mg", usda: 1253, off: "cholesterol_100g", male: 300, female: 300, isLimit: true),
        Micro(key: "caffeine", label: "Caffeine", unit: "mg", usda: 1057, off: "caffeine_100g", male: 400, female: 400, isLimit: true),
        // Open Food Facts gives alcohol as % by volume: 1 % vol ≈ 0,789 g per 100 ml
        Micro(key: "alcohol", label: "Alcohol", unit: "g", usda: 1018, off: "alcohol_100g", male: 20, female: 20, isLimit: true, offFactor: 0.789),
    ]

    static func fromUSDA(_ n: [Int: Double]) -> [String: Double]? {
        let m = Dictionary(uniqueKeysWithValues: all.compactMap { x in n[x.usda].map { (x.key, $0) } })
        return m.isEmpty ? nil : m
    }

    static func fromOFF(_ v: (String) -> Double?) -> [String: Double]? {
        let m = Dictionary(uniqueKeysWithValues: all.compactMap { x in v(x.off).map { (x.key, $0 * x.offScale) } })
        return m.isEmpty ? nil : m
    }
}

/// Daily references for the other nutrients we track (per day, adult).
enum Reference {
    /// Fibre: 14 g per 1000 kcal eaten (at least 25 g).
    static func fiber(kcal: Double) -> Double { max(25, kcal / 1000 * 14) }
    /// Free sugars: under 10% of calories (an upper limit; label sugars include fruit and milk).
    static func sugar(kcal: Double) -> Double { kcal * 0.10 / 4 }
    /// Saturated fat: under 10% of calories.
    static func satFat(kcal: Double) -> Double { kcal * 0.10 / 9 }
    /// Sodium: under 2000 mg (5 g of salt).
    static let sodium = 2000.0
}
