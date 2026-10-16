import Foundation

// What you usually eat, learned from your food log: meal slots and times, frequent foods and
// portions per slot (and weekday), foods you eat together, protein per meal, fibre, and where days
// tend to miss their targets. Recent weeks count more (half-life 30 days). Deterministic.

struct LoggedFood: Equatable {
    var day: String
    var weekday: Int                 // 1 Sunday … 7 Saturday
    var minute: Int                  // minutes after midnight (local)
    var key: String                  // food key
    var name: String
    var grams: Double
    var kcal: Double, protein: Double, fat: Double, carbs: Double, fibre: Double
}

struct DayTarget: Equatable { var kcal: Double; var protein: Double; var fat: Double; var carbs: Double }

struct EatingProfile: Equatable {
    struct Slot: Equatable {
        var index: Int
        var typicalMinute: Int
        var protein: Double              // g, weighted average
        var kcal: Double
        var foods: [UsualFood]           // most frequent first
    }
    struct UsualFood: Equatable {
        var key: String, name: String
        var score: Double                // recency-weighted count
        var grams: Double                // typical portion (weighted median)
        var weekdays: Set<Int>           // the days you usually have it (if not every day)
    }
    struct Pair: Equatable { var a: String, b: String, times: Int }
    struct Miss: Equatable { var what: String; var detail: String }

    var daysUsed: Int
    var mealsPerDay: Int
    var slots: [Slot]
    var together: [Pair]
    var fibrePerDay: Double
    var proteinPerDay: Double
    var misses: [Miss]
    var enoughData: Bool { daysUsed >= 14 }

    static let halfLifeDays = 30.0
    static let newMealGapMinutes = 90

