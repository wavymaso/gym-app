import SwiftData
import SwiftUI

/// Today at a glance: what's left to eat, expenditure, weight and goal.
struct DashboardView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @Query(sort: \TargetSet.fromDay, order: .reverse) private var targetSets: [TargetSet]
    @Query(sort: \WeightEntry.day, order: .reverse) private var weights: [WeightEntry]
    @Query(filter: #Predicate<Program> { $0.isActive }) private var programs: [Program]

    private var profile: Profile? { profiles.first }
    private var today: TargetSet? { targetSets.first { $0.fromDay <= dayKey() } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(appLocale)))
                    .font(.headline).foregroundStyle(.secondary)
                if let t = today, let p = profile {
                    nutritionCard(t, p.energy)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16, alignment: .top)], spacing: 16) {
                        Card(title: "Expenditure", systemImage: "flame") {
                            big(p.energy.format(t.expenditure))
                            Text("Starting estimate. It adapts to your own data once you log food and weight.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Card(title: "Weight", systemImage: "scalemass") {
                            if let w = weights.first {
                                big(p.weight.format(w.kg))
                                Text("Logged \(relative(w.day))").font(.callout).foregroundStyle(.secondary)
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
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.pageBackground)
        .navigationTitle("Dashboard")
    }

    private func nutritionCard(_ t: TargetSet, _ energy: EnergyUnit) -> some View {
        let eaten = Targets(kcal: 0, protein: 0, fat: 0, carbs: 0)       // the food log arrives in phase 2
        return Card(title: "Today", systemImage: "fork.knife") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(number(energy.fromKcal(max(0, t.kcal - eaten.kcal)))).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                Text("\(energy.rawValue) left").font(.title3).foregroundStyle(.secondary)
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
