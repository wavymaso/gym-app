import Foundation

// Plan adherence: for each planned meal, was it eaten as planned, swapped (eaten, but mostly other
// foods) or skipped? The plan for each meal is the last one shown before you ate it; what you logged is
// matched to the nearest planned meal by time, food by food at the canonical level (any chicken counts
// as the chicken in the plan). Context only: it never changes targets by itself.

struct PlannedMeal: Codable, Equatable {
    var index: Int
    var minute: Int
    var name: String                 // "Lunch", "Pre-workout"…
    var foods: [String]              // canonical ids (or food keys when there's none)
}

enum MealOutcome: String, Codable, CaseIterable { case asPlanned, swapped, skipped
    var label: String { ["asPlanned": "as planned", "swapped": "swapped", "skipped": "skipped"][rawValue]! }
}

enum Adherence {
    /// At least this share of a meal's planned foods eaten counts as "as planned".
    static let asPlannedShare = 0.6
    /// A meal not logged within this long after its time counts as skipped (once the day is over, all do).
    static let skipAfterMinutes = 180

    /// Each planned meal's outcome, or nil while it's still to come. `eaten`: the day's logged foods
    /// (minute, canonical id or key). `now`: minutes since midnight today (nil: the day is over).
    static func outcomes(_ planned: [PlannedMeal], eaten: [(minute: Int, food: String)], now: Int?) -> [(meal: PlannedMeal, outcome: MealOutcome?)] {
        guard !planned.isEmpty else { return [] }
        var got: [Int: Set<String>] = [:]
        for e in eaten {
            guard let m = planned.min(by: { abs($0.minute - e.minute) < abs($1.minute - e.minute) }) else { continue }
            got[m.index, default: []].insert(e.food)
        }
        return planned.sorted { $0.minute < $1.minute }.map { m in
            guard let foods = got[m.index], !foods.isEmpty else {
                if let now, now < m.minute + skipAfterMinutes { return (m, nil) }
                return (m, .skipped)
            }
            let want = Set(m.foods)
            let share = want.isEmpty ? 1 : Double(want.intersection(foods).count) / Double(want.count)
            return (m, share >= asPlannedShare ? .asPlanned : .swapped)
        }
    }

    struct Summary: Equatable {
        var counts: [MealOutcome: Int] = [:]
        var skippedMost: (name: String, times: Int)? = nil
        var days = 0
        var total: Int { counts.values.reduce(0, +) }
        var asPlannedShare: Double? { total == 0 ? nil : Double(counts[.asPlanned] ?? 0) / Double(total) }
        static func == (a: Summary, b: Summary) -> Bool { a.counts == b.counts && a.days == b.days && a.skippedMost?.name == b.skippedMost?.name && a.skippedMost?.times == b.skippedMost?.times }
    }

    /// The week: outcomes counted over the days given (meals still to come left out).
    static func summary(_ days: [[(meal: PlannedMeal, outcome: MealOutcome?)]]) -> Summary {
        var s = Summary()
        var skips: [String: Int] = [:]
        for d in days where !d.isEmpty {
            s.days += 1
            for x in d { guard let o = x.outcome else { continue }; s.counts[o, default: 0] += 1; if o == .skipped { skips[x.meal.name, default: 0] += 1 } }
        }
        if let top = skips.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }), top.value >= 2 { s.skippedMost = (top.key, top.value) }
        return s
    }
}
