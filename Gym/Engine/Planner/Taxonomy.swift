import Foundation

// The food taxonomy: what a food is underneath the brand (a canonical food, anchored to a generic
// USDA food), its role in a meal, how processed it is (NOVA group) and whether its values are raw or
// cooked. Rules decide first (name keywords, the database's category, the macro profile); the local
// AI may suggest a canonical food and role for what rules can't place, but never touches nutrition;
// your corrections override both, permanently.

/// What a food's nutrition values are per: raw (or dry) weight, or cooked weight.
enum WeightState: String, Codable, CaseIterable {
    case raw, cooked
    var label: String { self == .raw ? "Raw / dry" : "Cooked" }
}

/// A food's job in a meal.
enum FoodRole: String, Codable, CaseIterable {
    case proteinMain    // chicken, fish, eggs, lean meat, tofu: the protein centre of a meal
    case carbSide       // rice, pasta, bread, potatoes, oats
    case vegetable
    case fruit
    case fatSource      // oil, nuts, avocado: small amounts alongside
    case dairy          // yogurt, skyr, cottage cheese, milk, cheese
    case proteinSnack   // protein bars, shakes: protein-dense, between or with meals
    case condiment      // jam, honey, spreads, sauces: only alongside a meal's food
    case treat          // sweets, crisps, biscuits: once a day, never a meal on its own
    case drink          // not planned

    var label: String {
        ["proteinMain": "Protein main", "carbSide": "Carb side", "vegetable": "Vegetable", "fruit": "Fruit", "fatSource": "Fat source", "dairy": "Dairy",
         "proteinSnack": "Protein snack", "condiment": "Condiment", "treat": "Treat", "drink": "Drink"][rawValue]!
    }
    /// Can be what a meal is built around.
    var isCore: Bool { self == .proteinMain || self == .carbSide || self == .dairy || self == .proteinSnack }
    /// Brings real protein (counts for the per-meal minimum like any food, and can anchor it).
    var isProteinSource: Bool { self == .proteinMain || self == .dairy || self == .proteinSnack }
    /// Small amounts, only with something else.
    var isAccompaniment: Bool { self == .condiment || self == .fatSource }

    // Earlier versions stored "main", "side": read them as the closest new role.
    init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        switch s {
        case "main": self = .proteinMain
        case "side": self = .vegetable
        default:
            guard let r = FoodRole(rawValue: s) else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "role \(s)")) }
            self = r
        }
    }
}

/// A canonical food: the generic thing a product is (USDA anchor), its role and typical NOVA group
/// as bought.
struct CanonicalFood: Equatable {
    var id: String
    var name: String
    var usda: String            // the generic USDA food it maps to (description in FoodData Central)
    var role: FoodRole
    var nova: Int               // typical for this product as bought (used only when nothing better is known)
    var words: [String]         // name keywords, Spanish and English (matched lower-case, accents as written)
    var bands: Set<MealBand> = []
}