    static func learn(_ logs: [LoggedFood], today: String, targets: [String: DayTarget] = [:], days: Int = 120) -> EatingProfile {
        let from = addDaysKey(today, -days)
        let foods = logs.filter { $0.day >= from && $0.day < today && $0.grams > 0 && !$0.key.isEmpty }
        let byDay = Dictionary(grouping: foods, by: \.day)
        func weight(_ day: String) -> Double { pow(0.5, Double(daysBetweenKeys(day, today)) / halfLifeDays) }

        // Meals: foods within 90 minutes of each other are one meal.
        var mealsOfDay: [String: [[LoggedFood]]] = [:]
        for (d, items) in byDay.sorted(by: { $0.key < $1.key }) {
            var meals: [[LoggedFood]] = []
            for f in items.sorted(by: { ($0.minute, $0.key) < ($1.minute, $1.key) }) {
                if let last = meals.last?.last, f.minute - last.minute <= newMealGapMinutes { meals[meals.count - 1].append(f) } else { meals.append([f]) }
            }
            mealsOfDay[d] = meals
        }
        let counts = mealsOfDay.values.map(\.count).sorted()
        let mealsPerDay = counts.isEmpty ? 4 : max(1, counts[counts.count / 2])

        // Slot k on each day = its k-th meal (days with a different count are mapped by time).
        var slotMeals = [[(day: String, meal: [LoggedFood])]](repeating: [], count: mealsPerDay)
        for (d, meals) in mealsOfDay.sorted(by: { $0.key < $1.key }) {
            for (mi, m) in meals.enumerated() {
                let k: Int
                if meals.count == mealsPerDay { k = mi }
                else { k = min(mealsPerDay - 1, Int(Double(m[0].minute) / 1440 * Double(mealsPerDay))) }
                slotMeals[k].append((d, m))
            }
        }
        var slots: [Slot] = []
        for k in 0..<mealsPerDay {
            let ms = slotMeals[k]
            let tw = ms.reduce(0) { $0 + weight($1.day) }
            let minutes = ms.map { $0.meal[0].minute }.sorted()
            var scores: [String: (name: String, score: Double, portions: [(Double, Double)], weekdays: [Int])] = [:]
            // (ms is already in day order, so sums are always added in the same order)
            for (d, m) in ms {
                for f in m {
                    var e = scores[f.key] ?? (f.name, 0, [], [])
                    e.score += weight(d); e.portions.append((f.grams, weight(d))); e.weekdays.append(f.weekday)
                    scores[f.key] = e
                }
            }
            let usual = scores.map { key, e -> UsualFood in
                let sorted = e.portions.sorted { $0.0 < $1.0 }
                let half = sorted.reduce(0) { $0 + $1.1 } / 2
                var acc = 0.0, med = sorted.first?.0 ?? 0
                for p in sorted { acc += p.1; if acc >= half { med = p.0; break } }
                let wds = Set(e.weekdays)
                return UsualFood(key: key, name: e.name, score: e.score, grams: (med / 5).rounded() * 5, weekdays: wds.count >= 6 ? [] : wds)
            }.sorted { ($0.score, $1.key) > ($1.score, $0.key) }
            let protein = tw > 0 ? ms.reduce(0) { $0 + $1.meal.reduce(0) { $0 + $1.protein } * weight($1.day) } / tw : 0
            let kcal = tw > 0 ? ms.reduce(0) { $0 + $1.meal.reduce(0) { $0 + $1.kcal } * weight($1.day) } / tw : 0
            slots.append(Slot(index: k, typicalMinute: minutes.isEmpty ? 480 + k * 240 : minutes[minutes.count / 2], protein: protein, kcal: kcal, foods: Array(usual.prefix(12))))
        }

        // Foods eaten together (same meal) at least three times.
        var pairs: [String: Int] = [:], names: [String: String] = [:]
        for (_, meals) in mealsOfDay.sorted(by: { $0.key < $1.key }) { for m in meals {
            let keys = Array(Set(m.map(\.key))).sorted()
            for f in m { names[f.key] = f.name }
            for i in 0..<keys.count { for j in (i + 1)..<keys.count { pairs["\(keys[i])|\(keys[j])", default: 0] += 1 } }
        } }
        let together = pairs.filter { $0.value >= 3 }.map { kv -> Pair in
            let p = kv.key.split(separator: "|").map(String.init); return Pair(a: names[p[0]] ?? p[0], b: names[p[1]] ?? p[1], times: kv.value)
        }.sorted { ($0.times, $1.a) > ($1.times, $0.a) }

        // Daily totals and where they miss.
        let dayTotals = byDay.mapValues { fs in (kcal: fs.reduce(0) { $0 + $1.kcal }, protein: fs.reduce(0) { $0 + $1.protein }, fat: fs.reduce(0) { $0 + $1.fat }, fibre: fs.reduce(0) { $0 + $1.fibre }) }
        let n = Double(max(dayTotals.count, 1))
        let ordered = dayTotals.sorted { $0.key < $1.key }.map(\.value)
        let fibre = ordered.reduce(0) { $0 + $1.fibre } / n
        let protein = ordered.reduce(0) { $0 + $1.protein } / n
        var misses: [Miss] = []
        let withTargets = dayTotals.compactMap { d, t in targets[d].map { (t, $0) } }
        if !withTargets.isEmpty {
            let pShort = withTargets.filter { $0.0.protein < $0.1.protein * 0.9 }.count
            if Double(pShort) >= Double(withTargets.count) * 0.4 { misses.append(.init(what: "protein", detail: "Protein under target on \(pShort) of \(withTargets.count) days.")) }
            let fatOver = withTargets.filter { $0.0.fat > $0.1.fat * 1.15 }.count
            if Double(fatOver) >= Double(withTargets.count) * 0.4 { misses.append(.init(what: "fat", detail: "Fat over target on \(fatOver) of \(withTargets.count) days.")) }
        }
        if let low = slots.min(by: { $0.protein < $1.protein }), slots.count >= 3, low.protein < 20 {
            misses.append(.init(what: "protein spread", detail: "Meal \(low.index + 1) (around \(low.typicalMinute / 60):\(String(format: "%02d", low.typicalMinute % 60))) usually has under 20 g protein."))
        }
        let kcalAvg = ordered.reduce(0) { $0 + $1.kcal } / n
        if kcalAvg > 0, fibre < 14 * kcalAvg / 1000 * 0.7 { misses.append(.init(what: "fibre", detail: "Fibre is usually low for how much you eat.")) }
        return EatingProfile(daysUsed: byDay.count, mealsPerDay: mealsPerDay, slots: slots, together: Array(together.prefix(10)),
                             fibrePerDay: fibre, proteinPerDay: protein, misses: misses)
    }
}

// Day keys without the app's helpers (the engine stays standalone): Gregorian, UTC, deterministic.
private let utcCal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
private func dateOfKey(_ k: String) -> Date {
    let p = k.split(separator: "-").compactMap { Int($0) }
    guard p.count == 3 else { return Date(timeIntervalSince1970: 0) }
    return utcCal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))!
}
func daysBetweenKeys(_ a: String, _ b: String) -> Int { utcCal.dateComponents([.day], from: dateOfKey(a), to: dateOfKey(b)).day ?? 0 }
func addDaysKey(_ k: String, _ n: Int) -> String {
    let c = utcCal.dateComponents([.year, .month, .day], from: utcCal.date(byAdding: .day, value: n, to: dateOfKey(k))!)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
}
