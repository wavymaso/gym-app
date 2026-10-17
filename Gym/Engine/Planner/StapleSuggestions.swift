import Foundation

// Staples from frequency: a food you've logged on enough days lately is suggested as a staple,
// with your median portion and the meal you usually have it at. You confirm or dismiss; manual
// staples always win. Deterministic.

enum StapleSuggestions {
    struct Suggestion: Equatable {
        var key: String
        var name: String
        var days: Int                 // days logged in the window
        var grams: Double             // median portion at that meal (a day's entries at that meal added up)
        var band: MealBand            // the meal you have it at most
    }

    /// Foods logged on ≥ `minDays` of the last `window` days (today excluded), not already a staple
    /// and not dismissed. Most frequent first.
    static func suggest(_ logs: [LoggedFood], today: String, window: Int = 28, minDays: Int = 6,
                        staples: Set<String> = [], dismissed: Set<String> = []) -> [Suggestion] {
        let from = addDaysKey(today, -window)
        let recent = logs.filter { $0.day >= from && $0.day < today && !$0.key.isEmpty && $0.key != "import" && !$0.key.hasPrefix("entry:") }
        var out: [Suggestion] = []
        for (key, rows) in Dictionary(grouping: recent, by: \.key) where !staples.contains(key) && !dismissed.contains(key) {
            let days = Set(rows.map(\.day))
            guard days.count >= minDays else { continue }
            let bands = Dictionary(grouping: rows, by: { MealBand.of(minute: $0.minute) }).mapValues { Set($0.map(\.day)).count }
            let band = bands.max { ($0.value, MealBand.allCases.firstIndex(of: $1.key)!) < ($1.value, MealBand.allCases.firstIndex(of: $0.key)!) }!.key
            // Portion at that meal, per day (two entries of it in one meal are one portion); the median.
            let portions = Dictionary(grouping: rows.filter { MealBand.of(minute: $0.minute) == band }, by: \.day).values.map { $0.reduce(0) { $0 + $1.grams } }.sorted()
            let median = portions.count % 2 == 1 ? portions[portions.count / 2] : (portions[portions.count / 2 - 1] + portions[portions.count / 2]) / 2
            out.append(.init(key: key, name: rows.last!.name, days: days.count, grams: (median / 5).rounded() * 5, band: band))
        }
        return out.sorted { ($0.days, $1.name) > ($1.days, $0.name) }
    }
}
