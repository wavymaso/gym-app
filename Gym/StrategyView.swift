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
        let series = trendSeries(weighIns.map { DayValue(day: $0.day, value: $0.trendKg) }, through: dayKey())
        guard let now = series.last?.trend else { return nil }
        if abs(now - goal) < 0.1 { return "You're there." }
        guard let wk = weeklyTrendChange(series), let d = goalDate(trendKg: now, goalKg: goal, weeklyKg: wk) else {
            return nil
        }
        return "At \(signed(p.weight, wk)) a week: \(p.weight.format(goal)) around \(d.formatted(.dateTime.day().month(.abbreviated).year().locale(appLocale)))"
    }

    @State private var selectedDay = dayKey()
    @State private var collaborative = false
    @State private var refeeding = false
    @State private var planning = false
    @State private var shadowing = false
    @State private var scaling = false
    @State private var breaking = false
    @State private var editingFloor = false

    private func styleText(_ m: String) -> String {
        switch m {
        case "collaborative": return "Collaborative"
        case "manual": return "Manual"
        default: return "Coached"
        }
    }
    @State private var showingDistribution = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let p = profiles.first, let g = programs.first, let t = targetSets.first(where: { $0.fromDay <= dayKey() }) {
                    hero(p, g)
                    weekTargets(p, t)
                    checkInCard(g)
                    Text("Program").font(.title2.bold()).padding(.top, 4)
                    settings(p, g, t)
                }
            }
            .padding(pagePadding)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .debugScrollAnchor()
        .pageBackground()
        #if os(iOS)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        #else
        .navigationTitle("Strategy")
        #endif
        .sheet(isPresented: $editing) { GoalEditor() }
        .sheet(isPresented: $checkingIn) { CheckInView() }
        .sheet(isPresented: $manual) { ManualTargetsView() }
        .sheet(isPresented: $collaborative) { ManualTargetsView(mode: "collaborative") }
        .sheet(isPresented: $refeeding) { if let p = profiles.first { RefeedSheet(profile: p) } }
        .sheet(isPresented: $planning) { if let p = profiles.first { PhasePlanSheet(profile: p) } }
        .sheet(isPresented: $shadowing) { if let p = profiles.first { ShadowSheet(profile: p) } }
        .sheet(isPresented: $scaling) { if let p = profiles.first { ScalesSheet(profile: p) } }
        .sheet(isPresented: $breaking) { if let p = profiles.first { DietBreakSheet(profile: p) } }
        .sheet(isPresented: $editingFloor) { if let p = profiles.first { CalorieFloorSheet(profile: p) } }
        .sheet(isPresented: $editingGoalWeight) { if let p = profiles.first { GoalWeightSheet(profile: p) } }
        .sheet(isPresented: $showingDistribution) {
            NavigationStack {
                ScrollView {
                    if let p = profiles.first, let t = targetSets.first(where: { $0.fromDay <= dayKey() }) {
                        DistributionCard(profile: p, targets: t.targets).padding(16)
                    }
                }
                .pageBackground()
                .navigationTitle("Calorie distribution")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingDistribution = false } } }
            }
            .appStyle()
            #if os(macOS)
            .frame(width: 560, height: 620)
            #endif
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("STRATEGY").font(.pageTitle(isPhone ? 30 : 34)).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(GlowStyle.on || palette.glass
                                 ? AnyShapeStyle(LinearGradient(colors: [.primary, palette.good], startPoint: .leading, endPoint: .trailing))
                                 : AnyShapeStyle(.primary))
            Spacer()
            Button { checkingIn = true } label: { roundIcon("calendar.badge.checkmark") }.buttonStyle(.plain)
            Button { editing = true } label: { roundIcon("slider.horizontal.3") }.buttonStyle(.plain)
        }
    }

    private func roundIcon(_ name: String) -> some View {
        Image(systemName: name).font(.headline).frame(width: 44, height: 44).modifier(GlassCapsule())
    }

    // MARK: The program

    private func hero(_ p: Profile, _ g: Program) -> some View {
        let series = trendSeries(weighIns.map { DayValue(day: $0.day, value: $0.trendKg) }, through: dayKey())
        let now = series.last?.trend
        let startKg = series.first { $0.day >= g.startDay }?.trend ?? g.startWeightKg
        let tint: Color = g.goalValue == .lose ? palette.calories : g.goalValue == .gain ? palette.protein : palette.good
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURRENT PROGRAM").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.white.opacity(0.75))
                    Text(g.goalValue.label).font(.number(32)).foregroundStyle(.white)
                }
                Spacer()
                Text("Week \(daysBetween(g.startDay, dayKey()) / 7 + 1)").font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 5).background(.white.opacity(0.2), in: Capsule()).foregroundStyle(.white)
            }
            HStack(spacing: 8) {
                chip(goalDetail(g, p))
                chip(p.inDietBreak(dayKey()) ? "Diet break" : p.shadowMode ? "Shadow" : styleText(g.mode))
                if let end = p.phaseEndText(p.weight) { chip(end) }
                chip(g.dietValue.label)
            }
            if let goal = p.goalWeightKg, let now {
                let total = goal - startKg
                let done = total != 0 ? max(0, min(1, (now - startKg) / total)) : 1
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(p.weight.format(startKg)) → \(p.weight.format(goal))").font(.callout.weight(.semibold)).foregroundStyle(.white)
                        Spacer()
                        Text("\(Int(done * 100 + 0.5))%").font(.callout.weight(.bold)).foregroundStyle(.white).monospacedDigit()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.22))
                            Capsule().fill(.white).frame(width: max(8, geo.size.width * done))
                        }
                    }
                    .frame(height: 8)
                    if let proj = projection(p, goal) { Text(proj).font(.caption).foregroundStyle(.white.opacity(0.85)) }
                }
            } else {
                Button("Set a goal weight") { editingGoalWeight = true }.font(.callout.weight(.semibold)).foregroundStyle(.white)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [tint, tint.mix(with: palette.accent.mix(with: .purple, by: 0.4), by: 0.5)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "target").font(.system(size: 110, weight: .bold)).foregroundStyle(.white.opacity(0.08))
                .offset(x: 24, y: 30).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: GlowStyle.on || palette.glass ? tint.opacity(0.45) : .clear, radius: 18, y: 6)
    }

    private func chip(_ t: String) -> some View {
        Text(t).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 10).padding(.vertical, 6).background(.white.opacity(0.18), in: Capsule()).foregroundStyle(.white)
    }

    /// This week, Monday to Sunday: each day's calories as a stacked column of protein, fat and carbs.
    private func weekTargets(_ p: Profile, _ t: TargetSet) -> some View {
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        let monday = dayKey(cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date())
        let days = (0..<7).map { addDays(monday, $0) }
        let targets = days.map { ctx.dayTargets(on: $0) ?? p.adjust(t.targets, on: $0) }
        let top = max(targets.map(\.kcal).max() ?? 1, 1)
        let sel = days.firstIndex(of: selectedDay) ?? days.firstIndex(of: dayKey()) ?? 0
        let s = targets[sel]
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Weekly Targets").font(.title3.weight(.semibold))
                Spacer()
                Text("avg \(p.energy.format(targets.map(\.kcal).reduce(0, +) / 7))").font(.callout).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days.indices, id: \.self) { i in
                    let d = targets[i]
                    Button { withAnimation(.snappy) { selectedDay = days[i] } } label: {
                        VStack(spacing: 6) {
                            Text(number(p.energy.fromKcal(d.kcal))).font(.caption2.weight(.semibold)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.6).foregroundStyle(i == sel ? .primary : .secondary)
                            VStack(spacing: 2) {
                                let h = 130 * d.kcal / top
                                segment(palette.carbs, h * d.carbs * 4 / max(d.kcal, 1))
                                segment(palette.fat, h * d.fat * 9 / max(d.kcal, 1))
                                segment(palette.protein, h * d.protein * 4 / max(d.kcal, 1))
                            }
                            .frame(height: 134, alignment: .bottom)
                            .shadow(color: GlowStyle.on && i == sel ? palette.accent.opacity(0.6) : .clear, radius: 6)
                            Text(date(fromKey: days[i]).formatted(.dateTime.weekday(.narrow).locale(appLocale)))
                                .font(.caption.weight(i == sel ? .bold : .regular)).foregroundStyle(i == sel ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(i == sel ? Color.primary.opacity(0.85) : .clear, lineWidth: 2))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(date(fromKey: days[sel]).formatted(.dateTime.weekday(.wide).locale(appLocale))).font(.caption).foregroundStyle(.secondary)
                    Text(p.energy.format(s.kcal)).font(.number(22, weight: .semibold)).monospacedDigit()
                }
                Spacer()
                ForEach([Macro.protein, .fat, .carbs], id: \.self) { m in
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(m.label).font(.caption).foregroundStyle(m.color)
                        Text("\(number(m.value(s))) g").font(.headline).monospacedDigit()
                    }
                    .frame(minWidth: 62, alignment: .trailing)
                }
            }
            Text("Based on an expenditure of \(p.energy.format(t.expenditure)) since \(relative(t.fromDay)).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).modifier(CardSurface())
    }

    private func segment(_ c: Color, _ h: Double) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(c.gradient).frame(width: 22, height: max(0, h))
    }

    private func checkInCard(_ g: Program) -> some View {
        let due = ctx.dueCheckIn != nil
        return HStack(spacing: 14) {
            Image(systemName: "calendar.badge.checkmark").font(.title2).foregroundStyle(due ? .white : palette.accent)
                .frame(width: 50, height: 50).background(due ? palette.accent : palette.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(due ? "Check-in ready" : "Weekly check-in").font(.headline)
                Text(due ? "Update your targets" : "Next: \(nextCheckIn(g))").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button(due ? "Check in" : "Early") { checkingIn = true }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(due ? palette.accent : Color.raisedBackground)
                .foregroundStyle(due ? .white : .primary)
        }
        .padding(16).modifier(CardSurface())
    }

    // MARK: Settings rows

    @ViewBuilder private func settings(_ p: Profile, _ g: Program, _ t: TargetSet) -> some View {
        VStack(spacing: 0) {
            rowButton("target", palette.good, "Goal", g.goalValue.label + " · " + goalDetail(g, p)) { editing = true }
            rowButton("flag.checkered", palette.calories, "Goal weight", p.goalWeightKg.map { p.weight.format($0) } ?? "Not set") { editingGoalWeight = true }
            rowButton("fork.knife", palette.fat, "Diet & protein", "\(g.dietValue.label) · \(number(g.proteinValue.gramsPerKg, digits: 1)) g/kg protein") { editing = true }
            rowButton("calendar", palette.carbs, "Calorie distribution", p.hasDistribution ? "On: varies by day" : "Off: the same every day") { showingDistribution = true }
            rowMenu("person.crop.circle.badge.checkmark", palette.accent, "Program style", styleText(g.mode)) {
                Button("Coached: the app sets everything, with guardrails") { g.mode = "coached"; ctx.commit() }
                Button("Collaborative: your macros, the app's weekly calories") { collaborative = true }
                Button("Manual: fixed targets you set") { manual = true }
            }
            rowMenu("figure.strengthtraining.traditional", palette.protein, "Training", (TrainingType(rawValue: p.trainingType) ?? .resistance).label + " · sets protein") {
                ForEach(TrainingType.allCases) { t in Button(t.label) { p.trainingType = t.rawValue; ctx.commit() } }
            }
            if g.mode == "coached" {
                rowButton("shield.lefthalf.filled", palette.good, "Calorie floor",
                          "Never below \(p.energy.format(p.calorieFloorKcal > 0 ? p.calorieFloorKcal : calorieFloor(p.sexValue))) · fat minimum on") { editingFloor = true }
            }
            rowMenu("clock.arrow.circlepath", palette.protein, "Check-in day", weekdayName(g.checkInWeekday)) {
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in Button(weekdayName(d)) { g.checkInWeekday = d; ctx.commit() } }
            }
            if g.mode == "manual" {
                rowButton("pencil", palette.accent, "Edit targets", "\(p.energy.format(t.targets.kcal)) a day") { manual = true }
            }
            if g.mode == "collaborative" {
                rowButton("pencil", palette.accent, "Your macros", "P \(number(t.targets.protein)) · F \(number(t.targets.fat)) · C \(number(t.targets.carbs))") { collaborative = true }
            }
            rowButton("arrow.up.circle", palette.carbs, "Refeed day",
                      p.refeedWeekday > 0 ? "\(weekdayName(p.refeedWeekday)) · +\(number(p.refeedExtraKcal / 4)) g carbs" : "Off") { refeeding = true }
            rowButton("pause.circle", palette.good, "Diet break",
                      p.inDietBreak(dayKey()) ? "On until \(date(fromKey: p.dietBreakEnd).formatted(.dateTime.day().month(.abbreviated).locale(appLocale)))"
                      : (!p.dietBreakStart.isEmpty && p.dietBreakStart > dayKey() ? "Planned from \(date(fromKey: p.dietBreakStart).formatted(.dateTime.day().month(.abbreviated).locale(appLocale)))"
                         : "A week or two at maintenance")) { breaking = true }
            rowButton("flag.2.crossed", palette.calories, "Phase plan",
                      [p.phaseEndText(p.weight), p.phases.first.map { "then " + $0.describe(p.weight) }].compactMap { $0 }.joined(separator: " · ").isEmpty
                        ? "Plan what comes after this phase"
                        : [p.phaseEndText(p.weight), p.phases.first.map { "then " + $0.describe(p.weight) }].compactMap { $0 }.joined(separator: " · ")) { planning = true }
            rowButton("eye.slash", Color(hex: 0xA77BF3), "Shadow mode", p.shadowMode ? "On: check-ins don't change targets" : "Off · replay past check-ins") { shadowing = true }
            rowButton("scalemass", palette.accent, "Scales", p.scaleNames.isEmpty ? "Just one" : "Main + \(p.scaleNames.joined(separator: ", "))") { scaling = true }
            rowLink("flame", palette.warn, "Expenditure settings", "Algorithm, starting estimate") { ExpenditureSettingsView() }
            rowLink("leaf", palette.good, "Nutrient targets", "Fibre, sugar, vitamins and minerals") { NutrientTargetsView() }
            rowLink("chart.line.uptrend.xyaxis", Color(hex: 0xA77BF3), "Weight trend settings", "How the trend is smoothed", last: true) { WeightTrendSettingsView() }
        }
        .modifier(CardSurface())
    }

    private func rowContent(_ icon: String, _ c: Color, _ title: String, _ value: String, last: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(c).frame(width: 36, height: 36).background(c.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(value).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { if !last { Divider().padding(.leading, 64) } }
    }

    private func rowButton(_ icon: String, _ c: Color, _ title: String, _ value: String, last: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { rowContent(icon, c, title, value, last: last) }.buttonStyle(.plain)
    }

    private func rowMenu<M: View>(_ icon: String, _ c: Color, _ title: String, _ value: String, @ViewBuilder _ items: () -> M) -> some View {
        Menu { items() } label: { rowContent(icon, c, title, value, last: false) }.menuStyle(.button).buttonStyle(.plain)
    }

    private func rowLink<D: View>(_ icon: String, _ c: Color, _ title: String, _ value: String, last: Bool = false, @ViewBuilder _ dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: { rowContent(icon, c, title, value, last: last) }.buttonStyle(.plain)
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
