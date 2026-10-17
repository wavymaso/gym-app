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
    @State private var editingGoalFlow = false
    @Query(sort: \Program.startDay, order: .reverse) private var allPrograms: [Program]
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
            VStack(alignment: .leading, spacing: Space.l) {
                header
                if let p = profiles.first, let g = programs.first, let t = targetSets.first(where: { $0.fromDay <= dayKey() }) {
                    checkInRing(g)
                    CoachCard()
                    if ctx.engineBody.isEstimated {
                        NavigationLink { WeightView() } label: {
                            Label("Add your waist and neck measurements: the coaching then uses your own lean mass for protein and a personal calorie floor, instead of an assumed 20% body fat.",
                                  systemImage: "ruler").font(.secondaryText).foregroundStyle(.secondary)
                                .padding(Space.l).frame(maxWidth: .infinity, alignment: .leading).modifier(CardSurface())
                        }
                        .buttonStyle(.plain)
                    }
                    Text("In Progress").font(.sectionTitle).padding(.top, Space.xs)
                    hero(p, g)
                    weekTargets(p, t)
                    programButtons(g)
                    goalCard(p, g)
                    settings(p, g, t)
                    goalHistory(p)
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
        .sheet(isPresented: $manual) { ProgramEditor(mode: "manual") }
        .sheet(isPresented: $collaborative) { ProgramEditor(mode: "collaborative") }
        .sheet(isPresented: $editingGoalFlow) { EditGoalFlow() }
        #if DEBUG
        .onAppear {       // testing only: -strategySheet goal | program
            switch UserDefaults.standard.string(forKey: "strategySheet") { case "goal": editingGoalFlow = true; case "program": collaborative = true; case "checkin": checkingIn = true; default: break }
        }
        #endif
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
                        DistributionCard(profile: p, targets: t.targets).padding(Space.l)
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
            Text("STRATEGY").font(.pageTitle(isPhone ? 30 : 34)).foregroundStyle(palette.titleStyle).lineLimit(1).minimumScaleFactor(0.6)
            Spacer()
            Button { checkingIn = true } label: { roundIcon("calendar.badge.checkmark") }.buttonStyle(.plain)
            Button { editing = true } label: { roundIcon("slider.horizontal.3") }.buttonStyle(.plain)
        }
    }

    private func roundIcon(_ name: String) -> some View {
        Image(systemName: name).font(.cardTitle).frame(width: 44, height: 44).modifier(GlassCapsule())
    }

    // MARK: The program

    private func hero(_ p: Profile, _ g: Program) -> some View {
        let series = trendSeries(weighIns.map { DayValue(day: $0.day, value: $0.trendKg) }, through: dayKey())
        let now = series.last?.trend
        let startKg = series.first { $0.day >= g.startDay }?.trend ?? g.startWeightKg
        return VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("CURRENT PROGRAM").font(.label).tracking(0.8).foregroundStyle(palette.text2)
                    Text(g.goalValue.label).font(.numberLarge).foregroundStyle(palette.text1)
                }
                Spacer()
                Text("Week \(daysBetween(g.startDay, dayKey()) / 7 + 1)").font(.label)
                    .padding(.horizontal, Space.m).padding(.vertical, Space.xs).background(Color.raisedBackground, in: Capsule()).foregroundStyle(palette.text1)
            }
            HStack(spacing: Space.s) {
                chip(goalDetail(g, p))
                chip(p.inDietBreak(dayKey()) ? "Diet break" : p.shadowMode ? "Shadow" : styleText(g.mode))
                if let end = p.phaseEndText(p.weight) { chip(end) }
                chip(g.dietValue.label)
            }
            if let goal = p.goalWeightKg, let now {
                let total = goal - startKg
                let done = total != 0 ? max(0, min(1, (now - startKg) / total)) : 1
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack {
                        Text("\(p.weight.format(startKg)) → \(p.weight.format(goal))").font(.secondaryEmphasis).foregroundStyle(palette.text1)
                        Spacer()
                        Text("\(Int(done * 100 + 0.5))%").font(.secondaryEmphasis).foregroundStyle(palette.text1).monospacedDigit()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.raisedBackground)
                            Capsule().fill(palette.accentFill).frame(width: max(8, geo.size.width * done))
                        }
                    }
                    .frame(height: 8)
                    if let proj = projection(p, goal) { Text(proj).font(.note).foregroundStyle(palette.text2) }
                }
            } else {
                Button("Set a goal weight") { editingGoalWeight = true }.font(.secondaryEmphasis).foregroundStyle(palette.text1)
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardSurface(cornerRadius: Radius.xl))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "target").font(.system(size: 110, weight: .bold)).foregroundStyle(palette.text1.opacity(0.045))
                .offset(x: 24, y: 30).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private func chip(_ t: String) -> some View {
        Text(t).font(.label).lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, Space.m).padding(.vertical, Space.s).background(Color.raisedBackground, in: Capsule()).foregroundStyle(palette.text1)
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
        return VStack(alignment: .leading, spacing: Space.l) {
            HStack {
                Text("Weekly Targets").font(.subsectionTitle)
                Spacer()
                Text("avg \(p.energy.format(targets.map(\.kcal).reduce(0, +) / 7))").font(.secondaryText).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: Space.s) {
                ForEach(days.indices, id: \.self) { i in
                    let d = targets[i]
                    Button { animate(Motion.snappy) { selectedDay = days[i] } } label: {
                        VStack(spacing: Space.s) {
                            Text(number(p.energy.fromKcal(d.kcal))).font(.fineLabel).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.6).foregroundStyle(i == sel ? .primary : .secondary)
                            VStack(spacing: Space.xxs) {
                                let h = 130 * d.kcal / top
                                segment(palette.carbs, h * d.carbs * 4 / max(d.kcal, 1))
                                segment(palette.fat, h * d.fat * 9 / max(d.kcal, 1))
                                segment(palette.protein, h * d.protein * 4 / max(d.kcal, 1))
                            }
                            .frame(height: 134, alignment: .bottom)
                            Text(date(fromKey: days[i]).formatted(.dateTime.weekday(.narrow).locale(appLocale)))
                                .font(i == sel ? Font.label : Font.note).foregroundStyle(i == sel ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, Space.s)
                        .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                            .stroke(i == sel ? Color.primary.opacity(0.85) : .clear, lineWidth: 2))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(date(fromKey: days[sel]).formatted(.dateTime.weekday(.wide).locale(appLocale))).font(.note).foregroundStyle(.secondary)
                    Text(p.energy.format(s.kcal)).font(.numberMedium).monospacedDigit()
                }
                Spacer()
                ForEach([Macro.protein, .fat, .carbs], id: \.self) { m in
                    VStack(alignment: .trailing, spacing: Space.xxs) {
                        Text(m.label).font(.note).foregroundStyle(m.color)
                        Text("\(number(m.value(s))) g").font(.cardTitle).monospacedDigit()
                    }
                    .frame(minWidth: 62, alignment: .trailing)
                }
            }
            Text("Based on an expenditure of \(p.energy.format(t.expenditure)) since \(relative(t.fromDay)).")
                .font(.note).foregroundStyle(.secondary)
        }
        .padding(Space.l).modifier(CardSurface())
    }

    private func segment(_ c: Color, _ h: Double) -> some View {
        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous).fill(c).frame(width: 22, height: max(0, h))
    }

    // MARK: MacroFactor's Strategy top: the countdown, then the program and goal

    /// Days to the next check-in as a ring, with Goal and Check-in buttons under it.
    private func checkInRing(_ g: Program) -> some View {
        let due = ctx.dueCheckIn != nil
        var days = 0
        if !due {
            var d = addDays(dayKey(), 1); days = 1
            while Calendar(identifier: .gregorian).component(.weekday, from: date(fromKey: d)) != g.checkInWeekday { d = addDays(d, 1); days += 1 }
        }
        let progress = due ? 1 : Double(7 - days) / 7
        return VStack(spacing: Space.l) {
            ZStack {
                Circle().stroke(Color.raisedBackground, lineWidth: 10)
                Circle().trim(from: 0, to: progress).stroke(palette.good, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle().inset(by: 22).stroke(Color.primary.opacity(0.85), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                VStack(spacing: Space.xxs) {
                    Text(due ? "TODAY" : "\(days) DAY\(days == 1 ? "" : "S")").font(.pageTitle(30)).foregroundStyle(palette.titleStyle).monospacedDigit()
                    Text(due ? "check-in ready" : "until check-in").font(.secondaryText).foregroundStyle(.secondary)
                }
            }
            .frame(width: 230, height: 230)
            .animation(Motion.snappy, value: progress)
            HStack(spacing: Space.xxl) {
                Button { editingGoalFlow = true } label: { Label("Goal", systemImage: "target").font(.cardTitle) }
                Button { checkingIn = true } label: {
                    Label(due ? "Check in now" : "Check-in", systemImage: "calendar.badge.checkmark").font(.cardTitle)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s)
    }

    private func programButtons(_ g: Program) -> some View {
        HStack(spacing: Space.m) {
            pill("arrow.clockwise", "New Program") { editing = true }
            pill("pencil", "Edit Program") {
                if g.mode == "manual" { manual = true } else if g.mode == "collaborative" { collaborative = true } else { editing = true }
            }
        }
    }

    private func pill(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.secondaryEmphasis).lineLimit(1)
                .padding(.horizontal, Space.l).padding(.vertical, Space.m).modifier(GlassCapsule())
        }
        .buttonStyle(.plain)
    }

    /// Goal weight and rate, with New Goal / Edit Goal.
    private func goalCard(_ p: Profile, _ g: Program) -> some View {
        let trend = trendSeries(weighIns.map { DayValue(day: $0.day, value: $0.trendKg) }, through: dayKey()).last?.trend ?? g.startWeightKg
        let weekly = weeklyChangeKg(goal: g.goalValue, ratePercent: g.ratePercent, weightKg: trend)
        return VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(g.goalValue == .lose ? "Weight Loss Goal" : g.goalValue == .gain ? "Weight Gain Goal" : "Maintenance Goal").font(.subsectionTitle)
                Text("\(date(fromKey: g.startDay).formatted(.dateTime.day().month(.abbreviated).year().locale(appLocale))) – Now")
                    .font(.secondaryText).foregroundStyle(.secondary)
            }
            HStack(alignment: .top) {
                goalStat(p.goalWeightKg.map { number(p.weight.fromKg($0), digits: 1) } ?? "–", p.weight.rawValue, "Goal Weight")
                goalStat((weekly > 0 ? "+" : weekly < 0 ? "−" : "") + number(abs(p.weight.fromKg(weekly)), digits: 2), p.weight.rawValue, "Goal Rate")
                goalStat((g.goalValue == .lose ? "−" : g.goalValue == .gain ? "+" : "") + number(g.ratePercent, digits: 2), "%", "Goal Rate")
            }
            if let gw = p.goalWeightKg, let proj = projection(p, gw) {
                Text(proj).font(.note).foregroundStyle(palette.good)
            }
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.m) {
                    pill("plus", "New Goal") { editing = true }
                    pill("pencil", "Edit Goal") { editingGoalFlow = true }
                    pill("flag.2.crossed", "Phase Plan") { planning = true }
                }
                .padding(.horizontal, Space.l)
            }
            .padding(.horizontal, -16)          // scrolls to the card's edge instead of being cut at its padding
        }
        .padding(Space.l).modifier(CardSurface())
    }

    private func goalStat(_ value: String, _ unit: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(value).font(.numberLarge).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(.note).foregroundStyle(.secondary)
            }
            Text(label).font(.note).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Every program you've run: when, from what weight to what, and which is current.
    private func goalHistory(_ p: Profile) -> some View {
        let trend = Dictionary(trendSeries(weighIns.map { DayValue(day: $0.day, value: $0.trendKg) }, through: dayKey()).map { ($0.day, $0.trend) },
                               uniquingKeysWith: { a, _ in a })
        func kg(_ day: String) -> Double? { trend[day] ?? trend.filter { $0.key <= day }.max { $0.key < $1.key }?.value }
        let list = Array(allPrograms.prefix(20))
        return VStack(alignment: .leading, spacing: Space.m) {
            Text("Goal History").font(.sectionTitle).padding(.top, Space.xs)
            ForEach(Array(list.enumerated()), id: \.element.id) { i, prog in
                let end = i == 0 ? nil : list[i - 1].startDay
                HStack {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("\(date(fromKey: prog.startDay).formatted(.dateTime.day().month(.abbreviated).year().locale(appLocale))) – \(end.map { date(fromKey: $0).formatted(.dateTime.day().month(.abbreviated).year().locale(appLocale)) } ?? "Now")")
                            .font(.secondaryText).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                            Text(p.weight.format(kg(prog.startDay) ?? prog.startWeightKg)).font(.subsectionTitle).monospacedDigit()
                            if let e = end, let w = kg(e) {
                                Text("to").font(.note).foregroundStyle(.secondary)
                                Text(p.weight.format(w)).font(.subsectionTitle).monospacedDigit()
                            }
                        }
                    }
                    Spacer()
                    Text(prog.goalValue.label).font(.secondaryText).foregroundStyle(.secondary)
                    Image(systemName: prog.isActive ? "hourglass" : "checkmark.circle.fill").foregroundStyle(prog.isActive ? Color.primary : palette.good)
                }
                .padding(Space.l).modifier(CardSurface())
            }
        }
    }

    private func checkInCard(_ g: Program) -> some View {
        let due = ctx.dueCheckIn != nil
        return HStack(spacing: Space.l) {
            Image(systemName: "calendar.badge.checkmark").font(.sectionTitle).foregroundStyle(due ? palette.onAccent : palette.accent)
                .frame(width: 50, height: 50).background(due ? palette.accent : palette.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: Radius.m))
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(due ? "Check-in ready" : "Weekly check-in").font(.cardTitle)
                Text(due ? "Update your targets" : "Next: \(nextCheckIn(g))").font(.secondaryText).foregroundStyle(.secondary)
            }
            Spacer()
            Button(due ? "Check in" : "Early") { checkingIn = true }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(due ? palette.accent : Color.raisedBackground)
                .foregroundStyle(due ? palette.onAccent : .primary)
        }
        .padding(Space.l).modifier(CardSurface())
    }

    // MARK: Settings rows

    @ViewBuilder private func settings(_ p: Profile, _ g: Program, _ t: TargetSet) -> some View {
        let phaseText = [p.phaseEndText(p.weight), p.phases.first.map { "then " + $0.describe(p.weight) }].compactMap { $0 }.joined(separator: " · ")
        category("Goal & targets", "What you're aiming for") {
            rowButton("target", palette.good, "Goal", g.goalValue.label + " · " + goalDetail(g, p)) { editing = true }
            if g.goalValue == .maintain {
                rowLink("arrow.triangle.2.circlepath", palette.carbs, "Recomposition", p.recomp ? "On: maintenance calories, higher protein" : "Off") {
                    RecompPage(profile: p)
                }
            }
            rowButton("flag.checkered", palette.calories, "Goal weight & rate", p.goalWeightKg.map { p.weight.format($0) } ?? "Not set") { editingGoalFlow = true }
            rowButton("fork.knife", palette.fat, "Diet & protein", "\(g.dietValue.label) · \(number(g.proteinValue.gramsPerKg, digits: 1)) g/kg protein") { editing = true }
            rowLink("figure.strengthtraining.traditional", palette.protein, "Training", (TrainingType(rawValue: p.trainingType) ?? .resistance).label + " · sets protein",
                    last: g.mode == "coached") {
                OptionsPage(title: "Training", header: "What you mainly do. It sets how much protein your targets carry.",
                            options: TrainingType.allCases.map { .init(id: $0.rawValue, title: $0.label) },
                            selected: p.trainingType.isEmpty ? TrainingType.resistance.rawValue : p.trainingType) { p.trainingType = $0; ctx.commit() }
            }
            if g.mode == "manual" {
                rowButton("pencil", palette.accent, "Edit targets", "\(p.energy.format(t.targets.kcal)) a day", last: true) { manual = true }
            }
            if g.mode == "collaborative" {
                rowButton("pencil", palette.accent, "Your macros", "P \(number(t.targets.protein)) · F \(number(t.targets.fat)) · C \(number(t.targets.carbs))", last: true) { collaborative = true }
            }
        }
        category("Coaching", "How targets get updated") {
            rowLink("person.crop.circle.badge.checkmark", palette.accent, "Program style", styleText(g.mode)) {
                OptionsPage(title: "Program Style",
                            header: "How much of your targets the app decides. Every style keeps the weekly check-in.",
                            options: [.init(id: "coached", title: "Coached", detail: "The app sets calories and macros each week from your expenditure and goal, with guardrails."),
                                      .init(id: "collaborative", title: "Collaborative", detail: "You set protein and your carb/fat split per day; the app moves the calories with your expenditure."),
                                      .init(id: "manual", title: "Manual", detail: "Fixed targets you set. Check-ins show the numbers but never change them.")],
                            selected: g.mode) { m in
                    switch m {
                    case "coached": g.mode = "coached"; ctx.commit()
                    case "collaborative": DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { collaborative = true }
                    default: DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { manual = true }
                    }
                }
            }
            rowLink("clock.arrow.circlepath", palette.protein, "Check-in day", weekdayName(g.checkInWeekday)) {
                OptionsPage(title: "Check-In Day", header: "The day each week your targets are reviewed.",
                            options: [2, 3, 4, 5, 6, 7, 1].map { .init(id: $0, title: weekdayName($0)) },
                            selected: g.checkInWeekday) { g.checkInWeekday = $0; ctx.commit() }
            }
            if g.mode == "coached" {
                rowButton("shield.lefthalf.filled", palette.good, "Calorie floor",
                          "Never below \(p.energy.format(p.calorieFloorKcal > 0 ? p.calorieFloorKcal : calorieFloor(p.sexValue))) · fat minimum on") { editingFloor = true }
            }
            rowButton("eye.slash", Color.weightTone, "Shadow mode", p.shadowMode ? "On: check-ins don't change targets" : "Off · replay past check-ins", last: true) { shadowing = true }
        }
        category("Your week & phases", "Planning the days and months ahead") {
            rowButton("calendar", palette.carbs, "Calorie distribution", p.hasDistribution ? "On: varies by day" : "Off: the same every day") { showingDistribution = true }
            rowButton("arrow.up.circle", palette.carbs, "Refeed day",
                      p.refeedWeekday > 0 ? "\(weekdayName(p.refeedWeekday)) · +\(number(p.refeedExtraKcal / 4)) g carbs" : "Off") { refeeding = true }
            rowButton("pause.circle", palette.good, "Diet break",
                      p.inDietBreak(dayKey()) ? "On until \(date(fromKey: p.dietBreakEnd).formatted(.dateTime.day().month(.abbreviated).locale(appLocale)))"
                      : (!p.dietBreakStart.isEmpty && p.dietBreakStart > dayKey() ? "Planned from \(date(fromKey: p.dietBreakStart).formatted(.dateTime.day().month(.abbreviated).locale(appLocale)))"
                         : "A week or two at maintenance")) { breaking = true }
            rowButton("flag.2.crossed", palette.calories, "Phase plan", phaseText.isEmpty ? "Plan what comes after this phase" : phaseText, last: true) { planning = true }
        }
        category("Accuracy", "How your data is read") {
            rowButton("scalemass", palette.accent, "Scales", p.scaleNames.isEmpty ? "Just one" : "Main + \(p.scaleNames.joined(separator: ", "))") { scaling = true }
            rowLink("flame", palette.warn, "Expenditure", "Starting estimate, modifiers") { ExpenditureSettingsView() }
            rowLink("leaf", palette.good, "Nutrient targets", "Fibre, sugar, vitamins and minerals") { NutrientTargetsView() }
            rowLink("questionmark.circle", palette.accent, "Why these targets?", "Every check-in's decision and its evidence") { DecisionHistoryView() }
            rowLink("books.vertical", palette.accent, "Evidence", "What the coaching is based on, and how strong it is", last: true) { EvidenceListView() }
        }
    }

    /// A titled card of related rows.
    private func category<C: View>(_ title: String, _ subtitle: String, @ViewBuilder _ rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(title).font(.sectionTitle).padding(.top, Space.s)
            VStack(spacing: 0) { rows() }.modifier(CardSurface(cornerRadius: Radius.l))
        }
    }

    private func rowContent(_ icon: String, _ c: Color, _ title: String, _ value: String, last: Bool) -> some View {
        HStack(spacing: Space.l) {
            Image(systemName: icon).font(.subsectionTitle).foregroundStyle(.primary).frame(width: 32)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title).font(.bodyText)
                Text(value).font(.note).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.secondaryEmphasis).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { if !last { Divider().padding(.leading, 60) } }
    }

    private func rowButton(_ icon: String, _ c: Color, _ title: String, _ value: String, last: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { rowContent(icon, c, title, value, last: last) }.buttonStyle(.plain)
    }

    private func rowMenu<M: View>(_ icon: String, _ c: Color, _ title: String, _ value: String, last: Bool = false, @ViewBuilder _ items: () -> M) -> some View {
        Menu { items() } label: { rowContent(icon, c, title, value, last: last) }.menuStyle(.button).buttonStyle(.plain)
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

/// "Monday" for 2 (Calendar weekdays: 1 = Sunday).
func weekdayName(_ d: Int) -> String {
    var c = Calendar(identifier: .gregorian)
    c.locale = appLocale
    return c.weekdaySymbols[d - 1]
}
