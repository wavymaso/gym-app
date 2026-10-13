import Charts
import SwiftData
import SwiftUI

/// Today at a glance: what's left to eat, expenditure, weight and goal.
struct DashboardView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @Query(sort: \TargetSet.fromDay, order: .reverse) private var targetSets: [TargetSet]
    @Query(sort: \WeightEntry.day, order: .reverse) private var weights: [WeightEntry]
    @Query(filter: #Predicate<Program> { $0.isActive }) private var programs: [Program]
    @Query private var todaysEntries: [FoodEntry]
    @State private var checkingIn: Bool = {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "checkIn")       // testing only
        #else
        return false
        #endif
    }()

    init() {
        let today = dayKey()
        _todaysEntries = Query(filter: #Predicate<FoodEntry> { $0.day == today })
    }

    private var profile: Profile? { profiles.first }
    private var today: TargetSet? { targetSets.first { $0.fromDay <= dayKey() } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(appLocale)))
                    .font(.headline).foregroundStyle(.secondary)
                if let t = today, let p = profile {
                    if ctx.dueCheckIn != nil {
                        Button { checkingIn = true } label: {
                            HStack {
                                Image(systemName: "calendar.badge.clock").font(.title2)
                                VStack(alignment: .leading) {
                                    Text("Your weekly check-in is ready").font(.headline)
                                    Text("See how the week went and update your targets.").font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(16)
                            .background(Macro.calories.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                    nutritionCard(t, p.energy)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16, alignment: .top)], spacing: 16) {
                        let exp = ExpenditureSummary(ctx.expenditureEstimates())
                        Card(title: "Expenditure", systemImage: "flame") {
                            big(p.energy.format(exp?.current ?? t.expenditure))
                            if let exp, exp.series.count > 2 {
                                Sparkline(values: exp.series.suffix(60).map(\.kcal), color: Macro.calories.color)
                            }
                            Text(exp?.status ?? "Starting estimate.").font(.callout).foregroundStyle(.secondary)
                        }
                        let series = trendSeries(weights.map { DayValue(day: $0.day, value: $0.kg) }, through: dayKey())
                        Card(title: "Trend weight", systemImage: "scalemass") {
                            if let now = series.last, let w = weights.first {
                                big(p.weight.format(now.trend))
                                if series.count > 2 { Sparkline(values: series.suffix(60).map(\.trend), color: .accentColor) }
                                Text("\(weeklyTrendChange(series).map { signed(p.weight, $0) + " a week · " } ?? "")scale \(p.weight.format(w.kg)) \(relative(w.day))")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        if let g = programs.first {
                            Card(title: "Goal", systemImage: "target") {
                                big(g.goalValue.label)
                                Text(goalDetail(g, p)).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(pagePadding)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.pageBackground)
        .navigationTitle("Dashboard")
        .sheet(isPresented: $checkingIn) { CheckInView() }
    }

    private func nutritionCard(_ t: TargetSet, _ energy: EnergyUnit) -> some View {
        let eaten = todaysEntries.reduce(Nutrients.zero) { $0 + $1.nutrients }.targets
        return Card(title: "Today", systemImage: "fork.knife") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(number(energy.fromKcal(abs(t.kcal - eaten.kcal)))).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                Text("\(energy.rawValue) \(t.kcal >= eaten.kcal ? "left" : "over")").font(.title3).foregroundStyle(.secondary)
            }
            VStack(spacing: 14) {
                ForEach(Macro.allCases, id: \.self) { m in
                    MacroBar(macro: m, eaten: m.value(eaten), target: m.value(t.targets), energy: energy)
                }
            }
        }
    }

    private func big(_ s: String) -> some View {
        Text(s).font(.title2.bold()).monospacedDigit()
    }
}

func goalDetail(_ g: Program, _ p: Profile) -> String {
    guard g.goalValue != .maintain else { return "Keeping your trend weight level" }
    let kg = abs(weeklyChangeKg(goal: g.goalValue, ratePercent: g.ratePercent, weightKg: g.startWeightKg))
    return "\(percent(g.ratePercent)) a week · about \(p.weight.format(kg, digits: 2))"
}

/// "today", "yesterday", "12 Oct".
func relative(_ day: String) -> String {
    let d = date(fromKey: day)
    let cal = Calendar.current
    if cal.isDateInToday(d) { return "today" }
    if cal.isDateInYesterday(d) { return "yesterday" }
    return d.formatted(.dateTime.day().month(.abbreviated).locale(appLocale))
}

/// A small line with no axes, for the dashboard tiles.
struct Sparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        Chart(Array(values.enumerated()), id: \.offset) { p in
            LineMark(x: .value("Day", p.offset), y: .value("Value", p.element))
                .foregroundStyle(color).interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .chartYScale(domain: (lo - max(0.5, (hi - lo) * 0.15))...(hi + max(0.5, (hi - lo) * 0.15)))
        .frame(height: 44)
    }
}
