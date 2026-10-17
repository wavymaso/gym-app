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
    @State private var swapping: (slot: Int, item: PlanItem)?
    @State private var amount: (slot: PlanSlot, item: PlanItem)?
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
            result = ctx.dayPlan(day); if let r = result { ctx.recordPlan(day, r.plan) }
        }
        .sheet(isPresented: $staples) {
            NavigationStack { StaplesView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { staples = false } } } }
                .appStyle().onDisappear { version += 1 }
        }
        .sheet(isPresented: $why) { if let r = result { NavigationStack { PlanWhyView(plan: r.plan) }.appStyle() } }
        .sheet(isPresented: $week) { NavigationStack { WeekPlanView(start: day) }.appStyle() }
        .sheet(isPresented: $settings) { NavigationStack { PlannerSettingsView() }.appStyle().onDisappear { version += 1 } }
        .sheet(item: Binding(get: { swapping.map { SwapKey(slot: $0.slot, item: $0.item) } }, set: { _ in swapping = nil })) { k in
            if let r = result { NavigationStack { SwapSheet(item: k.item, foods: r.foods) { replacement in lock(slot: k.slot, replacing: k.item, with: replacement, r) } }.appStyle() }
        }
        .sheet(item: Binding(get: { amount.map { SwapKey(slot: $0.slot.index, item: $0.item) } }, set: { _ in amount = nil })) { k in
            if let r = result, let s = r.plan.slots.first(where: { $0.index == k.slot }) {
                AmountSheet(item: k.item, food: r.foods[k.item.key]) { amount in
                    // The amount is in the way you weigh it (g, g cooked or g raw).
                    if let f = ctx.food(key: k.item.key) ?? ctx.materializeBasic(k.item.key) {
                        let t = Calendar.current.date(byAdding: .minute, value: s.minute, to: date(fromKey: day)) ?? Date()
                        let unit = r.foods[k.item.key].map(\.shownUnit).flatMap { f.units.contains($0) ? $0 : nil } ?? f.baseUnit
                        _ = ctx.log(f, amount: amount, unit: unit, day: day, time: t); ctx.commit(); Haptics.tap()
                    }
                }
                .presentationDetents([.height(260)])
            }
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
            VStack(alignment: .leading, spacing: 1) {
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
            Text("The coaching engine flagged falling strength while losing fast. The planner can put more of the day's carbs before and after training (same daily totals). Evidence for exact timing is weak, so this is your call.")
                .font(.secondaryText).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Move carbs around training") { setBoost(true) }.buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent)
                Button("Not now") { setBoost(false) }.buttonStyle(.bordered)
            }
            .font(.secondaryText.weight(.semibold))
        }
        .padding(Space.l).modifier(CardSurface())
    }

    private func setBoost(_ on: Bool) {
        guard let p = ctx.profile else { return }
        var s = p.planner
        if on { s.trainingCarbBoost = true } else { s.dismissedCarbProposal = dayKey() }
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
                Spacer()
                Text("\(number(energy.fromKcal(m.kcal))) \(energy.rawValue) · \(Int(m.protein)) g P").font(.fine).foregroundStyle(.secondary).monospacedDigit()
                if !s.eaten {
                    Button { toggleLock(s) } label: { Image(systemName: s.locked ? "lock.fill" : "lock.open") }
                        .buttonStyle(.borderless).accessibilityLabel(s.locked ? "Unlock this meal" : "Keep this meal every day")
                }
            }
            ForEach(Array(s.items.enumerated()), id: \.offset) { _, it in
                HStack {
                    Text(r.foods[it.key]?.name ?? it.key).lineLimit(1)
                    Spacer()
                    Text(it.grams > 1 ? (r.foods[it.key]?.shown(it.grams) ?? "\(Int(it.grams)) g") : "\(Int(r.foods[it.key]?.macros(it.grams).kcal ?? 0)) kcal").monospacedDigit().foregroundStyle(.secondary)
                    if !s.eaten {
                        Button { swapping = (s.index, it) } label: { Image(systemName: "arrow.triangle.2.circlepath") }.buttonStyle(.borderless)
                            .accessibilityLabel("Swap \(r.foods[it.key]?.name ?? "")")
                    }
                }
                .font(.secondaryText)
                .opacity(s.eaten ? 1 : 0.6)
                .contentShape(Rectangle())
                .onTapGesture { if !s.eaten { amount = (s, it) } }
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
    }

    private func toggleLock(_ s: PlanSlot) {
        guard let p = ctx.profile else { return }
        var st = p.planner
        if s.locked { st.locks[s.index] = nil } else { st.locks[s.index] = s.items }
        p.planner = st; ctx.commit(); version += 1; Haptics.tick()
    }

    private func lock(slot: Int, replacing old: PlanItem, with new: PlanItem, _ r: (plan: DayPlan, foods: [String: PlanFood], settings: PlannerSettings)) {
        // A swap keeps that meal as you want it (locked), and the rest of the day re-plans around it.
        guard let p = ctx.profile, let s = r.plan.slots.first(where: { $0.index == slot }) else { return }
        var st = p.planner
        st.locks[slot] = s.items.map { $0 == old ? new : $0 }
        p.planner = st; ctx.commit(); version += 1; Haptics.tap()
    }
}

