import Foundation
import SwiftData
import SwiftUI

// Saved meals (log several foods in one tap) and day notes (with a "partially logged" flag
// that keeps a patchy day out of the expenditure maths).

struct SavedItem: Codable, Hashable {
    var foodKey: String?
    var name: String
    var brand: String?
    var amount: Double
    var unit: String
    var grams: Double
    var nutrients: Nutrients
}

@Model final class SavedMeal {
    var syncID: String = ""
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var name: String
    var items: [SavedItem]
    var useCount: Int = 0
    var lastUsed: Date?
    var createdAt: Date = Date()

    init(name: String, items: [SavedItem]) { self.name = name; self.items = items }

    var total: Nutrients { items.reduce(Nutrients.zero) { $0 + $1.nutrients } }
}

@Model final class DayNote {
    var syncID: String = ""
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var day: String
    var text: String
    var partial: Bool
    var waterEvent: Bool = false            // salty meal, creatine start, travel, a big carb day: scale jump is water

    init(day: String, text: String = "", partial: Bool = false) { self.day = day; self.text = text; self.partial = partial }
}

extension ModelContext {
    func saveMeal(_ name: String, from entries: [FoodEntry]) {
        insert(SavedMeal(name: name, items: entries.map {
            SavedItem(foodKey: $0.foodKey, name: $0.name, brand: $0.brand, amount: $0.amount, unit: $0.unit, grams: $0.grams, nutrients: $0.nutrients)
        }))
        commit()
    }

    /// Log a saved meal's foods at a time on a day.
    func log(_ meal: SavedMeal, day: String, time: Date) {
        for (i, it) in meal.items.enumerated() {
            insert(FoodEntry(day: day, time: time.addingTimeInterval(Double(i)), name: it.name, brand: it.brand, foodKey: it.foodKey,
                             amount: it.amount, unit: it.unit, grams: it.grams, nutrients: it.nutrients))
        }
        meal.useCount += 1; meal.lastUsed = Date()
        commit()
    }

