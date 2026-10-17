import Charts
import SwiftData
import SwiftUI

// Habits and deeper insights: a weekly habit score, when you eat, and which foods
// bring the most of each nutrient.

/// The last 7 finished days, scored out of 100.
struct HabitScore: Equatable {
    var logging: Double          // share of days with food logged
    var calories: Double         // share of days within 10% of the (distributed) calorie target
    var protein: Double          // share of days at 90% of protein or more
    var weighIns: Double         // weigh-ins / 5, at most 1
    var total: Int { Int((logging * 35 + calories * 30 + protein * 20 + weighIns * 15).rounded()) }
}

extension ModelContext {
    /// The score for the 7 days ending `end` (yesterday by default: today isn't over).
    func habitScore(ending end: String = addDays(dayKey(), -1)) -> HabitScore? {
        guard let profile = try? fetch(FetchDescriptor<Profile>()).first else { return nil }
        let start = addDays(end, -6)
        let entries = (try? fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.day >= start && $0.day <= end }))) ?? []
        let weighed = (try? fetchCount(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.day >= start && $0.day <= end }))) ?? 0
        let byDay = Dictionary(grouping: entries, by: \.day).mapValues { $0.reduce(Nutrients.zero) { $0 + $1.nutrients } }
        var cal = 0.0, pro = 0.0
        for d in days(from: start, through: end) {
            guard let n = byDay[d], let base = targets(on: d)?.targets else { continue }
            let t = profile.adjust(base, on: d)
            if t.kcal > 0, abs(n.kcal - t.kcal) <= t.kcal * 0.1 { cal += 1 }
            if t.protein > 0, n.protein >= t.protein * 0.9 { pro += 1 }
        }
        return HabitScore(logging: Double(byDay.count) / 7, calories: cal / 7, protein: pro / 7, weighIns: min(1, Double(weighed) / 5))
    }
}

/// Dashboard and Insights: the score as a ring, what it's made of, and last week's for comparison.
struct HabitCard: View {
    @Environment(\.modelContext) private var ctx
    @Query private var recent: [FoodEntry]                       // only so the card refreshes when you log

    init() {
        let from = addDays(dayKey(), -15)
        _recent = Query(filter: #Predicate<FoodEntry> { $0.day >= from })
    }

    var body: some View {
        let now = ctx.habitScore(), before = ctx.habitScore(ending: addDays(dayKey(), -8))
        Card(title: "Habits, last 7 days", systemImage: "checkmark.seal") {
            if let s = now {
                HStack(spacing: Space.l) {
                    ZStack {
                        Ring(progress: Double(s.total) / 100, color: scoreColor(s.total), lineWidth: 10)
                        VStack(spacing: -2) {
                            Text("\(s.total)").font(.numberLarge).monospacedDigit()
                            Text("of 100").font(.fine).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 96, height: 96)
                    VStack(spacing: Space.s) {
                        part("Logging", s.logging, palette.accent)
                        part("Calories", s.calories, Macro.calories.color)
                        part("Protein", s.protein, Macro.protein.color)
                        part("Weigh-ins", s.weighIns, Macro.carbs.color)
                    }
                }
                if let b = before {
                    let diff = s.total - b.total
                    Text(diff == 0 ? "Same as the week before." : "\(diff > 0 ? "+" : "−")\(abs(diff)) on the week before (\(b.total)).")
                        .font(.note).foregroundStyle(diff >= 0 ? palette.good : palette.warn)
                }
            }
        }
    }

    private func part(_ name: String, _ v: Double, _ c: Color) -> some View {
        HStack(spacing: Space.s) {
            Text(name).font(.label).frame(width: 66, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(c.opacity(0.16))
                    Capsule().fill(c).frame(width: max(6, g.size.width * v)).opacity(v > 0 ? 1 : 0)
                }
            }
            .frame(height: 7)
            Text("\(Int((v * 100).rounded()))%").font(.fine).monospacedDigit().foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
        }
    }

    private func scoreColor(_ s: Int) -> Color { s >= 80 ? palette.good : s >= 55 ? Macro.fat.color : palette.warn }
}

/// When you eat: average calories by hour, and your eating window.
struct NutrientTimingCard: View {
    let entries: [FoodEntry]                     // the period's entries (imported day totals are left out)
    let energy: EnergyUnit