enum Taxonomy {
    // Most specific first: the first keyword hit wins (so "rice cakes" before "rice", "peanut butter" before "butter").
    static let canonical: [CanonicalFood] = [
        // Treats and snacks that contain staple words
        .init(id: "rice-cakes-chocolate", name: "Rice cakes with chocolate", usda: "Rice cake, cracker (include hain mini rice cakes)", role: .treat, nova: 4,
              words: ["tortitas de arroz integral con chocolate", "tortitas de arroz con chocolate", "rice cakes with chocolate", "chocolate rice cake"]),
        .init(id: "rice-cakes", name: "Rice cakes", usda: "Rice cake, cracker (include hain mini rice cakes)", role: .carbSide, nova: 3, words: ["tortitas de arroz", "rice cake", "tortitas de maíz"]),
        .init(id: "protein-bar", name: "Protein bar", usda: "Snacks, granola bars, soft, uncoated, plain", role: .proteinSnack, nova: 4,
              words: ["barebells", "protein bar", "barrita de proteína", "barrita proteica", "quest bar", "grenade", "carb killa"], bands: [.breakfast, .afternoon]),
        .init(id: "protein-shake", name: "Protein shake / whey", usda: "Beverages, Whey protein powder isolate", role: .proteinSnack, nova: 4,
              words: ["whey", "proteína en polvo", "protein powder", "batido de proteína", "protein shake", "+proteinas", "isolate"], bands: [.breakfast, .afternoon]),
        .init(id: "protein-noodles", name: "Protein noodles", usda: "Noodles, egg, dry, enriched", role: .proteinMain, nova: 4, words: ["protein noodles", "fideos proteicos", "protein pasta"]),
        .init(id: "biscuits", name: "Biscuits / cookies", usda: "Cookies, butter, commercially prepared, enriched", role: .treat, nova: 4,
              words: ["pepero", "galleta", "cookie", "biscuit", "oreo", "príncipe", "digestive"]),
        .init(id: "popcorn", name: "Popcorn", usda: "Snacks, popcorn, microwave, regular (butter) flavor, made with partially hydrogenated oil", role: .treat, nova: 4, words: ["palomitas", "popcorn"]),
        .init(id: "crisps", name: "Crisps", usda: "Snacks, potato chips, plain, salted", role: .treat, nova: 4, words: ["patatas fritas", "chips", "crisps", "pringles", "doritos", "nachos"]),
        .init(id: "dessert", name: "Dessert", usda: "Puddings, vanilla, ready-to-eat", role: .treat, nova: 4, words: ["flan", "natillas", "postre", "pudding", "arroz con leche", "cuajada"]),
        .init(id: "chocolate", name: "Chocolate", usda: "Candies, milk chocolate", role: .treat, nova: 4, words: ["chocolate con leche", "tableta de chocolate", "kitkat", "kinder", "milka", "chocolatina", "bombón"]),
        .init(id: "ice-cream", name: "Ice cream", usda: "Ice creams, vanilla", role: .treat, nova: 4, words: ["helado", "ice cream"]),
        .init(id: "pastry", name: "Pastry", usda: "Croissants, butter", role: .treat, nova: 4, words: ["croissant", "napolitana", "donut", "bollo", "magdalena", "muffin", "brownie", "palmera"]),
        // Juices before the fruit they're made from (a drink: not planned)
        .init(id: "juice", name: "Juice", usda: "Orange juice, raw (Includes foods for USDA's Food Distribution Program)", role: .drink, nova: 1,
              words: ["zumo", "juice", "néctar", "nectar", "smoothie"]),
        // Spreads and sauces (before the staples they contain)
        .init(id: "peanut-butter", name: "Peanut butter", usda: "Peanut butter, smooth style, without salt", role: .fatSource, nova: 2,
              words: ["peanut butter", "crema de cacahuete", "mantequilla de cacahuete"]),
        .init(id: "jam", name: "Jam", usda: "Jams and preserves", role: .condiment, nova: 3, words: ["mermelada", "jam", "confitura", "preserves"]),
        .init(id: "honey", name: "Honey", usda: "Honey", role: .condiment, nova: 1, words: ["miel", "honey"]),
        .init(id: "chocolate-spread", name: "Chocolate spread", usda: "Chocolate-flavored hazelnut spread", role: .condiment, nova: 4, words: ["nutella", "nocilla", "crema de cacao"]),
        .init(id: "tomato-sauce", name: "Tomato sauce", usda: "Sauce, pasta, spaghetti/marinara, ready-to-serve", role: .condiment, nova: 3, words: ["tomate frito", "salsa de tomate", "tomato sauce", "passata", "marinara"]),
        .init(id: "ketchup", name: "Ketchup", usda: "Catsup", role: .condiment, nova: 4, words: ["ketchup", "kétchup", "catsup"]),
        .init(id: "mayonnaise", name: "Mayonnaise", usda: "Salad dressing, mayonnaise, light", role: .condiment, nova: 4, words: ["ligeresa", "mayonesa", "mayonnaise", "mayo"]),
        .init(id: "aioli", name: "Garlic sauce (aioli)", usda: "Salad dressing, mayonnaise, regular", role: .condiment, nova: 4, words: ["aioli", "alioli", "allioli", "garlic sauce", "dipping sauce"]),
        .init(id: "sauce", name: "Sauce", usda: "Sauce, barbecue", role: .condiment, nova: 4, words: ["sauce", "salsa", "dressing", "aliño", "pesto", "mustard", "mostaza", "sriracha", "salsa de soja", "guacamole"]),
        .init(id: "butter", name: "Butter", usda: "Butter, salted", role: .fatSource, nova: 2, words: ["mantequilla", "butter"]),
        .init(id: "olive-oil", name: "Olive oil", usda: "Oil, olive, salad or cooking", role: .fatSource, nova: 2, words: ["aceite de oliva", "olive oil", "aove"]),
        .init(id: "oil", name: "Oil", usda: "Oil, sunflower, linoleic, (approx. 65%)", role: .fatSource, nova: 2, words: ["aceite", " oil"]),
        // Protein mains (cold cuts and processed meat first: "pechuga de pavo en lonchas" is a cold cut)
        .init(id: "ham", name: "Cold cuts / cured ham", usda: "Ham, sliced, regular (approximately 11% fat)", role: .proteinMain, nova: 3,
              words: ["jamón", "jamon", "ham", "fiambre", "lonchas", "loncheada", "loncheado", "chopped", "mortadela", "chorizo", "salami", "lomo embuchado", "pechuga de pavo cocida", "pechuga de pollo cocida", "pavo braseado", "pollo braseado", "pechuga de pavo asada"]),
        .init(id: "burger", name: "Burgers", usda: "Beef, ground, 80% lean meat / 20% fat, patty, cooked, broiled", role: .proteinMain, nova: 3, words: ["burger", "hamburguesa", "burguer"]),
        .init(id: "sausages", name: "Sausages", usda: "Sausage, pork, chorizo, link or ground, raw", role: .proteinMain, nova: 4, words: ["salchicha", "sausage", "frankfurt", "bratwurst"]),
        .init(id: "chicken-breast", name: "Chicken breast", usda: "Chicken, broiler or fryers, breast, skinless, boneless, meat only, raw", role: .proteinMain, nova: 1,
              words: ["pechuga de pollo", "chicken breast", "filete de pollo"]),
        .init(id: "chicken-thigh", name: "Chicken thigh", usda: "Chicken, broilers or fryers, dark meat, thigh, meat only, raw", role: .proteinMain, nova: 1, words: ["muslo de pollo", "contramuslo", "chicken thigh"]),
        .init(id: "chicken", name: "Chicken", usda: "Chicken, broilers or fryers, meat only, cooked, roasted", role: .proteinMain, nova: 1, words: ["roasted chicken", "pollo asado", "pollo", "chicken", "roosterz", "roosters"]),
        .init(id: "chicken-wings", name: "Chicken wings", usda: "Chicken, broilers or fryers, wing, meat and skin, cooked, roasted", role: .proteinMain, nova: 3, words: ["alitas", "wings"]),
        .init(id: "turkey", name: "Turkey breast", usda: "Turkey, retail parts, breast, meat only, raw", role: .proteinMain, nova: 1, words: ["pechuga de pavo", "pavo", "turkey"]),
        .init(id: "beef-mince", name: "Lean beef mince", usda: "Beef, ground, 95% lean meat / 5% fat, raw", role: .proteinMain, nova: 1,
              words: ["carne picada", "picada de ternera", "beef mince", "ground beef", "mince"]),
        .init(id: "beef", name: "Beef", usda: "Beef, top sirloin, steak, separable lean only, trimmed to 1/8\" fat, all grades, raw", role: .proteinMain, nova: 1, words: ["ternera", "beef", "solomillo", "entrecot", "vacuno", "añojo"]),
        .init(id: "pork", name: "Pork", usda: "Pork, fresh, loin, tenderloin, separable lean only, raw", role: .proteinMain, nova: 1, words: ["cerdo", "pork", "lomo"]),
        .init(id: "tuna-tinned", name: "Tinned tuna", usda: "Fish, tuna, light, canned in water, drained solids", role: .proteinMain, nova: 2, words: ["atún", "atun", "tuna"]),
        .init(id: "salmon", name: "Salmon", usda: "Fish, salmon, Atlantic, farmed, raw", role: .proteinMain, nova: 1, words: ["salmón", "salmon"]),
        .init(id: "white-fish", name: "White fish", usda: "Fish, cod, Atlantic, raw", role: .proteinMain, nova: 1, words: ["merluza", "bacalao", "hake", "cod", "dorada", "lubina", "pescado", "fish"]),
        .init(id: "prawns", name: "Prawns", usda: "Crustaceans, shrimp, raw", role: .proteinMain, nova: 1, words: ["gambas", "langostinos", "prawn", "shrimp"]),
        .init(id: "egg-whites", name: "Egg whites", usda: "Egg, white, raw, fresh", role: .proteinMain, nova: 1, words: ["claras", "egg white"]),
        .init(id: "eggs", name: "Eggs", usda: "Egg, whole, raw, fresh", role: .proteinMain, nova: 1, words: ["huevo", "egg"]),
        .init(id: "tofu", name: "Tofu", usda: "Tofu, firm, prepared with calcium sulfate and magnesium chloride (nigari)", role: .proteinMain, nova: 3, words: ["tofu", "seitan", "tempeh"]),
        // Dairy
        .init(id: "queso-fresco-batido", name: "Queso fresco batido 0%", usda: "Cheese, cottage, nonfat, uncreamed, dry, large or small curd", role: .dairy, nova: 1, words: ["queso fresco batido", "quark", "fromage frais"]),
        .init(id: "skyr", name: "Greek yogurt / skyr", usda: "Yogurt, Greek, plain, nonfat", role: .dairy, nova: 1, words: ["skyr", "yogur griego", "greek yogurt", "yogur proteico", "high protein yogurt", "yopro"]),
        .init(id: "yogurt", name: "Yogurt", usda: "Yogurt, plain, low fat", role: .dairy, nova: 1, words: ["yogur", "yogurt", "kefir"]),
        .init(id: "cottage-cheese", name: "Cottage cheese", usda: "Cheese, cottage, lowfat, 2% milkfat", role: .dairy, nova: 2, words: ["requesón", "cottage"]),
        .init(id: "cheese", name: "Cheese", usda: "Cheese, cheddar", role: .dairy, nova: 3, words: ["queso", "cheese", "mozzarella", "parmesano"]),
        .init(id: "milk", name: "Milk", usda: "Milk, lowfat, fluid, 1% milkfat, with added vitamin A and vitamin D", role: .dairy, nova: 1, words: ["leche", "milk"]),
        // Carb sides
        .init(id: "filled-pasta", name: "Filled pasta", usda: "Ravioli, cheese-filled, canned", role: .carbSide, nova: 4, words: ["tortellini", "ravioli", "raviolis", "cappelletti", "gnocchi"]),
        .init(id: "pasta", name: "Pasta", usda: "Pasta, dry, enriched", role: .carbSide, nova: 1,
              words: ["pasta", "rigate", "macarrones", "spaghetti", "espagueti", "penne", "fusilli", "tallarines", "fideos", "noodle", "lasaña"]),
        .init(id: "white-rice", name: "White rice", usda: "Rice, white, long-grain, regular, raw, enriched", role: .carbSide, nova: 1, words: ["arroz redondo", "arroz largo", "arroz blanco", "basmati", "jazmín", "white rice", "arroz", "rice"]),
        .init(id: "oats", name: "Oats", usda: "Cereals, oats, regular and quick, not fortified, dry", role: .carbSide, nova: 1, words: ["copos de avena", "avena", "oats", "porridge"], bands: [.breakfast, .afternoon]),
        .init(id: "cereal", name: "Breakfast cereal", usda: "Cereal, corn flakes, plain", role: .carbSide, nova: 4, words: ["cereal", "corn flakes", "granola", "muesli"], bands: [.breakfast, .afternoon]),
        .init(id: "wholemeal-bread", name: "Wholemeal bread", usda: "Bread, whole-wheat, commercially prepared", role: .carbSide, nova: 3, words: ["pan integral", "wholemeal", "whole wheat bread", "pan de centeno"]),
        .init(id: "bread", name: "Bread", usda: "Bread, white, commercially prepared (includes soft bread crumbs)", role: .carbSide, nova: 3,
              words: ["sourdough", "masa madre", "baguette", "barra de pan", "pan de molde", "bread", "pan ", "tostada", "wrap", "tortilla de trigo", "tortillas trigo", "bagel"]),
        .init(id: "sweet-potato", name: "Sweet potato", usda: "Sweet potato, raw, unprepared (Includes foods for USDA's Food Distribution Program)", role: .carbSide, nova: 1, words: ["boniato", "batata", "sweet potato"]),
        .init(id: "potato", name: "Potatoes", usda: "Potatoes, flesh and skin, raw", role: .carbSide, nova: 1, words: ["patata", "potato"]),
        .init(id: "green-beans", name: "Green beans", usda: "Beans, snap, green, raw", role: .vegetable, nova: 1, words: ["judía verde", "judías verdes", "judia verde", "judias verdes", "green bean", "vainas"]),
        .init(id: "pulses", name: "Pulses", usda: "Lentils, raw", role: .carbSide, nova: 1, words: ["lenteja", "lentil", "garbanzo", "chickpea", "alubia", "judías", "beans"]),
        .init(id: "couscous", name: "Couscous / quinoa", usda: "Couscous, dry", role: .carbSide, nova: 1, words: ["cuscús", "couscous", "quinoa", "bulgur"]),
        // Vegetables and fruit
        .init(id: "broccoli", name: "Broccoli", usda: "Broccoli, raw", role: .vegetable, nova: 1, words: ["brócoli", "brocoli", "broccoli", "bimi"]),
        .init(id: "carrots", name: "Carrots", usda: "Carrots, raw", role: .vegetable, nova: 1, words: ["zanahoria", "carrot"]),
        .init(id: "peppers", name: "Peppers", usda: "Peppers, sweet, red, raw", role: .vegetable, nova: 1, words: ["pimiento", "bell pepper", "red pepper", "green pepper"]),
        .init(id: "artichokes", name: "Artichokes", usda: "Artichokes, (globe or french), cooked, boiled, drained, without salt", role: .vegetable, nova: 1, words: ["alcachofa", "artichoke"]),
        .init(id: "spinach", name: "Spinach", usda: "Spinach, raw", role: .vegetable, nova: 1, words: ["espinaca", "spinach"]),
        .init(id: "tomato", name: "Tomatoes", usda: "Tomatoes, red, ripe, raw, year round average", role: .vegetable, nova: 1, words: ["tomate", "tomato"]),
        .init(id: "veg-mix", name: "Mixed vegetables", usda: "Vegetables, mixed, frozen, unprepared", role: .vegetable, nova: 1, words: ["verduras", "menestra", "salteado de verduras", "mixed vegetables", "vegetable mix", "wok"]),
        .init(id: "vegetables", name: "Vegetables", usda: "Broccoli, raw", role: .vegetable, nova: 1,
              words: ["lechuga", "lettuce", "ensalada", "salad", "pepino", "cucumber", "calabacín",
                      "zucchini", "cebolla", "onion", "champiñ", "mushroom", "coliflor", "cauliflower", "berenjena", "kimchi"]),
        .init(id: "banana", name: "Banana", usda: "Bananas, raw", role: .fruit, nova: 1, words: ["plátano", "platano", "banana"]),
        .init(id: "apple", name: "Apple", usda: "Apples, raw, with skin (Includes foods for USDA's Food Distribution Program)", role: .fruit, nova: 1, words: ["manzana", "apple"]),
        .init(id: "raspberries", name: "Raspberries", usda: "Raspberries, raw", role: .fruit, nova: 1, words: ["frambuesa", "raspberr", "mora", "blackberr"]),
        .init(id: "berries", name: "Berries", usda: "Strawberries, raw", role: .fruit, nova: 1, words: ["fresa", "strawberr", "arándano", "blueberr", "berries", "frutos rojos"]),
        .init(id: "pear", name: "Pear", usda: "Pears, raw", role: .fruit, nova: 1, words: ["pera", "pear"]),
        .init(id: "dates", name: "Dates", usda: "Dates, medjool", role: .fruit, nova: 1, words: ["dátil", "datil", "dates"]),
        .init(id: "fruit", name: "Fruit", usda: "Oranges, raw, all commercial varieties", role: .fruit, nova: 1,
              words: ["naranja", "orange", "uva", "grape", "mango", "piña", "pineapple", "kiwi", "melón", "melon", "sandía", "melocotón", "peach", "fruta", "fruit"]),
        .init(id: "nuts", name: "Nuts", usda: "Nuts, almonds", role: .fatSource, nova: 1, words: ["almendra", "almond", "nuez", "walnut", "anacardo", "cashew", "pistacho", "cacahuete", "peanut", "avellana", "frutos secos", "nuts"]),
        .init(id: "avocado", name: "Avocado", usda: "Avocados, raw, all commercial varieties", role: .fatSource, nova: 1, words: ["aguacate", "avocado"]),
        // Drinks
        .init(id: "energy-drink", name: "Energy drink", usda: "Beverages, Energy drink, AMP, sugar free", role: .drink, nova: 4, words: ["nocco", "monster", "red bull", "energy", "ramonade", "bcaa drink"]),
        .init(id: "soft-drink", name: "Soft drink", usda: "Beverages, carbonated, cola, without caffeine", role: .drink, nova: 4, words: ["coca-cola", "coca cola", "coke", "pepsi", "fanta", "refresco", "soda", "zero"]),
        .init(id: "coffee", name: "Coffee", usda: "Beverages, coffee, brewed, prepared with tap water", role: .drink, nova: 1, words: ["café", "coffee", "té ", "tea"]),
    ]
    static let byID: [String: CanonicalFood] = Dictionary(uniqueKeysWithValues: canonical.map { ($0.id, $0) })