private struct SwapKey: Identifiable { var slot: Int; var item: PlanItem; var id: String { "\(slot)-\(item.key)" } }

/// Replacements from your own foods with similar macros, at the same calories, most-eaten first.
struct SwapSheet: View {
    let item: PlanItem
    let foods: [String: PlanFood]
    let choose: (PlanItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let cur = foods[item.key]
        let m = cur?.macros(item.grams) ?? Macros()
        let options = foods.values.filter { $0.key != item.key && !$0.key.hasPrefix("entry:") && $0.per100.kcal > 0 }.map { f -> (PlanFood, Double, Double) in
            var g = m.kcal / f.per100.kcal * 100
            g = max(f.step, (g / f.step).rounded() * f.step)
            let n = f.macros(g)
            let d = abs(n.protein - m.protein) * 4 + abs(n.carbs - m.carbs) * 2 + abs(n.fat - m.fat) * 3
            return (f, g, d - f.frequency * 0.5)
        }.sorted { ($0.2, $0.0.key) < ($1.2, $1.0.key) }.prefix(8)
        return List {
            Section { Text("Similar calories and macros, from foods you eat; most familiar first.").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(options), id: \.0.key) { f, g, _ in
                let n = f.macros(g)
                Button { choose(PlanItem(key: f.key, grams: g)); dismiss() } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(f.name).lineLimit(1)
                            Text("\(Int(n.kcal)) kcal · \(Int(n.protein))P \(Int(n.fat))F \(Int(n.carbs))C").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer()
                        Text("\(Int(g)) g").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .themedList()
        .navigationTitle("Swap \(cur?.name ?? "")")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}

/// Ate a different amount: log what you actually had (the rest of the day re-plans).
struct AmountSheet: View {
    let item: PlanItem
    let food: PlanFood?
    let log: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var body: some View {
        VStack(spacing: Space.l) {
            Text(food?.name ?? "").font(.cardTitle)
            HStack(alignment: .firstTextBaseline) {
                TextField("\(Int((item.grams * (food?.shownRatio ?? 1)).rounded()))", text: $text).font(.numberLarge).multilineTextAlignment(.center).frame(maxWidth: 160)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Text(food?.shownUnit ?? "g").unitStyle()
            }
            Button {
                log(parseNumber(text) ?? (item.grams * (food?.shownRatio ?? 1)).rounded()); dismiss()
            } label: { Text("Log what I ate").font(.headline).frame(maxWidth: .infinity, minHeight: 48) }
                .buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent)
        }
        .padding(Space.xl)
    }
}

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
                    VStack(alignment: .leading, spacing: 2) {
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
            Section("Next 7 days") {
                ForEach(days, id: \.day) { d in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(date(fromKey: d.day).formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(appLocale))).font(.secondaryText.weight(.semibold))
                        Text("\(Int(d.plan.totals.kcal)) kcal · \(Int(d.plan.totals.protein)) g protein · \(d.plan.slots.count) meals\(d.plan.feasible ? "" : " · doesn't fully fit")")
                            .font(.caption).foregroundStyle(d.plan.feasible ? Color.secondary : palette.warn).monospacedDigit()
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
        .task {
            var uses: [String: Int] = [:], out: [(day: String, plan: DayPlan, foods: [String: PlanFood])] = []
            for i in 0..<7 {
                let d = addDays(start, i)
                guard let r = ctx.dayPlan(d, uses: uses) else { continue }
                for s in r.plan.slots where !s.eaten { for it in s.items { uses[it.key, default: 0] += 1 } }
                out.append((d, r.plan, r.foods))
            }
            days = out
        }
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
                            edit { $0[wd] = v < 0 ? nil : TrainingSlot(start: v, minutes: $0[wd]?.minutes ?? $0.values.first?.minutes ?? 75) } })) {
                            Text("Rest").tag(-1)
                            ForEach(Array(stride(from: 6 * 60, through: 22 * 60, by: 30)), id: \.self) { m in Text(planClock(m)).tag(m) }
                        }
                        .pickerStyle(.menu).labelsHidden()
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
                Toggle("Protein before bed", isOn: $s.preSleepProtein)
                VStack(alignment: .leading) {
                    Text("Variety")
                    Slider(value: $s.variety, in: 0...1) { Text("Variety") } minimumValueLabel: { Text("Same").font(.caption) } maximumValueLabel: { Text("Varied").font(.caption) }
                }
            } header: { Text("Preferences") } footer: { Text("Pre-sleep protein has some evidence but it's weak once total protein is the same; off by default.") }
            Section {
                NavigationLink("Meal templates") { TemplatesView() }
                NavigationLink("Simple foods") { CatalogView() }
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
        s.templates = p.planner.templates; s.treatsEnabled = p.planner.treatsEnabled; s.catalogRemoved = p.planner.catalogRemoved; s.inStock = p.planner.inStock
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
