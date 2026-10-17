import Foundation

// The basic foods library: generic whole foods the planner can always use, even if you've never
// logged them. They fill a role your own foods can't, or make up the "Basic" style. Values per
// 100 g from USDA FoodData Central (generic foods), or from the Spanish product on Open Food Facts
// where the USDA entry doesn't match what's sold here. Approved 17 Oct 2026.

struct BasicFood: Equatable {
    struct Values: Equatable { var kcal, protein, fat, carbs, fibre: Double }
    var id: String
    var name: String
    var role: FoodRole
    var raw: Values?              // per 100 g raw / dry (nil: sold ready to eat)
    var cooked: Values?           // per 100 g cooked (nil: eaten as is)
    var ratio: Double?            // cooked ÷ raw weight (from the raw and cooked values)
    var portion: Double           // g (ml for liquids), in the state the values are given
    var unit: (name: String, grams: Double)? = nil
    var bands: Set<MealBand>
    var nova: Int
    var basicAllowed = false      // NOVA 3–4 but allowed in Basic style (you chose it as a basic)
    var liquid = false
    var source: String            // where the values come from
    var canonical: String?

    /// The values the planner uses: raw when there are raw values (the plan converts to cooked), else cooked.
    var values: Values { raw ?? cooked! }
    var state: WeightState { raw != nil ? .raw : .cooked }
    var key: String { "basic:\(id)" }
    var inBasicStyle: Bool { nova <= 2 || basicAllowed }

    static func == (a: BasicFood, b: BasicFood) -> Bool { a.id == b.id }
}

