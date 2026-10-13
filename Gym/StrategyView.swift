import SwiftData
import SwiftUI

/// Your goal and the targets that come from it.
struct StrategyView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @Query(sort: \TargetSet.fromDay, order: .reverse) private var targetSets: [TargetSet]
    @Query(filter: #Predicate<Program> { $0.isActive }) private var programs: [Program]
    @State private var editing = false

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
                        row("Targets", g.mode == "coached" ? "Coached: updated at each weekly check-in" : "Manual")
                    }
                    Card(title: "Daily targets", systemImage: "chart.bar") {
                        TargetsGrid(targets: t.targets, energy: p.energy)
                        Text("Since \(relative(t.fromDay)), based on an expenditure of \(p.energy.format(t.expenditure)).")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Card(title: "Weekly check-in", systemImage: "calendar.badge.clock") {
                        Text("Once a week the app compares what you ate with how your trend weight moved, updates your expenditure, and suggests new targets. Arrives in phase 4.")
                            .foregroundStyle(.secondary)
                    }
                    Button("Change goal…") { editing = true }.controlSize(.large)
                }
            }
            .padding(24)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.pageBackground)
        .navigationTitle("Strategy")
        .sheet(isPresented: $editing) { GoalEditor() }
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
        expenditure = ctx.targets()?.expenditure ?? draft.expenditure
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