    /// Whole foods first. Tier 1: whole foods (meat, fish, eggs, rice, potatoes, pasta, oats, bread,
    /// fruit, vegetables, legumes, plain dairy). Tier 2: simple staples (peanut butter, jam, oil, tinned
    /// fish, plain sauces; chocolate rice cakes as a breakfast base; whey, when in stock). Tier 3:
    /// convenience products (bars, ready meals, protein noodles, snacks): only planned when in stock.
    static func tier(_ id: String) -> Int {
        let two: Set<String> = ["peanut-butter", "jam", "honey", "olive-oil", "oil", "butter", "tuna-tinned", "ham", "tomato-sauce", "ketchup", "mayonnaise", "aioli",
                                "sauce", "rice-cakes", "rice-cakes-chocolate", "protein-shake", "cheese", "cottage-cheese", "tofu", "cereal", "chocolate-spread"]
        let three: Set<String> = ["burger", "sausages", "dessert", "protein-bar", "protein-noodles", "biscuits", "popcorn", "crisps", "chocolate", "ice-cream", "pastry", "filled-pasta", "chicken-wings",
                                  "energy-drink", "soft-drink", "juice"]
        return three.contains(id) ? 3 : two.contains(id) ? 2 : 1
    }
    /// The protein family (chicken breast, thigh and roast chicken are all chicken): for "not the same
    /// protein at lunch and dinner" and rotation.
    static func family(_ id: String) -> String {
        if id.hasPrefix("chicken") { return "chicken" }
        if ["beef", "beef-mince", "burger"].contains(id) { return "beef" }
        if ["eggs", "egg-whites"].contains(id) { return "eggs" }
        if ["skyr", "yogurt", "queso-fresco-batido", "cottage-cheese"].contains(id) { return "dairy" }
        return id
    }

