import Foundation

// The simple foods catalogue: canonical tier 1 and 2 foods sold at your stores (Mercadona, Alcampo,
// Costco), with Spanish values (the median of the products grouped under each one) and typical pack
// sizes. Built from the offline database by tools/build-catalog.sh; the planner fills meal slots
// from it after your staples and usual combinations.

struct SimpleFood: Codable, Equatable, Identifiable {
    struct Values: Codable, Equatable { var kcal, protein, fat, carbs, fibre: Double }
    var id: String                    // canonical food
    var name: String
    var role: FoodRole
    var tier: Int
    var stores: [String: Int]         // store → products of it there
    var products: Int                 // matched products in Spain overall
    var values: Values                // per 100 g: the products' median, or the USDA generic food when they disagree
    var valuesFrom = "Spain"          // "Spain" (median of n products) or "USDA" (the anchor: the products were mostly prepared forms)
    var pack: Double?                 // typical pack size (g or ml)
    var serving: Double?              // typical serving on the packs (g)
    var nova: Int?                    // median NOVA of the products that have one
    var examples: [String]            // the most scanned products at your stores
    var availableAtMyStores: Bool { stores.values.contains { $0 > 0 } }
}

enum SimpleFoods {
    static let myStores = ["mercadona", "alcampo", "costco"]

    static func load(_ data: Data?) -> [SimpleFood] { data.flatMap { try? JSONDecoder().decode([SimpleFood].self, from: $0) } ?? [] }
    static var bundled: [SimpleFood] = load(Bundle.main.url(forResource: "SimpleFoods", withExtension: "json").flatMap { try? Data(contentsOf: $0) })
}
