import SwiftData
import SwiftUI

/// Your goal and the targets that come from it.
struct StrategyView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @Query(sort: \TargetSet.fromDay, order: .reverse) private var targetSets: [TargetSet]
    @Query(filter: #Predicate<Program> { $0.isActive }) private var programs: [Program]
    @State private var editing = false
    @State private var checkingIn = false
    @State private var manual = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let p = profiles.first, let g = programs.first, let t = targetSets.first(where: { $0.fromDay <= dayKey() }) {
                    Card(title: "Goal", systemImage: "target") {
                        Text(g.goalValue.label).font(.title2.bold())
                        Text(goalDetail(g, p)).foregroundStyle(.secondary)
                        Divider()
                        row("Diet", g.dietValue.label)
                        row("Protein", "\(g.proteinValue.label) · \(number(g.proteinValue.gramsPerKg, digits: 1)) g/kg")
                        row("Started", date(fromKey: g.startDay).formatted(.dateTime.day().month(.wide).year().locale(appLocale)))
                    }
                    Card(title: "Daily targets", systemImage: "chart.bar") {
                        TargetsGrid(targets: t.targets, energy: p.energy)
                        Text("Since \(relative(t.fromDay)), based on an expenditure of \(p.energy.format(t.expenditure)).")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Card(title: "Weekly check-in", systemImage: "calendar.badge.clock") {
                        Picker("Targets", selection: Binding(get: { g.mode }, set: { m in
                            if m == "manual" { manual = true } else { g.mode = "coached"; try? ctx.save(); checkingIn = true }
                        })) {
                            Text("Coached").tag("coached")
                            Text("Manual").tag("manual")
                        }
                        .pickerStyle(.segmented)
                        Text(g.mode == "coached"
                             ? "Once a week the app compares what you ate with how your trend weight moved, updates your expenditure, and suggests targets for the week ahead."
                             : "You set your own targets. Check-ins still show how your week went.")
                            .font(.callout).foregroundStyle(.secondary)
                        Picker("Check-in day", selection: Binding(get: { g.checkInWeekday }, set: { g.checkInWeekday = $0; try? ctx.save() })) {
                            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in
                                Text(weekdayName(d)).tag(d)
                            }
                        }
                        HStack {
                            if ctx.dueCheckIn != nil {
                                Button("Check in now") { checkingIn = true }.buttonStyle(.borderedProminent)
                            } else {
                                Text("Next check-in: \(nextCheckIn(g))").foregroundStyle(.secondary)
                                Spacer()
                                Button("Check in early") { checkingIn = true }
                            }
                        }
                    }
                    HStack {
                        Button("Change goal…") { editing = true }
                        if g.mode == "manual" { Button("Edit targets…") { manual = true } }
                    }
                    .controlSize(.large)
                }
            }
            .padding(24)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.pageBackground)
        .navigationTitle("Strategy")
        .sheet(isPresented: $editing) { GoalEditor() }
        .sheet(isPresented: $checkingIn) { CheckInView() }
        .sheet(isPresented: $manual) { ManualTargetsView() }
    }

    private func nextCheckIn(_ g: Program) -> String {
        var d = addDays(dayKey(), 1)
        while Calendar(identifier: .gregorian).component(.weekday, from: date(fromKey: d)) != g.checkInWeekday { d = addDays(d, 1) }
        return date(fromKey: d).formatted(.dateTime.weekday(.wide).day().month(.wide).locale(appLocale))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}

/// Change goal, rate, diet or protein. Starts a new program with targets from today.
struct GoalEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var draft = SetupDraft()
    @State private var expenditure = 0.0
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GoalStep(draft: draft)
                    DietStep(draft: draft)
                    Card(title: "New daily targets", systemImage: "target") {
                        TargetsGrid(targets: newTargets, energy: draft.energyUnit)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Change goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
        .environment(\.locale, appLocale)       // sheets don't inherit it on the Mac
        #if os(macOS)
        .frame(width: 560, height: 720)
        #endif
        .onAppear(perform: load)
    }

    /// Keep the current expenditure estimate: only the goal changes.
    private var newTargets: Targets {
        makeTargets(expenditure: expenditure, weightKg: draft.weightKg ?? 70, sex: draft.sex, goal: draft.goal,
                    ratePercent: draft.ratePercent, diet: draft.diet, protein: draft.protein)
    }

    private func load() {
        guard !loaded, let p = ctx.profile else { return }
        loaded = true
        draft.weightUnit = p.weight; draft.energyUnit = p.energy; draft.sex = p.sexValue
        draft.weightKg = ctx.latestWeight?.kg
        expenditure = ctx.expenditureEstimates().last?.kcal ?? ctx.targets()?.expenditure ?? draft.expenditure
        if let g = ctx.activeProgram {
            draft.goal = g.goalValue; draft.diet = g.dietValue; draft.protein = g.proteinValue
            DispatchQueue.main.async { draft.ratePercent = g.ratePercent }   // after GoalStep resets it for the goal
        }
    }

    private func save() {
        ctx.startProgram(goal: draft.goal, ratePercent: draft.ratePercent, diet: draft.diet, protein: draft.protein,
                         weightKg: draft.weightKg ?? 70, expenditure: expenditure, sex: draft.sex, reason: "goal")
        dismiss()
    }
}

/// "Monday" for 2 (Calendar weekdays: 1 = Sunday).
func weekdayName(_ d: Int) -> String {
    var c = Calendar(identifier: .gregorian)
    c.locale = appLocale
    return c.weekdaySymbols[d - 1]
}