    /// Planned only when you've marked it in stock (tier 3, and whey).
    static func needsStock(_ id: String) -> Bool { tier(id) == 3 || id == "protein-shake" }

    struct Result: Equatable {
        enum Source: String, Codable { case user, rule, category, macros, ai }
        var canonical: String?          // CanonicalFood id
        var role: FoodRole
        var nova: Int                   // 1–4
        var novaSource: String          // "Open Food Facts", "USDA generic", "estimated", "your correction"
        var novaEstimated: Bool
        var state: WeightState?
        var confidence: Double          // 0–1: rules agreeing with each other, or you
        var roleSource: Source
        var why: [String]
        var canonicalName: String? { canonical.flatMap { byID[$0]?.name } }
    }

    /// What we know about a food before classifying it.
    struct Input {
        var key: String? = nil          // basic:<id> foods are known exactly
        var name: String
        var brand: String?
        var source: String              // off | usda | custom | recipe
        var kcal: Double, protein: Double, fat: Double, carbs: Double, sugar: Double? = nil
        var isLiquid = false
        var offNova: Int? = nil         // Open Food Facts NOVA group
        var offGroup: String? = nil     // Open Food Facts pnns_groups_2
        var usdaCategory: String? = nil
        var ingredientNovas: [Int] = [] // recipes: the NOVA groups of the ingredients
        var state: WeightState? = nil
    }

