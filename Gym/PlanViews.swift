import Charts
import SwiftData
import SwiftUI

private func planClock(_ m: Int) -> String { String(format: "%02d:%02d", (m / 60) % 24, m % 60) }

/// Food log → Plan: each meal with its planned foods (faint until eaten). Eat it in one tap, log a
/// different amount, swap a food, lock the meal, or see why.
struct PlanDayView: View {
    @Environment(\.modelContext) private var ctx
    let day: String
    let energy: EnergyUnit
    @State private var result: (plan: DayPlan, foods: [String: PlanFood], settings: PlannerSettings)?
    @State private var selected: ItemRef?
    @State private var adherence = Adherence.Summary()
    @State private var history: [DayEdits] = []          // undo: your edits before each change
    @State private var why = false
    @State private var week = false
    @State private var settings = false
    @State private var version = 0
    @State private var inferred: [Int: TrainingSlot] = [:]
    @State private var source: ModelContext.PlanSource = .history
    @State private var staples = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let r = result {
                trainingBar(r.settings)
                LargeEntriesCard(day: day, energy: energy)
                if source == .recent { staplesCard }
                if ctx.carbProposal { carbProposalCard }
                if let note = r.plan.note { ProblemCard(title: "Today's calories are mostly used", message: note, icon: "info.circle") }
                ForEach(r.plan.slots, id: \.index) { s in slotCard(s, r) }
                totals(r)
                if adherence.total > 0 { AdherenceCard(summary: adherence) }
                if !history.isEmpty {
                    Button { undo() } label: { Label("Undo last change", systemImage: "arrow.uturn.backward") }.font(.secondaryText.weight(.semibold))
                }
                HStack {
                    Button { why = true } label: { Label("Why this plan?", systemImage: "questionmark.circle") }
                    Spacer()
                    Button { week = true } label: { Label("Week & groceries", systemImage: "cart") }
                }
                .font(.secondaryText.weight(.semibold))
            } else {
                EmptyState(icon: "calendar.badge.clock", title: "No plan yet", message: "Set up your goal in Strategy first: the planner builds meals to hit those targets.")
            }
        }
        .task(id: "\(day)|\(dataVersion)|\(version)") {
            ctx.refreshTrainingWeek()
            inferred = ctx.inferredSchedule(); source = ctx.planSource
            result = ctx.dayPlan(day); if let r = result { ctx.recordPlan(day, r.plan); ctx.recordMeals(day, r) }
            #if DEBUG
            // Snapshots: -openPlanItem YES opens the first open food's sheet (swap, keep, portion).
            if UserDefaults.standard.bool(forKey: "openPlanItem"), selected == nil, let r = result,
               let s = r.plan.slots.first(where: { !$0.eaten && !$0.locked }), let it = s.items.first { selected = ItemRef(slot: s.index, item: it) }
            #endif
            adherence = ctx.weekAdherence()
            // The week view, ready before you open it.
            _ = await ctx.weekPlans(from: day)
        }
        .sheet(isPresented: $staples) {
            NavigationStack { StaplesView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { staples = false } } } }
                .appStyle().onDisappear { version += 1 }
        }
        .sheet(isPresented: $why) { if let r = result { NavigationStack { PlanWhyView(plan: r.plan) }.appStyle() } }
        .sheet(isPresented: $week) { NavigationStack { WeekPlanView(start: day) }.appStyle() }
        .sheet(isPresented: $settings) { NavigationStack { PlannerSettingsView() }.appStyle().onDisappear { version += 1 } }
        .sheet(item: $selected) { ref in
            if let r = result, let slot = r.plan.slots.first(where: { $0.index == ref.slot }) {
                let kind = r.plan.structure[slot.index]?.fill.first { $0.keys.contains(ref.item.key) }?.kind
                NavigationStack {
                    PlanItemSheet(item: ref.item, food: r.foods[ref.item.key], kind: kind,
                                  options: kind.map { ctx.swapOptions(day, slot: slot, kind: $0, item: ref.item) } ?? []) { a in act(a, slot: slot, item: ref.item, kind: kind, r) }
                }
                .appStyle()
            }
        }
    }

    // MARK: Edits (swap, keep, undo)

    private func change(_ f: (inout DayEdits) -> Void) {
        let before = ctx.profile?.planner.dayEdits[day] ?? DayEdits()
        history.append(before); if history.count > 30 { history.removeFirst() }
        ctx.editPlan(day, f); version += 1; Haptics.tap()
    }

    private func undo() {
        guard let prev = history.popLast() else { return }
        // From scratch with the earlier edits: the same plan you had before the change.
        ctx.forgetPlan(day); ctx.editPlan(day) { $0 = prev }; version += 1; Haptics.tick()
    }

    private func act(_ a: PlanItemSheet.Action, slot: PlanSlot, item: PlanItem, kind: TemplateSlot.Kind?, _ r: ModelContext.PlanResult) {
        let ik = DayEdits.itemKey(slot.index, item.key)
        // The first food of its kind fills the template slot; any other (a second protein) is an extra.
        let primary = kind.map { k in r.plan.structure[slot.index]?.fill.first { $0.kind == k && !$0.keys.isEmpty }?.keys.first == item.key } ?? false
        switch a {
        case .keep(let g):
            change { $0.pins[ik] = g; $0.pinKinds[ik] = primary ? kind?.rawValue : "extra" }
        case .unkeep:
            change { $0.pins[ik] = nil; $0.pinKinds[ik] = nil }
        case .swap(let f, let g):
            let nk = DayEdits.itemKey(slot.index, f.key)
            change { e in
                e.pins[ik] = nil; e.pinKinds[ik] = nil; e.start[ik] = nil
                if primary, let k = kind { e.picks[DayEdits.slotKey(slot.index, k)] = f.key; e.start[nk] = g }
                else { e.pins[nk] = g; e.pinKinds[nk] = "extra" }      // an extra food: swapped in at its matched portion
            }
        case .log(let g):
            guard let f = ctx.food(key: item.key) ?? ctx.materializeBasic(item.key) else { return }
            let t = Calendar.current.date(byAdding: .minute, value: slot.minute, to: date(fromKey: day)) ?? Date()
            if let p = r.foods[item.key], p.shownUnit != "g", f.units.contains(p.shownUnit) {
                _ = ctx.log(f, amount: (g * p.shownRatio).rounded(), unit: p.shownUnit, day: day, time: t)
            } else {
                _ = ctx.log(f, amount: g.rounded(), unit: f.baseUnit, day: day, time: t)
            }
            ctx.commit(); Haptics.success()
        }
    }

    private var staplesCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label("Pick your staples", systemImage: "basket").font(.cardTitle)
            Text("Your log doesn't have enough food-by-food history yet, so this plan uses your recent foods. Pick 15–25 foods you eat regularly for plans that look like your real meals.")
                .font(.secondaryText).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Choose staples") { staples = true }.buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent).font(.secondaryText.weight(.semibold))
        }
        .padding(Space.l).modifier(CardSurface())
    }

    private func trainingBar(_ s: PlannerSettings) -> some View {
        let t = s.training(on: day, inferred: inferred)
        let why = s.overrides[day] != nil ? "today only" : s.scheduleSet ? "your schedule" : t != nil ? "from your workouts" : inferred.isEmpty ? "no workout history yet" : nil
        return HStack {
            VStack(alignment: .leading, spacing: Space.hairline) {
                Label(t.map { "Training \(planClock($0.start)) · \($0.minutes) min" } ?? "Rest day", systemImage: t == nil ? "bed.double" : "dumbbell")
                    .font(.secondaryText.weight(.semibold))
                if let why { Text(why).font(.fine).foregroundStyle(.secondary) }
            }
            Spacer()
            Menu {
                Button("Rest day today") { override(TrainingSlot(start: -1, minutes: 0)) }
                ForEach([7, 9, 12, 16, 17, 18, 19, 20], id: \.self) { h in
                    Button("Training at \(h):00 today") { override(TrainingSlot(start: h * 60, minutes: t?.minutes ?? 75)) }
                }
                Divider()
                Button("Use my weekly schedule") { override(nil) }
                Button("Planner settings…") { settings = true }
            } label: { Text("Change").font(.secondaryText.weight(.semibold)) }
        }
        .padding(Space.m).modifier(CardSurface())
    }

    private var carbProposalCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label("Strength is dropping on training days", systemImage: "chart.line.downtrend.xyaxis").font(.cardTitle)
            Text("The coaching engine flagged falling strength while losing fast. Proposal: shift more carbs to training days and around sessions (rest days take a little more fat; the week's calories are the same). Evidence for timing is modest outside long, high-volume sessions, so this is your call.")
                .font(.secondaryText).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Shift carbs to training") { setBoost(true) }.buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent)
                Button("Not now") { setBoost(false) }.buttonStyle(.bordered)
            }
            .font(.secondaryText.weight(.semibold))
        }
        .padding(Space.l).modifier(CardSurface())
    }

    private func setBoost(_ on: Bool) {
        guard let p = ctx.profile else { return }
        var s = p.planner
        if on { s.trainingCarbBoost = true; s.carbs.dayShift = max(s.carbs.dayShift, 0.5) } else { s.dismissedCarbProposal = dayKey() }
        p.planner = s; ctx.commit(); version += 1; Haptics.tap()
    }

    private func override(_ t: TrainingSlot?) {
        guard let p = ctx.profile else { return }
        var s = p.planner
        s.overrides[day] = t
        s.overrides = s.overrides.filter { $0.key >= addDays(dayKey(), -7) }
        p.planner = s; ctx.commit(); version += 1; Haptics.tick()
    }

    private func label(_ k: PlanSlot.Kind) -> String {
        switch k { case .meal: return "Meal"; case .preWorkout: return "Before training"; case .postWorkout: return "After training"; case .preSleep: return "Before bed" }
    }

    private func slotCard(_ s: PlanSlot, _ r: (plan: DayPlan, foods: [String: PlanFood], settings: PlannerSettings)) -> some View {
        let m = s.items.reduce(Macros()) { $0 + (r.foods[$1.key]?.macros($1.grams) ?? Macros()) }
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Text(planClock(s.minute)).font(.numberSmall).monospacedDigit()
                Text(label(s.kind)).font(.label).foregroundStyle(.secondary).textCase(.uppercase)
                if s.kind == .preWorkout || s.kind == .postWorkout {
                    Image(systemName: "bolt.fill").font(.fine).foregroundStyle(palette.accent).accessibilityLabel(s.kind == .preWorkout ? "Before training" : "After training")
                }
                Spacer()
                Text("\(number(energy.fromKcal(m.kcal))) \(energy.rawValue) · \(Int(m.protein)) P · \(Int(m.carbs)) C").font(.fine).foregroundStyle(.secondary).monospacedDigit()
                if !s.eaten {
                    Button { toggleLock(s) } label: { Image(systemName: s.locked ? "lock.fill" : "lock.open") }
                        .buttonStyle(.borderless).accessibilityLabel(s.locked ? "Unlock this meal" : "Keep this meal every day")
                }
            }
            if let st = r.plan.structure[s.index] {
                Text(st.template + (st.dropped.isEmpty ? "" : " · dropped to fit: \(st.dropped.joined(separator: ", "))") + (st.unfilled.isEmpty ? "" : " · ⚠ \(st.unfilled.joined(separator: "; "))"))
                    .font(.fine).foregroundStyle(st.unfilled.isEmpty ? Color.secondary : palette.warn)
            }
            ForEach(Array(s.items.enumerated()), id: \.offset) { _, it in
                HStack {
                    if let kind = r.plan.structure[s.index]?.fill.first(where: { $0.keys.contains(it.key) })?.kind {
                        Text(kind.label).font(.fine).foregroundStyle(.tertiary).frame(width: 74, alignment: .leading).lineLimit(1)
                    }
                    Text(r.foods[it.key]?.name ?? it.key).lineLimit(1)
                    if it.isPinned { Image(systemName: "pin.fill").font(.fine).foregroundStyle(palette.accent).accessibilityLabel("Kept at this portion") }
                    Spacer()
                    Text(it.grams > 1 ? (r.foods[it.key]?.shown(it.grams) ?? "\(Int(it.grams)) g") : "\(Int(r.foods[it.key]?.macros(it.grams).kcal ?? 0)) kcal").monospacedDigit().foregroundStyle(.secondary)
                    if !s.eaten && !s.locked {
                        Button { selected = ItemRef(slot: s.index, item: it) } label: { Image(systemName: "arrow.triangle.2.circlepath") }.buttonStyle(.borderless)
                            .accessibilityLabel("Swap or change \(r.foods[it.key]?.name ?? "")")
                    }
                }
                .font(.secondaryText)
                .opacity(s.eaten ? 1 : 0.6)
                .contentShape(Rectangle())
                .onTapGesture { if !s.eaten && !s.locked { selected = ItemRef(slot: s.index, item: it) } }
            }
            if let short = r.plan.shortMeals.first(where: { r.plan.slots.indices.contains($0.index) && r.plan.slots[$0.index].index == s.index }) {
                Label("\(Int(short.protein)) g protein, below this meal's \(Int(short.needed)) g minimum: none of your foods for it has enough. Add a protein staple.",
                      systemImage: "exclamationmark.triangle").font(.fine).foregroundStyle(palette.warn).fixedSize(horizontal: false, vertical: true)
            }
            if s.eaten {
                Label("Eaten", systemImage: "checkmark.circle.fill").font(.fine).foregroundStyle(palette.good)
            } else {
                Button { ctx.eat(s, foods: r.foods, day: day); Haptics.success() } label: {
                    Text("Eat this meal").font(.secondaryText.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 38)
                        .background(palette.accentFill, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous)).foregroundStyle(palette.onAccent)
                }
                .pressable()
            }
        }
        .padding(Space.l)
        .modifier(CardSurface())
        .overlay { if !s.eaten { RoundedRectangle(cornerRadius: Radius.l + 2, style: .continuous).strokeBorder(palette.stroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4])) } }
    }

    private func totals(_ r: (plan: DayPlan, foods: [String: PlanFood], settings: PlannerSettings)) -> some View {
        let t = ctx.dayTargets(on: day)
        let provisional = r.plan.slots.contains(where: \.provisional)
        return HStack {
            Text("\(provisional ? "Plan (not counting the meal to confirm)" : "Plan"): \(number(energy.fromKcal(r.plan.totals.kcal))) \(energy.rawValue) · \(Int(r.plan.totals.protein)) g protein")
            Spacer()
            if let t { Text("target \(number(energy.fromKcal(t.kcal))) · \(Int(t.protein)) g").foregroundStyle(.secondary) }
        }
        .font(.fine).monospacedDigit()
        .safeAreaInset(edge: .bottom, spacing: Space.xs) {
            if let c = r.plan.carbs {
                HStack(spacing: Space.xs) {
                    Text("Carbs \(Int(r.plan.totals.carbs)) g · \(String(format: "%.1f", c.gPerKg)) g/kg")
                    Text(c.rangeIsTarget ? "(target \(Int(c.range.lowerBound))–\(Int(c.range.upperBound)))" : "(cut range \(Int(c.range.lowerBound))–\(Int(c.range.upperBound)); 4–7 for performance)")
                        .foregroundStyle(c.gPerKg < c.range.lowerBound ? palette.warn : Color.secondary)
                    if c.recovery { Label("recovery window", systemImage: "arrow.clockwise").labelStyle(.titleAndIcon) }
                    if c.intra > 0 { Text("· \(Int(c.intra)) g during training") }
                    Spacer()
                }
                .font(.fine).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    private func toggleLock(_ s: PlanSlot) {
        guard let p = ctx.profile else { return }
        var st = p.planner
        if s.locked { st.locks[s.index] = nil } else { st.locks[s.index] = s.items }
        p.planner = st; ctx.commit(); version += 1; Haptics.tick()
    }

}

/// A food in a meal (sheet item: an Identifiable value, so the sheet always has its content, Mac included).
private struct ItemRef: Identifiable, Equatable { var slot: Int; var item: PlanItem; var id: String { "\(slot)-\(item.key)" } }

/// Why this plan: the rules applied and their evidence.
struct PlanWhyView: View {
    let plan: DayPlan
    var body: some View {
        List {
            if !plan.relaxed.isEmpty {
                Section("Relaxed to fit") { ForEach(plan.relaxed, id: \.self) { Text($0.capitalized) } }
            }
            Section("Rules") {
                ForEach(Array(plan.reasons.enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(r.rule.capitalized).font(.secondaryText.weight(.semibold))
                        Text(r.detail).font(.secondaryText).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Evidence") {
                ForEach(Array(Set(plan.reasons.flatMap(\.evidence))).sorted(), id: \.self) { id in
                    if let e = Evidence.entry(id) { EvidenceRow(entry: e) }
                }
            }
        }
        .themedList()
        .navigationTitle("Why this plan")
    }
}

/// The week ahead and its grocery list.
struct WeekPlanView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let start: String
    @State private var days: [(day: String, plan: DayPlan, foods: [String: PlanFood])] = []

    var body: some View {
        List {
            Section {
                Chart(days, id: \.day) { d in
                    let training = d.plan.slots.contains { $0.kind == .preWorkout || $0.kind == .postWorkout }
                    BarMark(x: .value("Day", String(date(fromKey: d.day).formatted(.dateTime.weekday(.abbreviated).locale(appLocale)))), y: .value("Carbs", d.plan.totals.carbs))
                        .foregroundStyle(training ? palette.carbs : palette.carbs.opacity(0.4))
                        .annotation(position: .top) { Text(training ? "🏋" : "").font(.fine) }
                }
                .frame(height: 140)
                Text("Carbs per day; solid bars are training days. Same weekly calories: training days take more carbs, rest days more fat.")
                    .font(.note).foregroundStyle(.secondary)
            } header: { Text("Carbs this week") }
            Section("Next 7 days") {
                ForEach(days, id: \.day) { d in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(date(fromKey: d.day).formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(appLocale))).font(.secondaryText.weight(.semibold))
                        let training = d.plan.slots.contains { $0.kind == .preWorkout || $0.kind == .postWorkout }
                        Text("\(training ? "🏋 " : "")\(Int(d.plan.totals.kcal)) kcal · \(Int(d.plan.totals.protein)) P · \(Int(d.plan.totals.carbs)) C\(d.plan.carbs.map { String(format: " (%.1f g/kg)", $0.gPerKg) } ?? "") · \(d.plan.slots.count) meals\(d.plan.feasible ? "" : " · doesn't fully fit")")
                            .font(.note).foregroundStyle(d.plan.feasible ? Color.secondary : palette.warn).monospacedDigit()
                    }
                }
            }
            Section("Grocery list") {
                ForEach(Aisle.allCases, id: \.self) { a in
                    let items = groceries.filter { $0.aisle == a }
                    if !items.isEmpty {
                        Text(a.rawValue).font(.label).foregroundStyle(.secondary).textCase(.uppercase)
                        ForEach(items, id: \.name) { g in
                            HStack { Text(g.name).lineLimit(1); Spacer(); Text(g.amount).foregroundStyle(.secondary).monospacedDigit() }
                        }
                    }
                }
                ShareLink(item: groceryText) { Label("Share list", systemImage: "square.and.arrow.up") }
            }
        }
        .themedList()
        .navigationTitle("Week plan")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { days = await ctx.weekPlans(from: start) }
    }

    private var groceries: [(name: String, aisle: Aisle, amount: String)] {
        var grams: [String: Double] = [:], names: [String: String] = [:]
        for d in days { for s in d.plan.slots where !s.eaten { for it in s.items where !it.key.hasPrefix("entry:") {
            grams[it.key, default: 0] += it.grams; names[it.key] = d.foods[it.key]?.name ?? it.key
        } } }
        return grams.map { k, g in
            let amount = g >= 1000 ? String(format: "%.1f kg", (g / 100).rounded() / 10) : "\(Int((g / 50).rounded(.up) * 50)) g"
            return (names[k] ?? k, Aisle.of(names[k] ?? k), amount)
        }.sorted { ($0.aisle.rawValue, $0.name) < ($1.aisle.rawValue, $1.name) }
    }

    private var groceryText: String {
        Aisle.allCases.compactMap { a in
            let items = groceries.filter { $0.aisle == a }
            return items.isEmpty ? nil : a.rawValue.uppercased() + "\n" + items.map { "• \($0.name), \($0.amount)" }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

/// Planner settings: meals, day, training schedule, preferences.
struct PlannerSettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var s = PlannerSettings()
    @State private var loaded = false
    @State private var inferred: [Int: TrainingSlot] = [:]
    @Query(sort: \Routine.order) private var routines: [Routine]

    /// The week shown: yours once you've edited it, else the one from your workouts.
    private var week: [Int: TrainingSlot] { s.week(inferred) }
    private func edit(_ change: (inout [Int: TrainingSlot]) -> Void) {
        if !s.scheduleSet { s.schedule = inferred; s.scheduleSet = true }
        change(&s.schedule)
    }

    var body: some View {
        Form {
            Section("Your day") {
                Stepper("\(s.meals) meals a day", value: $s.meals, in: 2...7)
                timeRow("Wake up", $s.wake)
                timeRow("Bed", $s.sleep)
            }
            Section {
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                    HStack {
                        Text(weekdayName(wd))
                        Spacer()
                        Picker("", selection: Binding(get: { week[wd]?.start ?? -1 }, set: { v in
                            edit { $0[wd] = v < 0 ? nil : TrainingSlot(start: v, minutes: $0[wd]?.minutes ?? $0.values.first?.minutes ?? 75, routine: $0[wd]?.routine) } })) {
                            Text("Rest").tag(-1)
                            ForEach(Array(stride(from: 6 * 60, through: 22 * 60, by: 30)), id: \.self) { m in Text(planClock(m)).tag(m) }
                        }
                        .pickerStyle(.menu).labelsHidden()
                        // Which routine: its working sets size the day's carbs.
                        if week[wd] != nil, !routines.isEmpty {
                            Picker("", selection: Binding(get: { week[wd]?.routine ?? "" }, set: { v in edit { $0[wd]?.routine = v.isEmpty ? nil : v } })) {
                                Text("Usual session").tag("")
                                ForEach(routines, id: \.key) { r in Text(r.name).tag(r.key) }
                            }
                            .pickerStyle(.menu).labelsHidden()
                        }
                    }
                }
                Stepper("Sessions last \(week.values.first?.minutes ?? 75) min", value: Binding(get: { week.values.first?.minutes ?? 75 }, set: { v in
                    edit { for k in $0.keys { $0[k]?.minutes = v } } }), in: 30...180, step: 15)
                if s.scheduleSet && !inferred.isEmpty {
                    Button("Use the week from my workouts") { s.scheduleSet = false; s.schedule = [:] }
                }
                Toggle("Train fasted in the morning", isOn: $s.fastedMorning)
            } header: { Text("Training") } footer: {
                Text((s.scheduleSet ? "Your own week. " : inferred.isEmpty ? "No workouts logged in the last 6 weeks, so every day is a rest day until you set your week or log workouts. "
                      : "Inferred from your workouts in the last 6 weeks (a day counts if you trained on it in at least half the weeks). Change any day to set your own. ")
                     + "A meal goes about 2 hours before training and another after it. Fasted morning training is fine if you prefer it.")
            }
            Section {
                Picker("Training vs rest days", selection: $s.carbs.dayShift) {
                    Text("Same every day").tag(0.0); Text("Small shift").tag(0.15); Text("Moderate").tag(0.3); Text("Large").tag(0.5)
                }
                Stepper("Before training: \(String(format: "%.2f", s.carbs.preGPerKg)) g/kg", value: $s.carbs.preGPerKg, in: 0.5...1.0, step: 0.05)
                Toggle("Carbs during sessions over 90 min", isOn: $s.carbs.intra)
            } header: { Text("Carbs and training") } footer: {
                Text("Your calories don't change: on training days fat moves toward its floor and carbs go up, on rest days the reverse, more for bigger sessions. Before training about 0.5–1 g/kg; more after training when the next session is under 24 h away. The research finds carb timing matters most for long, high-volume sessions.")
            }
            Section {
                Toggle("Protein before bed", isOn: $s.preSleepProtein)
                VStack(alignment: .leading) {
                    Text("Variety")
                    Slider(value: $s.variety, in: 0...1) { Text("Variety") } minimumValueLabel: { Text("Same").font(.note) } maximumValueLabel: { Text("Varied").font(.note) }
                }
            } header: { Text("Preferences") } footer: { Text("Pre-sleep protein has some evidence but it's weak once total protein is the same; off by default.") }
            Section {
                NavigationLink("Meal templates") { TemplatesView() }
                NavigationLink("Simple foods") { CatalogView() }
                NavigationLink("Your usual meals") { UsualMealsView() }
                NavigationLink("Food taxonomy (roles, NOVA)") { TaxonomyReviewView() }
                NavigationLink("Staples (\(s.staples.count))") { StaplesView().onDisappear { if let p = ctx.profile { s.staples = p.planner.staples } } }
                NavigationLink("Foods to leave out (\(s.exclusions.count))") { ExclusionsView(exclusions: $s.exclusions) }
            } footer: { Text("Staples are used until your log has about two weeks of food-by-food history.") }
        }
        .themedForm()
        .navigationTitle("Meal planner")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { save(); dismiss() } } }
        .onAppear { if !loaded, let p = ctx.profile { s = p.planner; inferred = ctx.inferredSchedule(); loaded = true } }
        .onDisappear(perform: save)
    }

    private func save() {
        guard let p = ctx.profile else { return }
        // Staples and Health workouts are edited elsewhere: keep the latest of those.
        s.staples = p.planner.staples; s.healthSessions = p.planner.healthSessions; s.roles = p.planner.roles; s.inferredWeek = p.planner.inferredWeek
        s.templates = p.planner.templates; s.treatsEnabled = p.planner.treatsEnabled; s.catalogRemoved = p.planner.catalogRemoved; s.inStock = p.planner.inStock; s.usualMeals = p.planner.usualMeals; s.deletedUsualMeals = p.planner.deletedUsualMeals
        guard p.planner != s else { return }
        p.planner = s; ctx.commit()
    }

    private func timeRow(_ label: String, _ v: Binding<Int>) -> some View {
        DatePicker(label, selection: Binding(get: { Calendar.current.date(bySettingHour: v.wrappedValue / 60 % 24, minute: v.wrappedValue % 60, second: 0, of: Date()) ?? Date() },
                                             set: { d in let c = Calendar.current.dateComponents([.hour, .minute], from: d); v.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0) }),
                   displayedComponents: .hourAndMinute)
    }
}