enum BasicFoods {
    typealias V = BasicFood.Values
    static let all: [BasicFood] = [
        // Protein
        .init(id: "chicken-breast", name: "Chicken breast", role: .proteinMain, raw: V(kcal: 120, protein: 22.5, fat: 2.6, carbs: 0, fibre: 0),
              cooked: V(kcal: 165, protein: 31, fat: 3.6, carbs: 0, fibre: 0), ratio: 0.73, portion: 150, bands: [.lunch, .dinner], nova: 1, source: "USDA 171077 / 171477", canonical: "chicken-breast"),
        .init(id: "chicken-thigh", name: "Chicken thigh", role: .proteinMain, raw: V(kcal: 121, protein: 19.7, fat: 4.1, carbs: 0, fibre: 0),
              cooked: V(kcal: 179, protein: 24.8, fat: 8.2, carbs: 0, fibre: 0), ratio: 0.79, portion: 150, bands: [.lunch, .dinner], nova: 1, source: "USDA 173627 / 172388", canonical: "chicken-thigh"),
        .init(id: "beef-mince-5", name: "Lean beef mince 5%", role: .proteinMain, raw: V(kcal: 137, protein: 21.4, fat: 5, carbs: 0, fibre: 0),
              cooked: V(kcal: 193, protein: 29.2, fat: 7.6, carbs: 0, fibre: 0), ratio: 0.73, portion: 125, bands: [.lunch, .dinner], nova: 1, source: "USDA 171790 / 174028", canonical: "beef-mince"),
        .init(id: "eggs", name: "Eggs", role: .proteinMain, raw: V(kcal: 143, protein: 12.6, fat: 9.5, carbs: 0.7, fibre: 0),
              cooked: V(kcal: 155, protein: 12.6, fat: 10.6, carbs: 1.1, fibre: 0), ratio: 1.0, portion: 120, unit: ("1 egg", 60), bands: [.breakfast, .lunch, .afternoon, .dinner], nova: 1,
              source: "USDA 171287 / 173424", canonical: "eggs"),
        .init(id: "egg-whites", name: "Egg whites", role: .proteinMain, raw: V(kcal: 52, protein: 10.9, fat: 0.2, carbs: 0.7, fibre: 0),
              cooked: V(kcal: 52, protein: 10.7, fat: 0, carbs: 2.4, fibre: 0), ratio: 1.0, portion: 150, bands: [.breakfast, .dinner], nova: 1, source: "USDA 172183 / 2707170", canonical: "egg-whites"),
        .init(id: "tuna-tin", name: "Tinned tuna in water (drained)", role: .proteinMain, raw: nil, cooked: V(kcal: 90, protein: 19, fat: 0.9, carbs: 0.1, fibre: 0),
              ratio: nil, portion: 112, unit: ("1 tin (drained)", 56), bands: [.lunch, .afternoon, .dinner], nova: 3, basicAllowed: true, source: "USDA 334194", canonical: "tuna-tinned"),
        .init(id: "salmon", name: "Salmon", role: .proteinMain, raw: V(kcal: 208, protein: 20.4, fat: 13.4, carbs: 0, fibre: 0),
              cooked: V(kcal: 206, protein: 22.1, fat: 12.3, carbs: 0, fibre: 0), ratio: 0.92, portion: 125, bands: [.lunch, .dinner], nova: 1, source: "USDA 175167 / 175168", canonical: "salmon"),
        .init(id: "turkey-breast", name: "Turkey breast", role: .proteinMain, raw: V(kcal: 114, protein: 23.3, fat: 2.3, carbs: 0, fibre: 0),
              cooked: V(kcal: 136, protein: 29.5, fat: 2, carbs: 0, fibre: 0), ratio: 0.79, portion: 150, bands: [.lunch, .dinner], nova: 1, source: "USDA 174515 / 174516", canonical: "turkey"),
        .init(id: "whey", name: "Whey protein", role: .proteinSnack, raw: nil, cooked: V(kcal: 397, protein: 75, fat: 5.4, carbs: 12, fibre: 0),
              ratio: nil, portion: 30, unit: ("1 scoop", 30), bands: [.breakfast, .afternoon], nova: 4, source: "Open Food Facts 3583787294765 (Decathlon, unflavoured)", canonical: "protein-shake"),
        // Carbs
        .init(id: "white-rice", name: "White rice", role: .carbSide, raw: V(kcal: 365, protein: 7.1, fat: 0.7, carbs: 80, fibre: 1.3),
              cooked: V(kcal: 130, protein: 2.7, fat: 0.3, carbs: 28.2, fibre: 0.4), ratio: 2.8, portion: 75, bands: [.lunch, .dinner], nova: 1, source: "USDA 168877 / 168878", canonical: "white-rice"),
        .init(id: "potatoes", name: "Potatoes", role: .carbSide, raw: V(kcal: 77, protein: 2, fat: 0.1, carbs: 17.5, fibre: 2.1),
              cooked: V(kcal: 93, protein: 2.5, fat: 0.1, carbs: 21.1, fibre: 2.2), ratio: 0.83, portion: 250, bands: [.lunch, .dinner], nova: 1, source: "USDA 170026 / 170093 (baked)", canonical: "potato"),
        .init(id: "sweet-potato", name: "Sweet potato", role: .carbSide, raw: V(kcal: 86, protein: 1.6, fat: 0.1, carbs: 20.1, fibre: 3),
              cooked: V(kcal: 90, protein: 2, fat: 0.1, carbs: 20.7, fibre: 3.3), ratio: 0.96, portion: 250, bands: [.lunch, .dinner], nova: 1, source: "USDA 168482 / 168483 (baked)", canonical: "sweet-potato"),
        // Oats: always dry weight (no cooked unit).
        .init(id: "oats", name: "Oats", role: .carbSide, raw: V(kcal: 379, protein: 13.2, fat: 6.5, carbs: 67.7, fibre: 10.1), cooked: nil, ratio: nil,
              portion: 60, bands: [.breakfast, .afternoon], nova: 1, source: "USDA 173904", canonical: "oats"),
        .init(id: "pasta", name: "Pasta", role: .carbSide, raw: V(kcal: 371, protein: 13, fat: 1.5, carbs: 74.7, fibre: 3.2),
              cooked: V(kcal: 158, protein: 5.8, fat: 0.9, carbs: 30.9, fibre: 1.8), ratio: 2.4, portion: 80, bands: [.lunch, .dinner], nova: 1, source: "USDA 169736 / 169737", canonical: "pasta"),
        .init(id: "wholemeal-bread", name: "Wholemeal bread", role: .carbSide, raw: nil, cooked: V(kcal: 252, protein: 12.4, fat: 3.5, carbs: 42.7, fibre: 6),
              ratio: nil, portion: 60, unit: ("1 slice", 30), bands: [.breakfast, .lunch, .afternoon], nova: 3, basicAllowed: true, source: "USDA 172688", canonical: "wholemeal-bread"),
        .init(id: "chickpeas-jar", name: "Chickpeas, cooked (jar, drained)", role: .carbSide, raw: nil, cooked: V(kcal: 95, protein: 5.4, fat: 2, carbs: 12, fibre: 5.4),
              ratio: nil, portion: 150, bands: [.lunch, .dinner], nova: 3, source: "Open Food Facts 8431876112771 (Carrefour garbanzos cocidos)", canonical: "pulses"),
        .init(id: "lentils-jar", name: "Lentils, cooked (jar, drained)", role: .carbSide, raw: nil, cooked: V(kcal: 92, protein: 7, fat: 0, carbs: 12.5, fibre: 4.8),
              ratio: nil, portion: 150, bands: [.lunch, .dinner], nova: 4, source: "Open Food Facts 8413585012542 (bonÀrea lentejas cocidas)", canonical: "pulses"),
        // Vegetables and fruit
        .init(id: "veg-mix", name: "Frozen vegetable mix", role: .vegetable, raw: V(kcal: 72, protein: 3.3, fat: 0.5, carbs: 13.5, fibre: 4),
              cooked: V(kcal: 65, protein: 2.9, fat: 0.1, carbs: 13.1, fibre: 4.4), ratio: 1.0, portion: 200, bands: [.lunch, .dinner], nova: 1, source: "USDA 170471 / 170472", canonical: "veg-mix"),
        .init(id: "spinach", name: "Spinach", role: .vegetable, raw: V(kcal: 23, protein: 2.9, fat: 0.4, carbs: 3.6, fibre: 2.2), cooked: nil, ratio: nil,
              portion: 100, bands: [.lunch, .dinner], nova: 1, source: "USDA 168462", canonical: "spinach"),
        .init(id: "tomatoes", name: "Tomatoes", role: .vegetable, raw: V(kcal: 18, protein: 0.9, fat: 0.2, carbs: 3.9, fibre: 1.2), cooked: nil, ratio: nil,
              portion: 150, bands: [.lunch, .dinner], nova: 1, source: "USDA 170457", canonical: "tomato"),
        .init(id: "banana", name: "Banana", role: .fruit, raw: V(kcal: 89, protein: 1.1, fat: 0.3, carbs: 22.8, fibre: 2.6), cooked: nil, ratio: nil,
              portion: 120, unit: ("1 banana", 120), bands: [.breakfast, .afternoon], nova: 1, source: "USDA 173944", canonical: "banana"),
        .init(id: "apple", name: "Apple", role: .fruit, raw: V(kcal: 52, protein: 0.3, fat: 0.2, carbs: 13.8, fibre: 2.4), cooked: nil, ratio: nil,
              portion: 180, unit: ("1 apple", 180), bands: [.breakfast, .afternoon], nova: 1, source: "USDA 171688", canonical: "apple"),
        .init(id: "berries", name: "Berries (strawberries)", role: .fruit, raw: V(kcal: 32, protein: 0.7, fat: 0.3, carbs: 7.7, fibre: 2), cooked: nil, ratio: nil,
              portion: 125, bands: [.breakfast, .afternoon], nova: 1, source: "USDA 167762", canonical: "berries"),
        // Fats and dairy
        .init(id: "olive-oil", name: "Olive oil", role: .fatSource, raw: V(kcal: 884, protein: 0, fat: 100, carbs: 0, fibre: 0), cooked: nil, ratio: nil,
              portion: 10, bands: [.lunch, .dinner], nova: 2, source: "USDA 171413", canonical: "olive-oil"),
        .init(id: "greek-yogurt", name: "Greek yogurt, nonfat", role: .dairy, raw: V(kcal: 61, protein: 10.3, fat: 0.4, carbs: 3.6, fibre: 0), cooked: nil, ratio: nil,
              portion: 170, bands: [.breakfast, .afternoon], nova: 1, source: "USDA 330137", canonical: "skyr"),
        .init(id: "skyr", name: "Skyr, natural", role: .dairy, raw: V(kcal: 51, protein: 9, fat: 0.1, carbs: 3.4, fibre: 0), cooked: nil, ratio: nil,
              portion: 150, bands: [.breakfast, .afternoon], nova: 3, source: "Open Food Facts 8410500031619 (Danone skyr natural)", canonical: "skyr"),
        .init(id: "queso-batido", name: "Queso fresco batido 0%", role: .dairy, raw: V(kcal: 46, protein: 8, fat: 0.1, carbs: 3.5, fibre: 0), cooked: nil, ratio: nil,
              portion: 250, bands: [.breakfast, .afternoon, .dinner], nova: 3, basicAllowed: true, source: "Open Food Facts 8480000510211 (Hacendado)", canonical: "queso-fresco-batido"),
        .init(id: "milk-semi", name: "Semi-skimmed milk", role: .dairy, raw: V(kcal: 46, protein: 3.1, fat: 1.6, carbs: 4.8, fibre: 0), cooked: nil, ratio: nil,
              portion: 250, bands: [.breakfast, .afternoon], nova: 1, liquid: true, source: "Open Food Facts 8480000103826 (Hacendado leche semidesnatada)", canonical: "milk"),
    ]
    static let byKey: [String: BasicFood] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    /// As planner candidates: they fill what your own foods can't (no usual meal, no frequency).
    static func planFoods(excluding: Set<String> = []) -> [PlanFood] {
        all.filter { !excluding.contains($0.key) }.map { b in
            let v = b.values
            let step = b.unit?.grams ?? (v.kcal > 500 ? 5 : 10)
            var f = PlanFood(key: b.key, name: b.name, per100: (v.kcal, v.protein, v.fat, v.carbs, v.fibre), step: step, usualGrams: b.portion,
                             usualSlots: [:], frequency: 0, bands: b.bands).with(role: b.role, usual: b.portion)
            f.nova = b.nova; f.basic = true; f.basicAllowed = b.inBasicStyle
            f.canonical = b.canonical; f.tier = b.canonical.map(Taxonomy.tier) ?? 1
            return f
        }
    }
}
