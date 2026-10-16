import SwiftData
import SwiftUI

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
                .padding(pagePadding)
            }
            .navigationTitle("Change goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
        .appStyle()                             // sheets don't inherit these on the Mac
        #if os(macOS)
        .frame(width: 560, height: 720)
        #endif
        .onAppear(perform: load)
    }

    /// Keep the current expenditure estimate: only the goal changes.
    private var newTargets: Targets {
        makeTargets(expenditure: expenditure, weightKg: draft.weightKg ?? 70, sex: draft.sex, goal: draft.goal,
                    ratePercent: draft.ratePercent, diet: draft.diet, protein: draft.protein,
                    body: ctx.bodyInfo(guardrails: (ctx.activeProgram?.mode ?? "coached") == "coached"))
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

/// Set or clear the goal weight.
struct GoalWeightSheet: View {
    let profile: Profile
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    TextField("Goal weight", text: $text, prompt: Text(profile.weight == .kg ? "100" : "220"))
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text(profile.weight.rawValue).foregroundStyle(.secondary)
                }
                Text("Used for a projected date on your dashboard and a line on the weight chart. Your weekly targets still come from your goal and rate.")
                    .font(.callout).foregroundStyle(.secondary)
                if profile.goalWeightKg != nil {
                    Button("Remove goal weight", role: .destructive) { profile.goalWeightKg = nil; ctx.commit(); dismiss() }
                }
            }
            .themedForm()
            .navigationTitle("Goal weight")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let v = parseNumber(text) { profile.goalWeightKg = profile.weight.toKg(v); ctx.commit() }
                        dismiss()
                    }
                    .disabled(parseNumber(text).map { !(20...700).contains($0) } ?? true)
                }
            }
            .onAppear { if let g = profile.goalWeightKg { text = number(profile.weight.fromKg(g), digits: 1) } }
        }
        .appStyle()
        #if os(macOS)
        .frame(width: 420, height: 280)
        #endif
    }
}