struct ExclusionsView: View {
    @Binding var exclusions: [String]
    @Query(sort: \Food.useCount, order: .reverse) private var foods: [Food]
    var body: some View {
        List(foods.filter { $0.useCount > 0 || $0.isFavorite }) { f in
            Button { if let i = exclusions.firstIndex(of: f.key) { exclusions.remove(at: i) } else { exclusions.append(f.key) } } label: {
                HStack { Text(f.name).lineLimit(1); Spacer(); if exclusions.contains(f.key) { Image(systemName: "xmark.circle.fill").foregroundStyle(palette.warn) } }
            }
            .buttonStyle(.plain)
        }
        .themedList()
        .navigationTitle("Leave out")
    }
}

/// The last 7 days of planned meals: eaten as planned, swapped or skipped.
struct AdherenceCard: View {
    let summary: Adherence.Summary
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label("Plan, last 7 days", systemImage: "calendar.badge.checkmark").font(.cardTitle)
            HStack(spacing: Space.l) {
                ForEach(MealOutcome.allCases, id: \.self) { o in
                    VStack(alignment: .leading, spacing: Space.hairline) {
                        Text("\(summary.counts[o] ?? 0)").font(.numberSmall).monospacedDigit()
                        Text(o.label).font(.fine).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if let share = summary.asPlannedShare {
                Text("\(Int((share * 100).rounded()))% of \(summary.total) planned meals eaten as planned" + (summary.skippedMost.map { " · \($0.name) skipped \($0.times)×" } ?? "") + ".")
                    .font(.fine).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("Context only: it never changes your targets by itself.").font(.fine).foregroundStyle(.tertiary)
        }
        .padding(Space.l).modifier(CardSurface())
    }
}
