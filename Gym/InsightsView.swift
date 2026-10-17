import Charts
import SwiftData
import SwiftUI

/// Your nutrition over time: calories against target, expenditure, macros, and how often you hit them.
struct InsightsView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @Query(sort: \TargetSet.fromDay) private var targetSets: [TargetSet]
    @Query private var entries: [FoodEntry]
    @Query private var weights: [WeightEntry]
    @State private var range = InsightRange.month

    var body: some View {
        let energy = profiles.first?.energy ?? .kcal
        let d = InsightData(ctx: ctx, entries: entries, targetSets: targetSets, days: range.days, profile: profiles.first)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Picker("", selection: $range) { ForEach(InsightRange.allCases, id: \.self) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: isPhone ? 150 : 150), spacing: Space.m, alignment: .top)], spacing: Space.m) {
                    tile("Average intake", d.avg.map { energy.format($0.kcal) } ?? "–", "\(d.logged.count) of \(d.span.count) days logged")
                    tile("On target", d.adherence.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", "Days within 10% of your calories")
                    tile("Average protein", d.avg.map { "\(number($0.protein)) g" } ?? "–",
                         d.avgTarget.map { "Target \(number($0.protein)) g" } ?? "")
                    tile("Protein target hit", d.proteinHit.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", "Days at 90% of your protein or more")
                    tile("Expenditure", d.expenditure.last.map { energy.format($0.kcal) } ?? "–",
                         d.expenditureChange.map { "\(signedKcal($0, energy)) over this period" } ?? "")
                }
                HabitCard()
                CarbPerformanceCard()
                Card(title: "Calories", systemImage: "chart.bar") {
                    Chart {
                        ForEach(d.logged, id: \.day) { x in
                            BarMark(x: .value("Day", date(fromKey: x.day), unit: .day), y: .value("Eaten", energy.fromKcal(x.n.kcal)))
                                .foregroundStyle(Macro.calories.color.opacity(0.75))
                        }
                        ForEach(d.span, id: \.self) { day in
                            if let t = d.target(day) {
                                LineMark(x: .value("Day", date(fromKey: day), unit: .day), y: .value("Target", energy.fromKcal(t.kcal)),
                                         series: .value("Line", "Target"))
                                    .foregroundStyle(Color.primary.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                    .interpolationMethod(.stepCenter)
                            }
                        }
                    }
                    .numberYAxis()
                    .dateAxis(days: d.logged.map(\.day))
                    .dayTip(days: d.logged.map(\.day)) { day in
                        guard let x = d.logged.first(where: { $0.day == day }) else { return [] }
                        return [TipRow(label: "Eaten", value: energy.format(x.n.kcal), color: Macro.calories.color)]
                            + (d.target(day).map { [TipRow(label: "Target", value: energy.format($0.kcal))] } ?? [])
                    }
                    .chartSummary("Calories eaten per day", d.logged.map { energy.fromKcal($0.n.kcal) }) { "\(number($0)) \(energy.rawValue)" }
                    .frame(height: 220)
                    legend([("Eaten", Macro.calories.color), ("Target", .primary.opacity(0.6))])
                }
                Card(title: "Expenditure and intake", systemImage: "flame") {
                    Chart {
                        ForEach(d.expenditure, id: \.day) { p in
                            LineMark(x: .value("Day", date(fromKey: p.day), unit: .day), y: .value("kcal", energy.fromKcal(p.kcal)),
                                     series: .value("Line", "Expenditure"))
                                .foregroundStyle(Macro.fat.color).lineStyle(StrokeStyle(lineWidth: 2.5))
                        }
                        ForEach(d.rollingIntake, id: \.day) { p in
                            LineMark(x: .value("Day", date(fromKey: p.day), unit: .day), y: .value("kcal", energy.fromKcal(p.value)),
                                     series: .value("Line", "Intake"))
                                .foregroundStyle(Macro.calories.color).interpolationMethod(.monotone)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .numberYAxis()
                    .dateAxis(days: d.expenditure.map(\.day))
                    .dayTip(days: d.expenditure.map(\.day)) { day in
                        (d.expenditure.first { $0.day == day }.map { [TipRow(label: "Expenditure", value: energy.format($0.kcal), color: Macro.fat.color)] } ?? [])
                        + (d.rollingIntake.first { $0.day == day }.map { [TipRow(label: "Intake (7-day)", value: energy.format($0.value), color: Macro.calories.color)] } ?? [])
                    }
                    .chartSummary("Expenditure", d.expenditure.map { energy.fromKcal($0.kcal) }) { "\(number($0)) \(energy.rawValue)" }
                    .frame(height: 200)
                    legend([("Expenditure", Macro.fat.color), ("Intake, 7-day average", Macro.calories.color)])
                    Text("When intake sits below expenditure you lose weight, above it you gain. The gap is your daily deficit or surplus.")
                        .font(.secondaryText).foregroundStyle(.secondary)
                }
                Card(title: "Macros", systemImage: "chart.bar.doc.horizontal") {
                    Chart {
                        ForEach(d.logged, id: \.day) { x in
                            ForEach([Macro.protein, .fat, .carbs], id: \.self) { m in
                                BarMark(x: .value("Day", date(fromKey: x.day), unit: .day), y: .value("kcal", m.value(x.n.targets) * (m == .fat ? 9 : 4)))
                                    .foregroundStyle(by: .value("Macro", m.label))
                            }
                        }
                    }
                    .chartForegroundStyleScale(["Protein": Macro.protein.color, "Fat": Macro.fat.color, "Carbs": Macro.carbs.color])
                    .chartYAxisLabel("kcal from each")
                    .numberYAxis()
                    .dateAxis(days: d.logged.map(\.day))
                    .dayTip(days: d.logged.map(\.day)) { day in
                        guard let x = d.logged.first(where: { $0.day == day }) else { return [] }
                        return [TipRow(label: "Calories", value: energy.format(x.n.kcal), color: Macro.calories.color)]
                            + [Macro.protein, .fat, .carbs].map { TipRow(label: $0.label, value: "\(number($0.value(x.n.targets))) g", color: $0.color) }
                    }
                    .chartSummary("Calories from protein, fat and carbs per day", d.logged.map { energy.fromKcal($0.n.kcal) }) { "\(number($0)) \(energy.rawValue)" }
                    .frame(height: 200)
                    if let a = d.avg, let t = d.avgTarget {
                        adaptiveStack {
                            ForEach([Macro.protein, .fat, .carbs], id: \.self) { m in
                                MacroBar(macro: m, eaten: m.value(a.targets), target: m.value(t), energy: energy)
                            }
                        }
                        Text("Daily averages against your average targets.").font(.note).foregroundStyle(.secondary)
                    }
                }
                EnergyBalanceCard(d: d, weights: weights, energy: energy, unit: profiles.first?.weight ?? .kg)
                WeeklyTable(d: d, weights: weights, energy: energy, unit: profiles.first?.weight ?? .kg)
                let inRange = entries.filter { $0.day >= (d.span.first ?? "") }
                let finishedInRange = inRange.filter { $0.day < dayKey() }
                if !finishedInRange.isEmpty {
                    NutrientPanel(total: finishedInRange.reduce(Nutrients.zero) { $0 + $1.nutrients }, entries: finishedInRange,
                                  days: max(1, Set(finishedInRange.map(\.day)).count), title: "Nutrients, daily average")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: Space.l, alignment: .top)], spacing: Space.l) {
                    NutrientTimingCard(entries: inRange, energy: energy)
                    TopContributorsCard(entries: inRange, energy: energy)
                }
            }
            .padding(pagePadding)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .debugScrollAnchor()
        .pageBackground()
        .navigationTitle("Insights")
        .appStyle()
    }

    private func tile(_ title: String, _ value: String, _ note: String) -> some View {
        Card(title: title) {
            Text(value).font(.numberLarge).monospacedDigit()
            Text(note).font(.note).foregroundStyle(.secondary)
        }
    }

    private func legend(_ items: [(String, Color)]) -> some View {
        HStack(spacing: Space.l) {
            ForEach(items, id: \.0) { Label($0.0, systemImage: "circle.fill").labelStyle(DotLabel(color: $0.1)) }
        }
        .font(.note).foregroundStyle(.secondary)
    }
}

