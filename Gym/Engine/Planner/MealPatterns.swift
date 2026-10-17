import Foundation

// Which foods you eat together: your log grouped into meals (entries within 45 minutes), each food
// mapped to its canonical food, then counted per meal type. Pair scores ("with rice cakes at
// breakfast you have peanut butter 2 times out of 2") steer slot filling so plans reproduce what you
// actually eat; whole combinations show in "Your usual meals" to confirm, edit or delete.
// Recent weeks count more (half-life 30 days). Deterministic.

struct UsualMeal: Codable, Equatable, Identifiable {
    var band: MealBand
    var foods: [String]               // canonical food ids, sorted
    var times: Double = 0             // recency-weighted count
    var seen = 0                      // how many meals
    var lastDay = ""
    var confirmed = false             // you confirmed or edited it
    var id: String { band.rawValue + ":" + foods.joined(separator: "+") }
}

struct MealPatterns: Equatable {
    struct Meal: Equatable { var day: String; var band: MealBand; var foods: Set<String> }
    var meals: [Meal] = []
    /// band → canonical → weighted count of meals containing it
    var single: [MealBand: [String: Double]] = [:]
    /// band → "a|b" (sorted) → weighted count of meals containing both
    var pairs: [MealBand: [String: Double]] = [:]
    var combos: [UsualMeal] = []

    static let gapMinutes = 45
    static let halfLifeDays = 30.0

    /// `canonical`: food key → canonical id (foods without one are left out).
    static func learn(_ logs: [LoggedFood], canonical: (String) -> String?, today: String) -> MealPatterns {
        var out = MealPatterns()
        let byDay = Dictionary(grouping: logs.filter { $0.day < today || $0.day == today }, by: \.day)
        for day in byDay.keys.sorted() {
            let rows = byDay[day]!.sorted { ($0.minute, $0.key) < ($1.minute, $1.key) }
            var groups: [[LoggedFood]] = []
            for r in rows {
                if let last = groups.last?.last, r.minute - last.minute <= gapMinutes { groups[groups.count - 1].append(r) } else { groups.append([r]) }
            }
            for g in groups {
                let foods = Set(g.compactMap { canonical($0.key) })
                guard !foods.isEmpty else { continue }
                out.meals.append(Meal(day: day, band: MealBand.of(minute: g[0].minute), foods: foods))
            }
        }
        var combos: [String: UsualMeal] = [:]
        for m in out.meals {
            let w = pow(0.5, Double(max(0, daysBetweenKeys(m.day, today))) / halfLifeDays)
            for f in m.foods { out.single[m.band, default: [:]][f, default: 0] += w }
            let fs = m.foods.sorted()
            for i in fs.indices { for j in fs.indices where j > i { out.pairs[m.band, default: [:]][fs[i] + "|" + fs[j], default: 0] += w } }
            if fs.count >= 2 {
                let id = m.band.rawValue + ":" + fs.joined(separator: "+")
                var c = combos[id] ?? UsualMeal(band: m.band, foods: fs)
                c.times += w; c.seen += 1; c.lastDay = max(c.lastDay, m.day)
                combos[id] = c
            }
        }
        out.combos = combos.values.sorted { ($0.times, $1.id) > ($1.times, $0.id) }
        return out
    }

    /// How strongly `b` goes with `a` at this meal: the share of meals with `a` that also had `b` (0–1).
    func association(_ a: String, _ b: String, at band: MealBand) -> Double {
        guard a != b, let na = single[band]?[a], na > 0 else { return 0 }
        let key = a < b ? a + "|" + b : b + "|" + a
        return (pairs[band]?[key] ?? 0) / na
    }

    /// How well a food fits with what's already in the meal: the best association with any of them.
    func fit(_ food: String, with others: [String], at band: MealBand) -> Double {
        others.map { association($0, food, at: band) }.max() ?? 0
    }

    /// How often a food appears at this meal (weighted meals).
    func frequency(_ food: String, at band: MealBand) -> Double { single[band]?[food] ?? 0 }
}