    var body: some View {
        let own = entries.filter { $0.foodKey != "import" && $0.day < dayKey() }
        let days = Set(own.map(\.day)).count
        Card(title: "When you eat", systemImage: "clock") {
            if days < 3 {
                Text("Log a few full days to see when your calories come in.").foregroundStyle(.secondary)
            } else {
                let cal = Calendar.current
                let byHour = Dictionary(grouping: own) { cal.component(.hour, from: $0.time) }.mapValues { $0.reduce(0) { $0 + $1.nutrients.kcal } / Double(days) }
                let perDay = Dictionary(grouping: own, by: \.day)
                let firsts = perDay.values.compactMap { $0.map(\.time).min() }.map { minutes($0) }
                let lasts = perDay.values.compactMap { $0.map(\.time).max() }.map { minutes($0) }
                let late = own.filter { cal.component(.hour, from: $0.time) >= 21 }.reduce(0) { $0 + $1.nutrients.kcal }
                let total = own.reduce(0) { $0 + $1.nutrients.kcal }
                Chart(0..<24, id: \.self) { h in
                    BarMark(x: .value("Hour", h), y: .value("kcal", byHour[h] ?? 0))
                        .foregroundStyle(Meal(time: cal.date(bySettingHour: h, minute: 30, second: 0, of: Date())!).color).cornerRadius(Radius.xs)
                }
                .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) { v in AxisValueLabel { if let h = v.as(Int.self) { Text("\(h):00") } } } }
                .numberYAxis()
                .indexTip(count: 24, title: { h in String(format: "%02d:00–%02d:00", h, (h + 1) % 24) }) { h in
                    [TipRow(label: "Average", value: "\(number(byHour[h] ?? 0)) kcal", color: Macro.calories.color)]
                }
                .frame(height: 140)
                HStack {
                    stat(clock(avg(firsts)), "First bite")
                    Spacer()
                    stat(clock(avg(lasts)), "Last bite")
                    Spacer()
                    stat("\(Int((total > 0 ? late / total * 100 : 0).rounded()))%", "After 21:00")
                }
            }
        }
    }

    private func minutes(_ d: Date) -> Int { let c = Calendar.current.dateComponents([.hour, .minute], from: d); return (c.hour ?? 0) * 60 + (c.minute ?? 0) }
    private func avg(_ xs: [Int]) -> Int { xs.isEmpty ? 0 : xs.reduce(0, +) / xs.count }
    private func clock(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }

    private func stat(_ v: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: Space.hairline) {
            Text(v).font(.numberMedium).monospacedDigit()
            Text(label).font(.note).foregroundStyle(.secondary)
        }
    }
}

/// Which foods bring the most of a nutrient over the period.
struct TopContributorsCard: View {
    let entries: [FoodEntry]
    let energy: EnergyUnit
    @State private var nutrient: NutrientKey = .kcal

    var body: some View {
        let own = entries.filter { $0.foodKey != "import" }
        let groups = Dictionary(grouping: own) { $0.foodKey ?? "quick:\($0.name)" }
        let rows = groups.map { _, es in (name: es[0].name, brand: es[0].brand, total: es.reduce(0) { $0 + nutrient.value($1.nutrients) }, times: es.count) }
            .filter { $0.total > 0 }.sorted { $0.total > $1.total }
        let all = rows.reduce(0) { $0 + $1.total }
        Card(title: "Top contributors", systemImage: "list.number") {
            Picker("Nutrient", selection: $nutrient) {
                ForEach(NutrientKey.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu).labelsHidden().fixedSize()
            if rows.isEmpty {
                Text(nutrient.isMicro ? "No logged foods have \(nutrient.label.lowercased()) data in this period." : "Foods you log show up here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows.prefix(8).enumerated()), id: \.offset) { i, r in
                    HStack(spacing: Space.m) {
                        Text("\(i + 1)").font(.label).foregroundStyle(.secondary).frame(width: 18)
                        VStack(alignment: .leading, spacing: Space.hairline) {
                            Text(r.name).font(.secondaryEmphasis).lineLimit(1)
                            Text("\(r.times)× \(r.brand.map { "· \($0)" } ?? "")").font(.note).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(nutrient.format(r.total, energy)).font(.secondaryEmphasis).monospacedDigit()
                        Text("\(Int((all > 0 ? r.total / all * 100 : 0).rounded()))%").font(.note).foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
    }
}

/// A nutrient you can rank foods by.
enum NutrientKey: String, CaseIterable, Identifiable {
    case kcal, protein, fat, carbs, fiber, sugar, satFat, sodium
    var id: String { rawValue }
    var label: String {
        switch self {
        case .kcal: return "Calories"
        case .protein: return "Protein"
        case .fat: return "Fat"
        case .carbs: return "Carbs"
        case .fiber: return "Fibre"
        case .sugar: return "Sugar"
        case .satFat: return "Saturated fat"
        case .sodium: return "Sodium"
        }
    }
    var isMicro: Bool { ![.kcal, .protein, .fat, .carbs].contains(self) }
    func value(_ n: Nutrients) -> Double {
        switch self {
        case .kcal: return n.kcal
        case .protein: return n.protein
        case .fat: return n.fat
        case .carbs: return n.carbs
        case .fiber: return n.fiber ?? 0
        case .sugar: return n.sugar ?? 0
        case .satFat: return n.satFat ?? 0
        case .sodium: return n.sodium ?? 0
        }
    }
    func format(_ v: Double, _ e: EnergyUnit) -> String {
        switch self {
        case .kcal: return e.format(v)
        case .sodium: return "\(number(v)) mg"
        default: return "\(number(v, digits: v < 10 ? 1 : 0)) g"
        }
    }
}
