import Foundation

// Days that look half-logged but weren't marked: far fewer entries than usual AND well under the
// day's target. They stay out of the expenditure estimate until you say whether they were complete.

struct LoggedDay: Equatable {
    var day: String
    var entries: Int
    var kcal: Double
    var target: Double?
}

/// Thresholds (registry: partial-day detection, grade D, our own choice).
enum PartialDayRule {
    static let entryShare = 0.5         // fewer than half your usual number of entries…
    static let kcalShare = 0.6          // …and under 60% of the day's target
    static let minHistory = 10          // need this many logged days to know what "usual" is

    /// The usual number of entries a day: the median over your logged days.
    static func usualEntries(_ days: [LoggedDay]) -> Double? {
        let counts = days.map(\.entries).filter { $0 > 0 }.sorted()
        guard counts.count >= minHistory else { return nil }
        return Double(counts[counts.count / 2])
    }

    static func suspects(_ days: [LoggedDay], usual: Double?) -> [String] {
        guard let usual else { return [] }
        return days.filter { d in
            guard d.entries > 0, let t = d.target, t > 0 else { return false }
            return Double(d.entries) < usual * entryShare && d.kcal < t * kcalShare
        }.map(\.day)
    }
}