func signedKcal(_ v: Double, _ e: EnergyUnit) -> String { (v >= 0 ? "+" : "−") + e.format(abs(v)) }

enum InsightRange: CaseIterable {
    case week, month, quarter, half, year
    var label: String { ["1W", "1M", "3M", "6M", "1Y"][Self.allCases.firstIndex(of: self)!] }
    var days: Int { [7, 30, 91, 182, 365][Self.allCases.firstIndex(of: self)!] }
}

/// The numbers behind the insights page, for the last `days` days.
struct InsightData {
    let span: [String]
    let logged: [(day: String, n: Nutrients)]
    let expenditure: [ExpenditurePoint]
    let rollingIntake: [DayValue]
    private let sets: [TargetSet]
    private let profile: Profile?

    init(ctx: ModelContext, entries: [FoodEntry], targetSets: [TargetSet], days n: Int, profile: Profile? = nil) {
        self.profile = profile
        let today = dayKey()
        let first = addDays(today, -(n - 1))
        let span = days(from: first, through: today)
        self.span = span
        var byDay: [String: Nutrients] = [:]
        for e in entries where e.day >= first && e.day <= today { byDay[e.day] = (byDay[e.day] ?? .zero) + e.nutrients }
        logged = span.compactMap { d in byDay[d].map { (d, $0) } }
        sets = targetSets
        expenditure = ctx.expenditureEstimates(through: today).filter { $0.day >= first }
        rollingIntake = span.indices.dropLast().compactMap { i in                  // today isn't over yet
            let window = span[max(0, i - 6)...i].compactMap { byDay[$0]?.kcal }
            return window.count >= 3 ? DayValue(day: span[i], value: window.reduce(0, +) / Double(window.count)) : nil
        }
    }

