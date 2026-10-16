import Foundation

// Raw or cooked: what a food's nutrition values are per (100 g raw / dry, or 100 g cooked), and the
// cooked ÷ raw weight ratio. With both known you can log either weight and the app converts:
// 200 g of cooked pasta from a packet's dry values is 200 / 2.35 ≈ 85 g dry.

enum WeightState: String, Codable, CaseIterable {
    case raw, cooked
    var label: String { self == .raw ? "Raw / dry" : "Cooked" }
}

enum Cooking {
    /// Typical cooked ÷ raw weight (from USDA raw vs cooked energy per 100 g). Your own batch weights replace these.
    static let ratios: [(words: [String], ratio: Double, what: String)] = [
        (["arroz", "rice"], 2.8, "rice, boiled"),
        (["pasta", "rigate", "macarrones", "spaghetti", "espagueti", "penne", "fusilli", "tallarines", "fideos", "noodle", "tortellini", "ravioli"], 2.35, "pasta, boiled"),
        (["lentej", "lentil"], 3.0, "lentils, boiled"),
        (["garbanzo", "chickpea", "judías", "alubias", "beans"], 2.3, "pulses, boiled"),
        (["quinoa", "cuscús", "couscous", "bulgur"], 3.0, "grains, boiled"),
        (["avena", "oats", "porridge"], 5.0, "porridge"),
        (["patata", "potato"], 0.83, "potatoes, baked"),
        (["pollo", "chicken", "pavo", "turkey"], 0.73, "poultry, roasted"),
        (["ternera", "beef", "mince", "carne picada", "cerdo", "pork", "cordero", "lamb", "burger", "hamburguesa"], 0.75, "meat, cooked"),
        (["salmón", "salmon", "merluza", "hake", "bacalao", "cod", "atún fresco", "fish", "pescado"], 0.8, "fish, baked"),
        (["huevo", "egg"], 1.0, "eggs"),
    ]

    /// What the values probably refer to, from the name: "raw", "crudo" → raw; "cooked", "roasted",
    /// "asado"… → cooked; dry staples (pasta, rice, pulses) → raw (packet values). nil: no idea.
    static func guessState(_ name: String) -> WeightState? {
        let n = name.lowercased()
        if ["raw", "crudo", "cruda", "dry", "seco", "seca"].contains(where: { n.contains($0) }) { return .raw }
        if ["cooked", "cocido", "cocida", "roasted", "asado", "asada", "hervido", "hervida", "boiled", "baked", "al horno", "grilled",
            "a la plancha", "frito", "frita", "fried", "steamed", "al vapor"].contains(where: { n.contains($0) }) { return .cooked }
        if ["arroz", "rice", "pasta", "rigate", "macarrones", "spaghetti", "espagueti", "lentej", "lentil", "garbanzo", "chickpea", "quinoa", "cuscús", "couscous"]
            .contains(where: { n.contains($0) }) { return .raw }
        return nil
    }

    static func guessRatio(_ name: String) -> (ratio: Double, what: String)? {
        let n = name.lowercased()
        return ratios.first { $0.words.contains(where: { n.contains($0) }) }.map { ($0.ratio, $0.what) }
    }

    /// Cooked ÷ raw from a batch you weighed.
    static func ratio(raw: Double, cooked: Double) -> Double? { raw > 0 && cooked > 0 ? cooked / raw : nil }

    /// Grams in the food's own state, from what you weighed.
    static func grams(_ weighed: Double, weighedAs: WeightState, dataIs: WeightState, ratio: Double) -> Double {
        guard weighedAs != dataIs, ratio > 0 else { return weighed }
        return weighedAs == .cooked ? weighed / ratio : weighed * ratio
    }

    static let cookedUnit = "g cooked", rawUnit = "g raw"
}