/// More calories on training days (and/or fasting days), the same over the week.
struct DistributionCard: View {
    let profile: Profile
    let targets: Targets
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<Workout> { $0.end != nil }, sort: \Workout.start, order: .reverse) private var workouts: [Workout]

    private let order = [2, 3, 4, 5, 6, 7, 1]                    // Monday first

    var body: some View {
        Card(title: "Calorie distribution", systemImage: "calendar") {
            Text("Eat more on training days and less on the others; your week's calories stay the same.")
                .font(.callout).foregroundStyle(.secondary)
            Toggle(isOn: Binding(get: { profile.planner.highDaysFollowTraining }, set: { v in
                var s = profile.planner; s.highDaysFollowTraining = v; profile.planner = s
                if v && profile.highDayExtra == 0 { profile.highDayExtra = 250 }
                ctx.commit() })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Training days follow my training week").font(.subheadline.weight(.semibold))
                    Text(profile.planner.trainingWeekdays == nil
                         ? (profile.planner.highDaysFollowTraining ? "No training week yet (log workouts or set it in Food log → Plan), so the days below are used." : "Using the days below.")
                         : "From your training week (\(profile.planner.scheduleSet ? "set by you" : "your workouts")). Change it in Food log → Plan.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(order, id: \.self) { wd in
                    let high = profile.highDaySet.contains(wd), fast = profile.fastDaySet.contains(wd)
                    let day = dayFor(weekday: wd)
                    let k = profile.adjust(targets, on: day).kcal
                    Menu {
                        Button { set(wd, high: true, fast: false) } label: { Label("Training day (more)", systemImage: "dumbbell") }
                        Button { set(wd, high: false, fast: false) } label: { Label("Normal day", systemImage: "circle") }
                        Button { set(wd, high: false, fast: true) } label: { Label("Fasting day", systemImage: "moon.zzz") }
                    } label: {
                        VStack(spacing: 4) {
                            Text(String(weekdayName(wd).prefix(1))).font(.caption.weight(.bold))
                            Image(systemName: fast ? "moon.zzz.fill" : high ? "dumbbell.fill" : "circle").font(.caption)
                            Text(number(profile.energy.fromKcal(k))).font(.caption2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(fast ? Color.secondary : high ? palette.onData : Color.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(high ? palette.accent : (fast ? Color.raisedBackground.opacity(0.6) : Color.raisedBackground),
                                    in: RoundedRectangle(cornerRadius: 10))
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                }
            }
            if !profile.highDaySet.isEmpty {
                Stepper(value: Binding(get: { profile.highDayExtra }, set: { profile.highDayExtra = max(0, $0); ctx.commit() }), in: 0...1000, step: 50) {
                    LabeledContent("Extra on training days", value: profile.energy.format(profile.highDayExtra))
                }
            }
            if !profile.fastDaySet.isEmpty {
                Stepper(value: Binding(get: { profile.fastKcal }, set: { profile.fastKcal = max(0, $0); ctx.commit() }), in: 0...1500, step: 50) {
                    LabeledContent("Fasting day target", value: profile.energy.format(profile.fastKcal))
                }
            }
            HStack {
                if let usual = usualTrainingDays, usual != profile.highDaySet {
                    Button("Use my training days (\(usual.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }.map { String(weekdayName($0).prefix(3)) }.joined(separator: ", ")))") {
                        profile.highDays = usual.map(String.init).joined(separator: ",")
                        if profile.highDayExtra == 0 { profile.highDayExtra = 250 }
                        profile.fastDays = profile.fastDaySet.subtracting(usual).map(String.init).joined(separator: ",")
                        ctx.commit()
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                Spacer()
                if profile.hasDistribution {
                    Button("Same every day") { profile.highDays = ""; profile.fastDays = ""; ctx.commit() }.buttonStyle(.borderless).controlSize(.small)
                }
            }
            Text("Tap a day to change it. Extra calories come as carbs; protein stays the same every day.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle(isOn: Binding(get: { profile.weeklyBudget }, set: { profile.weeklyBudget = $0; ctx.commit() })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly budget").font(.subheadline.weight(.semibold))
                    Text("Ate less (or more) earlier in the week? Off by default. A small share of the difference is spread over the days left: up to 10% a day more, and at most 150 kcal a day less after a big day.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func set(_ wd: Int, high: Bool, fast: Bool) {
        // Changing a day by hand stops following the training week (starting from what it showed).
        var h = profile.highDaySet, f = profile.fastDaySet
        if profile.planner.trainingWeekdays != nil { var s = profile.planner; s.highDaysFollowTraining = false; profile.planner = s }
        h.remove(wd); f.remove(wd)
        if high { h.insert(wd) }
        if fast { f.insert(wd) }
        profile.highDays = h.sorted().map(String.init).joined(separator: ",")
        profile.fastDays = f.sorted().map(String.init).joined(separator: ",")
        if high && profile.highDayExtra == 0 { profile.highDayExtra = 250 }
        ctx.commit()
    }

    /// Weekdays you trained on at least twice in the last 4 weeks.
    private var usualTrainingDays: Set<Int>? {
        let from = Calendar.current.date(byAdding: .day, value: -28, to: Date())!
        let cal = Calendar(identifier: .gregorian)
        let counts = Dictionary(grouping: workouts.filter { $0.start >= from }) { cal.component(.weekday, from: $0.start) }.mapValues(\.count)
        let days = Set(counts.filter { $0.value >= 2 }.keys)
        return days.isEmpty || days.count >= 7 ? nil : days
    }

    /// A day key in the current week with this weekday (only its weekday matters).
    private func dayFor(weekday: Int) -> String {
        let today = Calendar(identifier: .gregorian).component(.weekday, from: Date())
        return addDays(dayKey(), weekday - today)
    }
}

/// Coached guardrail: the lowest daily target you'll be given.
struct CalorieFloorSheet: View {
    let profile: Profile
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(number(calorieFloor(profile.sexValue)), text: $text)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        Text(profile.energy.rawValue).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Coached targets never go below this, and fat stays above the minimum for normal hormone function. Leave it empty for the default (\(number(calorieFloor(profile.sexValue))) kcal). Collaborative and manual have no guardrails.")
                }
            }
            .themedForm()
            .navigationTitle("Calorie floor")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { profile.calorieFloorKcal = profile.energy.toKcal(parseNumber(text) ?? 0); ctx.commit(); dismiss() }
                }
            }
        }
        .appStyle()
        .presentationDetents([.medium])
        .onAppear { if profile.calorieFloorKcal > 0 { text = number(profile.energy.fromKcal(profile.calorieFloorKcal)) } }
    }
}