    func target(_ day: String) -> Targets? {
        guard let t = sets.last(where: { $0.fromDay <= day })?.targets else { return nil }
        return profile?.adjust(t, on: day) ?? t
    }

    var avg: Nutrients? {
        logged.isEmpty ? nil : logged.reduce(Nutrients.zero) { $0 + $1.n }.scaled(1 / Double(logged.count))
    }

    var avgTarget: Targets? {
        let ts = logged.compactMap { target($0.day) }
        guard !ts.isEmpty else { return nil }
        let k = 1 / Double(ts.count)
        return Targets(kcal: ts.reduce(0) { $0 + $1.kcal } * k, protein: ts.reduce(0) { $0 + $1.protein } * k,
                       fat: ts.reduce(0) { $0 + $1.fat } * k, carbs: ts.reduce(0) { $0 + $1.carbs } * k)
    }

    /// Share of logged days within 10% of the calorie target.
    var adherence: Double? {
        let scored = logged.compactMap { x in target(x.day).map { abs(x.n.kcal - $0.kcal) <= $0.kcal * 0.1 } }
        return scored.isEmpty ? nil : Double(scored.filter { $0 }.count) / Double(scored.count)
    }

    /// Share of logged days (not imported totals with no protein) reaching 90% of the protein target.
    var proteinHit: Double? {
        let scored = logged.filter { $0.n.protein > 0 }.compactMap { x in target(x.day).map { x.n.protein >= $0.protein * 0.9 } }
        return scored.isEmpty ? nil : Double(scored.filter { $0 }.count) / Double(scored.count)
    }

    /// Finished days only (today isn't over).
    var finished: [(day: String, n: Nutrients)] { logged.filter { $0.day < dayKey() } }

    var expenditureChange: Double? {
        guard let a = expenditure.first, let b = expenditure.last, expenditure.count > 1 else { return nil }
        return b.kcal - a.kcal
    }
}

/// Average surplus or deficit over the period, and the weight change it implies next to what your trend did.
struct EnergyBalanceCard: View {
    let d: InsightData
    let weights: [WeightEntry]
    let energy: EnergyUnit
    let unit: WeightUnit

