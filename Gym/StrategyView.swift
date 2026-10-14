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

    @State private var editingGoalWeight = false
    @Query(sort: \WeightEntry.day) private var weighIns: [WeightEntry]

    /// "At −0,62 kg a week you'll reach 100 kg around 12 Mar 2027."
    private func projection(_ p: Profile, _ goal: Double) -> String? {
        let series = trendSeries(weighIns.map { DayValue(day: $0.day, value: $0.kg) }, through: dayKey())
        guard let now = series.last?.trend else { return nil }
        if abs(now - goal) < 0.1 { return "You're there." }
        guard let wk = weeklyTrendChange(series), let d = goalDate(trendKg: now, goalKg: goal, weeklyKg: wk) else {
            return nil
        }
        return "At \(signed(p.weight, wk)) a week: \(p.weight.format(goal)) around \(d.formatted(.dateTime.day().month(.abbreviated).year().locale(appLocale)))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let p = profiles.first, let g = programs.first, let t = targetSets.first(where: { $0.fromDay <= dayKey() }) {
                    Card(title: "Goal", systemImage: "target") {
                        Text(g.goalValue.label).font(.number(26))
                        Text(goalDetail(g, p)).foregroundStyle(.secondary)
                        Divider()
                        row("Diet", g.dietValue.label)
                        row("Protein", "\(g.proteinValue.label) · \(number(g.proteinValue.gramsPerKg, digits: 1)) g/kg")
                        row("Started", date(fromKey: g.startDay).formatted(.dateTime.day().month(.wide).year().locale(appLocale)))
                        HStack {
                            Text("Goal weight").foregroundStyle(.secondary)
                            Spacer()
                            Button(p.goalWeightKg.map { p.weight.format($0) } ?? "Set…") { editingGoalWeight = true }
                                .buttonStyle(.borderless)
                        }
                        if let gw = p.goalWeightKg, let proj = projection(p, gw) {
                            Text(proj).font(.callout).foregroundStyle(palette.good)
                        }
                    }
                    Card(title: "Daily targets", systemImage: "chart.bar") {
                        HStack(spacing: 20) {
                            MacroDonut(targets: t.targets).frame(width: 110, height: 110)
                            TargetsGrid(targets: t.targets, energy: p.energy)
                        }
                        Text("Since \(relative(t.fromDay)), based on an expenditure of \(p.energy.format(t.expenditure)).")
                            .font(.callout).foregroundStyle(.secondary)
                        if p.hasDistribution {
                            let today = p.adjust(t.targets, on: dayKey())
                            Text("That's your daily average. Today: \(p.energy.format(today.kcal)), \(number(today.carbs)) g carbs.")
                                .font(.callout.weight(.semibold)).foregroundStyle(palette.accent)
                        }
                    }
                    DistributionCard(profile: p, targets: t.targets)
                    Card(title: "Weekly check-in", systemImage: "calendar.badge.clock") {
                        Picker("Targets", selection: Binding(get: { g.mode }, set: { m in
                            if m == "manual" { manual = true } else { g.mode = "coached"; ctx.commit(); checkingIn = true }
                        })) {
                            Text("Coached").tag("coached")
                            Text("Manual").tag("manual")
                        }
                        .pickerStyle(.segmented)
                        Text(g.mode == "coached"
                             ? "Once a week the app compares what you ate with how your trend weight moved, updates your expenditure, and suggests targets for the week ahead."
                             : "You set your own targets. Check-ins still show how your week went.")
                            .font(.callout).foregroundStyle(.secondary)
                        Picker("Check-in day", selection: Binding(get: { g.checkInWeekday }, set: { g.checkInWeekday = $0; ctx.commit() })) {
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
            .padding(pagePadding)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .navigationTitle("Strategy")
        .sheet(isPresented: $editing) { GoalEditor() }
        .sheet(isPresented: $checkingIn) { CheckInView() }
        .sheet(isPresented: $manual) { ManualTargetsView() }
        .sheet(isPresented: $editingGoalWeight) { if let p = profiles.first { GoalWeightSheet(profile: p) } }
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
                        .foregroundStyle(fast ? Color.secondary : high ? Color.white : Color.primary)
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
                    Text("Ate less (or more) earlier in the week? The difference is spread over the days left, up to 20% a day.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func set(_ wd: Int, high: Bool, fast: Bool) {
        var h = profile.highDaySet, f = profile.fastDaySet
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
