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