    var body: some View {
        let exp = Dictionary(d.expenditure.map { ($0.day, $0.kcal) }, uniquingKeysWith: { a, _ in a })
        let days = d.finished.compactMap { x in exp[x.day].map { (day: x.day, balance: x.n.kcal - $0) } }
        Card(title: "Energy balance", systemImage: "plusminus") {
            if days.count < 3 {
                Text("Log a few more days to see your average surplus or deficit.").foregroundStyle(.secondary)
            } else {
                let avg = days.reduce(0) { $0 + $1.balance } / Double(days.count)
                let implied = days.reduce(0) { $0 + $1.balance } / kcalPerKg
                let series = trendSeries(weights.map { DayValue(day: $0.day, value: $0.trendKg) }, through: dayKey())
                let byDay = Dictionary(series.map { ($0.day, $0.trend) }, uniquingKeysWith: { a, _ in a })
                let actual = (byDay[days.last!.day] ?? 0) - (byDay[days.first!.day] ?? 0)
                HStack(alignment: .firstTextBaseline) {
                    Text(signedKcal(avg, energy)).font(.numberLarge).monospacedDigit().foregroundStyle(avg < 0 ? palette.good : palette.warn)
                    Text(avg < 0 ? "a day, deficit" : "a day, surplus").foregroundStyle(.secondary)
                }
                Chart(days, id: \.day) { x in
                    BarMark(x: .value("Day", date(fromKey: x.day), unit: .day), y: .value("kcal", x.balance))
                        .foregroundStyle(x.balance < 0 ? palette.good.opacity(0.85) : palette.warn.opacity(0.85))
                }
                .numberYAxis()
                .dateAxis(days: days.map(\.day))
                    .dayTip(days: days.map(\.day)) { day in
                    days.filter { $0.day == day }.map { TipRow(label: $0.balance < 0 ? "Deficit" : "Surplus", value: signedKcal($0.balance, energy),
                                                               color: $0.balance < 0 ? palette.good : palette.warn) }
                }
                .chartSummary("Daily energy balance", days.map(\.balance)) { signedKcal($0, energy) }
                .frame(height: 140)
                HStack {
                    VStack(alignment: .leading, spacing: Space.hairline) {
                        Text(signed(unit, implied)).font(.numberMedium).monospacedDigit()
                        Text("Implied by the balance").font(.note).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Space.hairline) {
                        Text(byDay.isEmpty ? "–" : signed(unit, actual)).font(.numberMedium).monospacedDigit()
                        Text("What your trend did").font(.note).foregroundStyle(.secondary)
                    }
                }
                Text("Expenditure is estimated from your weight trend and intake, so these agree over time; big gaps usually mean days logged incompletely or water swings.")
                    .font(.note).foregroundStyle(.secondary)
            }
        }
    }
}

/// Week by week (Monday to Sunday): averages, logging and the trend's change.
struct WeeklyTable: View {
    let d: InsightData
    let weights: [WeightEntry]
    let energy: EnergyUnit
    let unit: WeightUnit

    var body: some View {
        let weeks = Dictionary(grouping: d.finished) { mondayOf($0.day) }.sorted { $0.key > $1.key }.prefix(12)
        let series = trendSeries(weights.map { DayValue(day: $0.day, value: $0.trendKg) }, through: dayKey())
        let trend = Dictionary(series.map { ($0.day, $0.trend) }, uniquingKeysWith: { a, _ in a })
        Card(title: "Week by week", systemImage: "tablecells") {
            if weeks.isEmpty {
                Text("Weeks you log show up here.").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("Week").gridColumnAlignment(.leading); Text(energy.rawValue); Text("Protein"); Text("Days"); Text("Trend")
                    }
                    .font(.label).foregroundStyle(.secondary)
                    ForEach(Array(weeks), id: \.key) { monday, items in
                        let n = Double(items.count)
                        let kcal = items.reduce(0) { $0 + $1.n.kcal } / n
                        let protein = items.reduce(0) { $0 + $1.n.protein } / n
                        let end = min(addDays(monday, 6), dayKey())                 // this week: up to today
                        let change = trend[end].flatMap { e in trend[addDays(monday, -1)].map { e - $0 } }
                        GridRow {
                            Text(date(fromKey: monday).formatted(.dateTime.day().month(.abbreviated).locale(appLocale))).gridColumnAlignment(.leading)
                            Text(number(energy.fromKcal(kcal)))
                            Text(protein > 0 ? "\(number(protein)) g" : "–")
                            Text("\(items.count)/7")
                            Text(change.map { signed(unit, $0) } ?? "–")
                        }
                        .font(.secondaryText).monospacedDigit()
                    }
                }
            }
        }
    }

    private func mondayOf(_ day: String) -> String {
        // dayNumber 0 = Thursday 1970-01-01, so Monday is (n + 3) % 7 == 0.
        let n = dayNumber(day)
        return dayKey(number: n - ((n + 3) % 7 + 7) % 7)
    }
}