    func note(on day: String) -> DayNote? {
        try? fetch(FetchDescriptor<DayNote>(predicate: #Predicate { $0.day == day })).first
    }

    /// Days marked as partially logged (left out of expenditure).
    var partialDays: Set<String> {
        Set(((try? fetch(FetchDescriptor<DayNote>(predicate: #Predicate { $0.partial }))) ?? []).map(\.day))
    }
}

/// Meals are times of day (Spanish hours), so every entry has one without choosing.
enum Meal: Int, CaseIterable, Identifiable {
    case breakfast, lunch, snack, dinner
    var id: Int { rawValue }

    var label: String { ["Breakfast", "Lunch", "Merienda", "Dinner"][rawValue] }
    var icon: String { ["sunrise.fill", "sun.max.fill", "cup.and.saucer.fill", "moon.stars.fill"][rawValue] }
    var color: Color { [palette.fat, palette.calories, palette.carbs, palette.protein][rawValue] }
    /// Starts at (minutes after midnight): 05:00, 11:30, 17:00, 20:30.
    var start: Int { [300, 690, 1020, 1230][rawValue] }
    /// When something added to this meal is timed: 08:30, 14:30, 18:00, 21:30.
    var usual: (Int, Int) { [(8, 30), (14, 30), (18, 0), (21, 30)][rawValue] }

    init(time: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        self = Meal.allCases.last { m >= $0.start } ?? .dinner        // after midnight still counts as dinner
    }

    /// The time for a new entry in this meal: now, if it's this meal now and the day is today; else its usual time.
    func time(on day: String) -> Date {
        if day == dayKey(), Meal(time: Date()) == self { return Date() }
        return Calendar.current.date(bySettingHour: usual.0, minute: usual.1, second: 0, of: date(fromKey: day)) ?? Date()
    }
}

extension ModelContext {
    /// A half-logged day, fixed the MacroFactor way: your best guess of the whole day's calories.
    /// The difference is logged as one quick add (macros in the day's own proportions), and the
    /// day counts again. A rough guess is fine: it keeps the expenditure estimate honest.
    @discardableResult
    func estimateDay(_ day: String, totalKcal: Double) -> Double {
        let logged = entries(on: day).reduce(Nutrients.zero) { $0 + $1.nutrients }
        let missing = totalKcal - logged.kcal
        if missing >= 20 {
            let k = max(logged.kcal, 1)
            let (p, f, c) = logged.kcal > 200 ? (logged.protein * 4 / k, logged.fat * 9 / k, logged.carbs * 4 / k) : (0.2, 0.35, 0.45)
            let t = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: date(fromKey: day)) ?? Date()
            insert(FoodEntry(day: day, time: t, name: "Unlogged food (estimate)", brand: nil, foodKey: nil, amount: 1, unit: "", grams: 0,
                             nutrients: Nutrients(kcal: missing, protein: missing * p / 4, fat: missing * f / 9, carbs: missing * c / 4)))
        }
        note(on: day)?.partial = false
        commit()
        return max(0, missing)
    }
}

/// A food's emoji from its name (Spanish or English); a plate when nothing fits.
func foodEmoji(_ e: FoodEntry) -> String { e.isQuickAdd ? "⚡️" : foodEmoji(name: e.name, brand: e.brand) }

func foodEmoji(name: String, brand: String?) -> String {
    let n = FoodAPI.fold(name + " " + (brand ?? ""))
    let table: [(String, [String])] = [
        ("☕️", ["cafe", "coffee", "espresso", "cortado", "capuccino", "cappuccino", "latte"]),
        ("🥤", ["batido", "shake", "whey", "protein drink", "proteina liquida"]),
        ("🥛", ["leche", "milk", "kefir", "laban"]),
        ("🥣", ["avena", "oat", "cereal", "muesli", "granola", "copos"]),
        ("🍦", ["helado", "ice cream"]),
        ("🥄", ["yogur", "yogurt", "skyr", "queso fresco batido", "labneh"]),
        ("🧀", ["queso", "cheese", "mozzarella", "parmesano", "cheddar"]),
        ("🥚", ["huevo", "egg", "tortilla de patata", "omelet", "omelette"]),
        ("🍗", ["pollo", "chicken", "pavo", "turkey", "shawarma"]),
        ("🥩", ["ternera", "beef", "steak", "filete", "carne", "lomo", "cerdo", "pork", "cordero", "lamb"]),
        ("🥓", ["bacon", "beicon", "panceta"]),
        ("🍖", ["jamon", "ham", "chorizo", "salchichon", "fuet", "salami"]),
        ("🌭", ["salchicha", "sausage", "hot dog"]),
        ("🍔", ["hamburguesa", "burger"]),
        ("🐟", ["atun", "tuna", "salmon", "merluza", "bacalao", "pescado", "fish", "sardina", "boqueron"]),
        ("🦐", ["gamba", "langostino", "shrimp", "prawn", "marisco"]),
        ("🥘", ["paella", "kabsa", "mandi", "biryani", "machboos"]),
        ("🍚", ["arroz", "rice"]),
        ("🍝", ["pasta", "espagueti", "spaghetti", "macarron", "macaroni", "noodle", "fideo", "lasana"]),
        ("🍕", ["pizza"]),
        ("🥪", ["sandwich", "bocadillo", "wrap", "kebab"]),
        ("🍞", ["pan ", "bread", "tostada", "toast", "baguette", "khubz", "pita"]),
        ("🥐", ["croissant", "bolleria", "magdalena", "muffin"]),
        ("🍫", ["chocolate", "cacao", "nutella"]),
        ("🍪", ["galleta", "cookie", "biscuit", "tortita", "rice cake"]),
        ("🍰", ["tarta", "cake", "bizcocho", "pastel", "kunafa", "baklava"]),
        ("🥔", ["patata", "potato", "papas", "fries"]),
        ("🥗", ["ensalada", "salad", "lechuga", "lettuce", "fattoush", "tabbouleh"]),
        ("🥦", ["brocoli", "broccoli", "verdura", "vegetable", "espinaca", "spinach"]),
        ("🍅", ["tomate", "tomato", "gazpacho", "salmorejo"]),
        ("🥑", ["aguacate", "avocado", "guacamole"]),
        ("🫘", ["lenteja", "lentil", "garbanzo", "chickpea", "alubia", "bean", "hummus", "falafel", "foul"]),
        ("🍌", ["platano", "banana"]),
        ("🍎", ["manzana", "apple"]),
        ("🍊", ["naranja", "orange", "mandarina"]),
        ("🍓", ["fresa", "strawberr", "arandano", "blueberr", "frambuesa"]),
        ("🍇", ["uva", "grape"]),
        ("🌴", ["datil", "date ", "dates", "tamr"]),
        ("🥜", ["almendra", "almond", "nuez", "nut", "cacahuete", "peanut", "anacardo", "pistacho"]),
        ("🫒", ["aceite", "olive", "oliva", "aceituna"]),
        ("🍯", ["miel", "honey", "mermelada", "jam"]),
        ("🧃", ["zumo", "juice"]),
        ("🥫", ["salsa", "sauce", "ketchup", "mayonesa", "mayo", "alioli"]),
        ("🍺", ["cerveza", "beer"]),
        ("🍷", ["vino", "wine"]),
        ("💧", ["agua", "water"]),
        ("🥤", ["refresco", "cola", "soda", "red bull", "monster", "bebida"]),
    ]
    for (emoji, words) in table where words.contains(where: { n.contains($0) }) { return emoji }
    return "🍽️"
}