    /// Your corrections (any field you set wins) and an AI suggestion (only canonical and role).
    struct Override: Codable, Equatable { var canonical: String?; var role: FoodRole?; var nova: Int? }
    struct Suggestion: Codable, Equatable { var canonical: String?; var role: FoodRole?; var confidence: Double = 0.6 }

    /// Lower-case words separated by single spaces (letters, digits, + & % kept), padded with spaces.
    static func words(_ s: String) -> String {
        let mapped = s.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || "+&%".unicodeScalars.contains($0) ? Character($0) : " " }
        return " " + String(mapped).split(separator: " ").joined(separator: " ") + " "
    }
    /// A keyword matches whole words (plurals allowed: "patata" matches "patatas", "strawberr" "strawberries"),
    /// so "tuna" doesn't match "aceitunas" and "jam" doesn't match "jamón".
    static func contains(_ text: String, _ keyword: String) -> Bool {
        let k = words(keyword).trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return false }
        var from = text.startIndex
        while let r = text.range(of: " " + k, range: from..<text.endIndex) {
            let rest = text[r.upperBound...]
            if ["", "s", "es", "ies", "ones", "as", "os"].contains(where: { rest.hasPrefix($0 + " ") }) { return true }
            from = text.index(after: r.lowerBound)
        }
        return false
    }

    static func match(_ name: String, brand: String?) -> CanonicalFood? {
        let text = words(name + " " + (brand ?? ""))
        return canonical.first { c in c.words.contains { contains(text, $0) } }
    }

    /// Processed forms of a whole food (crisps aren't potatoes, dried berries aren't berries): left out
    /// of the catalogue's values and availability for tier 1 foods.
    static let processedWords = ["frita", "fritas", "frito", "chips", "puré", "pure", "crema", "tortilla", "empanad", "rebozad", "relleno", "rellena", "kebab", "nugget",
                                 "salchicha", "deshidratad", "desecad", "postre", "flan", "bebible", "bebida", "batido", "zumo", "caldo", "sopa", "crunchy", "chocolate",
                                 "barrita", "barres", "bar", "sabor", "azúcar", "azucar", "con", "salad", "ensalada", "guacamole", "glace", "cup", "pudding", "gelificado",
                                 "marinad", "ahumad", "al huevo", "copos", "galleta", "snack", "light", "compota", "mermelada", "confitura", "helado", "salsa", "pizza", "croqueta",
                                 "lasagna", "lasaña", "canelones", "precocinad", "sandwich", "wrap", "pastel", "tarta", "muffin", "bollo", "dulce"]
    static func isPlainForm(_ name: String) -> Bool {
        let t = words(name)
        return !processedWords.contains { contains(t, $0) || t.contains(" " + $0) }
    }

    /// The role the database's category points to (Open Food Facts food group or USDA category).
    static func role(group: String?, usdaCategory: String?) -> FoodRole? {
        if let g = group?.lowercased(), g != "unknown" {
            if ["meat", "poultry", "fish and seafood", "eggs", "processed meat", "offals"].contains(g) { return .proteinMain }
            if ["cereals", "bread", "potatoes", "legumes"].contains(g) { return .carbSide }
            if ["vegetables", "soups"].contains(g) { return .vegetable }
            if ["fruits", "dried fruits", "fruit nectars"].contains(g) { return .fruit }
            if ["milk and yogurt", "cheese", "dairy desserts"].contains(g) { return .dairy }
            if ["fats", "nuts"].contains(g) { return .fatSource }
            if g == "dressings and sauces" { return .condiment }
            if ["sweets", "biscuits and cakes", "chocolate products", "appetizers", "salty and fatty products", "ice cream", "pastries", "breakfast cereals"].contains(g) {
                return g == "breakfast cereals" ? .carbSide : .treat
            }
            if g.contains("beverages") || g.contains("juices") || g.contains("waters") || g.contains("teas") { return .drink }
        }
        if let c = usdaCategory?.lowercased() {
            if ["poultry", "beef", "pork", "finfish", "lamb", "sausages", "chicken", "turkey", "fish", "meat"].contains(where: { c.contains($0) }) { return .proteinMain }
            if ["cereal grains", "pasta", "legumes", "rice", "bread", "potato"].contains(where: { c.contains($0) }) { return .carbSide }
            if c.contains("vegetable") { return .vegetable }
            if c.contains("fruit") { return .fruit }
            if c.contains("dairy") || c.contains("milk") || c.contains("yogurt") || c.contains("cheese") { return .dairy }
            if c.contains("fats and oils") || c.contains("nut and seed") { return .fatSource }
            if c.contains("sauces") || c.contains("spices") || c.contains("condiment") { return .condiment }
            if c.contains("sweets") || c.contains("snacks") || c.contains("candy") || c.contains("cookies") || c.contains("cakes") { return .treat }
            if c.contains("beverages") { return .drink }
        }
        return nil
    }

    /// The role the macro profile points to: > 60% of calories from protein → protein; mostly fat →
    /// fat source; mostly carbs → carb side (or fruit/treat by sugar).
    static func role(kcal: Double, protein: Double, fat: Double, carbs: Double, sugar: Double?, isLiquid: Bool) -> FoodRole? {
        guard kcal > 5 else { return isLiquid ? .drink : nil }
        let p = protein * 4 / kcal, f = fat * 9 / kcal, c = carbs * 4 / kcal
        // Liquids: a protein shake is a protein snack, milk-like drinks dairy; other drinks (non-nutritive,
        // caffeinated, sugary) aren't planned.
        if isLiquid { return p > 0.5 ? .proteinSnack : p > 0.2 ? .dairy : .drink }
        if p > 0.6 { return .proteinMain }
        if p > 0.3 && kcal > 300 { return .proteinSnack }
        if f > 0.7 { return .fatSource }
        if c > 0.6 { return (sugar ?? 0) > carbs * 0.5 ? (kcal > 200 ? .treat : .fruit) : .carbSide }
        if f > 0.4 && c > 0.35 { return .treat }
        return nil
    }

    static func classify(_ x: Input, override: Override? = nil, suggestion: Suggestion? = nil) -> Result {
        if override == nil, let k = x.key, let b = BasicFoods.byKey[k] {
            return Result(canonical: b.canonical, role: b.role, nova: b.nova, novaSource: "basic foods library (\(b.source))", novaEstimated: false,
                          state: b.state, confidence: 1, roleSource: .rule, why: ["basic foods library"])
        }
        var why: [String] = []
        let canon = override?.canonical.flatMap { byID[$0] } ?? match(x.name, brand: x.brand) ?? suggestion?.canonical.flatMap { byID[$0] }
        if let c = canon, override?.canonical == nil { why.append("name → \(c.name)") }
        let byCategory = role(group: x.offGroup, usdaCategory: x.usdaCategory)
        let byMacros = role(kcal: x.kcal, protein: x.protein, fat: x.fat, carbs: x.carbs, sugar: x.sugar, isLiquid: x.isLiquid)
        if let r = byCategory { why.append("category → \(r.label)") }
        if let r = byMacros { why.append("macros → \(r.label)") }

        // Role: yours → name rule → category → macros → AI suggestion → condiment-ish fallback.
        var role: FoodRole, src: Result.Source, conf: Double
        if let r = override?.role { role = r; src = .user; conf = 1 }
        else if let c = canon, match(x.name, brand: x.brand) != nil {
            role = c.role; src = .rule
            let agree = [byCategory, byMacros].compactMap { $0 }
            conf = agree.isEmpty ? 0.8 : agree.contains(where: { compatible($0, c.role) }) ? 0.95 : 0.7
            if !agree.isEmpty && !agree.contains(where: { compatible($0, c.role) }) { why.append("⚠ the name and the \(byCategory != nil ? "category" : "macros") disagree") }
        } else if let r = byCategory { role = r; src = .category; conf = byMacros == nil || byMacros == r ? 0.75 : 0.6 }
        else if let s = suggestion?.role { role = s; src = .ai; conf = min(0.65, s == byMacros ? 0.65 : suggestion!.confidence) ; why.append("AI suggestion") }
        else if let r = byMacros { role = r; src = .macros; conf = 0.5 }
        else { role = .condiment; src = .macros; conf = 0.2; why.append("no rule matched") }
        // A protein-dense bar or shake is a protein snack even if the macros say protein main.
        if src != .user, role == .proteinMain, x.name.lowercased().contains("bar") || x.name.lowercased().contains("barrita") { role = .proteinSnack }

        // NOVA: yours → Open Food Facts → generic USDA (1) → recipe ingredients → typical for the canonical food.
        var nova: Int, novaSource: String, estimated: Bool
        if let n = override?.nova { (nova, novaSource, estimated) = (n, "your correction", false) }
        else if let n = x.offNova, (1...4).contains(n) { (nova, novaSource, estimated) = (n, "Open Food Facts", false) }
        else if x.source == "usda" { (nova, novaSource, estimated) = (1, "USDA generic food", false) }
        else if !x.ingredientNovas.isEmpty { (nova, novaSource, estimated) = (min(4, max(x.ingredientNovas.max()!, 3)), "estimated from the recipe's ingredients", true) }
        else if let c = canon { (nova, novaSource, estimated) = (packaged(c.nova, x), "estimated (typical \(c.name.lowercased()))", true) }
        else { (nova, novaSource, estimated) = (role == .treat || role == .proteinSnack ? 4 : 3, "estimated (no data)", true) }
        if estimated && src != .user { conf = min(conf, 0.85) }
        return Result(canonical: canon?.id, role: role, nova: nova, novaSource: novaSource, novaEstimated: estimated, state: x.state,
                      confidence: conf, roleSource: src, why: why)
    }

    /// Roles that look alike in a database category or a macro profile: jam is "sweets", mayonnaise
    /// is mostly fat, dates are mostly sugar, USDA files potatoes under vegetables.
    static func compatible(_ a: FoodRole, _ b: FoodRole) -> Bool {
        if a == b { return true }
        let families: [Set<FoodRole>] = [[.condiment, .fatSource, .treat], [.fruit, .treat], [.vegetable, .carbSide], [.proteinMain, .proteinSnack, .dairy], [.carbSide, .treat]]
        return families.contains { $0.contains(a) && $0.contains(b) }
    }

    /// A branded, cooked or seasoned product is at least NOVA 3 even when the plain food is 1.
    private static func packaged(_ typical: Int, _ x: Input) -> Int {
        let n = x.name.lowercased()
        let prepared = ["roasted", "asado", "premium", "marinado", "seasoned", "sazonado", "empanado", "breaded", "frito", "listo", "ready"].contains(where: { n.contains($0) })
        return prepared && typical < 3 ? 3 : typical
    }

    /// Meals a food belongs in by its canonical food, when it has a usual one.
    static func bands(_ c: String?) -> Set<MealBand> { c.flatMap { byID[$0]?.bands } ?? [] }
}
