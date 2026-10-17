import Charts
import SwiftData
import SwiftUI

/// Today at a glance: rings for what's left to eat, quick actions, then your week.
struct DashboardView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.openPage) private var openPage
    @Query private var profiles: [Profile]
    @Query(sort: \TargetSet.fromDay, order: .reverse) private var targetSets: [TargetSet]
    @Query(sort: \WeightEntry.day, order: .reverse) private var weights: [WeightEntry]
    @Query(filter: #Predicate<Program> { $0.isActive }) private var programs: [Program]
    @Query private var weekEntries: [FoodEntry]
    @Query private var loggedDays: [FoodEntry]
    @AppStorage("dashLayout") private var layoutJSON = ""
    @State private var heroPage = UserDefaults.standard.integer(forKey: "heroPage")      // testing: -heroPage 1
    @State private var heroHeights: [Int: CGFloat] = [:]
    @State private var detail: InsightKind? = {
        #if DEBUG
        if let k = UserDefaults.standard.string(forKey: "insight") { return InsightKind(rawValue: k) }   // testing: -insight expenditure
        #endif
        return nil
    }()
    @State private var sheet: DashSheet? = {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "checkIn") { return .checkIn }       // testing only
        #endif
        return nil
    }()

    enum DashSheet: String, Identifiable {
        case addFood, quickAdd, weighIn, checkIn, layout
        var id: String { rawValue }
    }

    init() {
        let weekAgo = addDays(dayKey(), -6), monthsAgo = addDays(dayKey(), -400)
        _weekEntries = Query(filter: #Predicate<FoodEntry> { $0.day >= weekAgo })
        _loggedDays = Query(filter: #Predicate<FoodEntry> { $0.day >= monthsAgo })
    }

    private var profile: Profile? { profiles.first }
    private func target(on day: String) -> TargetSet? { targetSets.first { $0.fromDay <= day } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                header
                SigningBanner()
                PartialDaysCard()
                LargeEntriesCard(energy: profile?.energy ?? .kcal)
                if let t = target(on: dayKey()), let p = profile {
                    if ctx.dueCheckIn != nil { checkInBanner }
                    let todayN = loggedDays.filter { $0.day == dayKey() }.reduce(Nutrients.zero) { $0 + $1.nutrients }
                    let tt = ctx.dayTargets(on: dayKey()) ?? p.adjust(t.targets, on: dayKey())
                    heroWidgets(todayN, tt, p)
                    if !isPhone { quickActions }
                    ForEach(DashLayout.load(layoutJSON).sections) { sec in
                        if !sec.items.isEmpty { section(sec, todayN, tt, t, p) }
                    }
                    Button { sheet = .layout } label: { Label("Customize dashboard", systemImage: "slider.horizontal.3").font(.secondaryEmphasis) }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).frame(maxWidth: .infinity).padding(.top, Space.xs)
                }
            }
            .padding(pagePadding)
            .frame(maxWidth: isPhone ? 1000 : 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .debugScrollAnchor()
        .pageBackground()
        .largeTitle("Dashboard")
        .toolbar { headerButtons }
        .navigationDestination(item: $detail) { InsightDetailView(kind: $0) }
        .sheet(item: $sheet) { s in
            switch s {
            case .addFood: FoodLogger(day: dayKey())
            case .quickAdd: QuickAddView(day: dayKey(), entry: nil)
            case .weighIn: WeighInSheet()
            case .checkIn: CheckInView()
            case .layout: CustomizeDashboardView()
            }
        }
    }

    // MARK: Top

    private var header: some View {
        Text("\(greeting) · \(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(appLocale)))")
            .font(.secondaryEmphasis).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
    }

    @ToolbarContentBuilder private var headerButtons: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            let s = streak
            if s > 1 {
                Label("\(s)", systemImage: "flame.fill").labelStyle(.titleAndIcon)
                    .font(.numberSmall).monospacedDigit().foregroundStyle(palette.warn)
                    .help("Days in a row you've logged food").accessibilityLabel("\(s) day logging streak")
            }
            Button { sheet = .layout } label: { Label("Customize dashboard", systemImage: "slider.horizontal.3") }
            if isPhone {
                Button { openPage(.settings) } label: { Label("Profile and settings", systemImage: "person.crop.circle") }
            }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<20: return "Good afternoon"
        default: return "Good evening"
        }
    }

    /// Days in a row with food logged, counting back from today (or yesterday, if today is still empty).
    private var streak: Int {
        let days = Set(loggedDays.map(\.day))
        var d = days.contains(dayKey()) ? dayKey() : addDays(dayKey(), -1)
        var n = 0
        while days.contains(d) { n += 1; d = addDays(d, -1) }
        return n
    }

    private var checkInBanner: some View {
        Button { sheet = .checkIn } label: {
            HStack(spacing: Space.l) {
                Image(systemName: "calendar.badge.checkmark").font(.sectionTitle).foregroundStyle(palette.accent)
                    .frame(width: 44, height: 44).background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(isPhone ? "Weekly check-in ready" : "Your weekly check-in is ready").font(.cardTitle).foregroundStyle(palette.text1)
                    Text(isPhone ? "Review the week, update targets" : "See how the week went and update your targets.")
                        .font(.secondaryText).foregroundStyle(palette.text2)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(palette.text2)
            }
            .padding(Space.l)
            .modifier(CardSurface())
            .overlay(alignment: .leading) {
                // The finish's metal as a thin edge: "this needs you" without a coloured slab.
                Capsule().fill(palette.accentFill).frame(width: 3).padding(.vertical, Space.l)
            }
        }
        .buttonStyle(.plain)
    }

    private var quickActions: some View {
        HStack(spacing: Space.m) {
            QuickAction(title: "Log food", icon: "plus", color: palette.accent) { sheet = .addFood }
            QuickAction(title: "Quick add", icon: "bolt.fill", color: Macro.fat.color) { sheet = .quickAdd }
            QuickAction(title: "Weigh in", icon: "scalemass.fill", color: Macro.carbs.color) { sheet = .weighIn }
            QuickAction(title: "Train", icon: "dumbbell.fill", color: Macro.protein.color) { openPage(.workouts) }
        }
        .capType()
    }

    // MARK: Top widgets and sections

    /// Daily nutrition, the week against targets, and energy balance: swipe between them on the
    /// phone; on the Mac, the rings across the top and the other two side by side.
    private func heroPage<V: View>(_ v: V, _ i: Int) -> some View {
        v.padding(.horizontal, Space.xxs).fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroHeights[i] = $0 }
            .frame(maxHeight: .infinity, alignment: .top).tag(i)
    }

    @ViewBuilder private func heroWidgets(_ eaten: Nutrients, _ t: Targets, _ p: Profile) -> some View {
        let rings = TodayRings(eaten: eaten.targets, target: t, energy: p.energy)
        let week = Card(title: "Weekly nutrition", systemImage: "calendar") {
            WeekGrid(entries: loggedDays, target: { d in d == dayKey() ? t : (ctx.dayTargets(on: d) ?? target(on: d).map { p.adjust($0.targets, on: d) }) },
                     energy: p.energy)
        }
        let balance = Card(title: "Energy balance", systemImage: "plusminus") {
            EnergyBalanceWidget(intake: ctx.dailyIntake(), target: { d in target(on: d).map { p.adjust($0.targets, on: d).kcal } },
                                expenditure: Dictionary(ctx.expenditureEstimates().map { ($0.day, $0.kcal) }, uniquingKeysWith: { a, _ in a }),
                                energy: p.energy)
        }
        if isPhone {
            TabView(selection: $heroPage) {
                // Pinned to the top: cards of different heights don't float in the middle of the pager.
                heroPage(rings, 0)
                heroPage(week, 1)
                balance.padding(.horizontal, Space.xxs).fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroHeights[2] = $0 }
                    .frame(maxHeight: .infinity, alignment: .top).tag(2)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            #endif
            // As tall as the card showing (plus the page dots), so there's never an empty band.
            .frame(height: (heroHeights[heroPage] ?? 452) + 34)
            .animation(Motion.pick(Motion.smooth), value: heroPage)
        } else {
            rings
            HStack(alignment: .top, spacing: Space.l) { week; balance }
        }
    }

    @ViewBuilder private func section(_ sec: DashLayout.Section, _ eaten: Nutrients, _ t: Targets, _ set: TargetSet, _ p: Profile) -> some View {
        switch sec.kind {
        case .nutrition:
            Button { detail = .nutrition } label: { Label("Calories & macros history", systemImage: "chart.bar.xaxis").font(.label) }
                .buttonStyle(.borderless)
            NutritionSection(items: sec.items, remaining: sec.remaining, eaten: eaten, target: t, energy: p.energy,
                             waterMl: ctx.water(on: dayKey()).reduce(0) { $0 + $1.ml }, waterGoal: ctx.waterGoalMl, sex: p.sexValue, profile: p)
        case .insights where isPhone:
            Text(sec.kind.label).font(.sectionTitle).padding(.top, Space.s)
            let small = sec.items.filter { ["expenditure", "weight", "scale", "nutritionTrend", "energyBalance", "goal"].contains($0) }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m), GridItem(.flexible(), spacing: Space.m)], spacing: Space.m) {
                ForEach(small, id: \.self) { id in sparkCard(id, set, p) }
            }
            ForEach(sec.items.filter { !small.contains($0) }, id: \.self) { id in card(id, set, p) }
        case .insights, .habits:
            Text(sec.kind.label).font(.subsectionTitle).padding(.top, Space.s)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: isPhone ? 300 : 320), spacing: Space.l, alignment: .top)], spacing: Space.l) {
                ForEach(sec.items, id: \.self) { id in card(id, set, p) }
            }
        }
    }

    @ViewBuilder private func card(_ id: String, _ t: TargetSet, _ p: Profile) -> some View {
        switch id {
        case "expenditure": expenditureCard(t, p)
        case "weight": weightCard(p)
        case "scale", "nutritionTrend": sparkCard(id, t, p)
        case "goal": if let g = programs.first { goalCard(g, p) }
        case "week": WeekNutritionCard(entries: weekEntries, target: { d in target(on: d).map { p.adjust($0.targets, on: d) } }, energy: p.energy)
        case "training": TrainingCard()
        case "activity": ActivityCard()
        case "energyBalance":
            Card(title: "Energy balance", systemImage: "plusminus") {
                EnergyBalanceWidget(intake: ctx.dailyIntake(), target: { d in target(on: d).map { p.adjust($0.targets, on: d).kcal } },
                                    expenditure: Dictionary(ctx.expenditureEstimates().map { ($0.day, $0.kcal) }, uniquingKeysWith: { a, _ in a }),
                                    energy: p.energy)
            }
        case "score": HabitCard()
        case "supplements": SupplementsCard()
        case "proteinMeals": ProteinMealsCard(days: (1...7).map { addDays(dayKey(), -$0) })
        case "strength": StrengthRetentionCard(unit: p.weight)
        case "weighIn": HabitDotsCard(title: "Weigh-ins", color: DashItem.color("weighIn"), done: Set(weights.map(\.day)))
        case "foodLogging": HabitDotsCard(title: "Food logging", color: DashItem.color("foodLogging"), done: Set(loggedDays.map(\.day)))
        default: EmptyView()
        }
    }

    // MARK: Cards

    /// MacroFactor's small insight cards: last 7 days as a sparkline, today's value.
    @ViewBuilder private func sparkCard(_ id: String, _ t: TargetSet, _ p: Profile) -> some View {
        let week = (0..<7).map { addDays(dayKey(), $0 - 6) }
        switch id {
        case "expenditure":
            let exp = ctx.expenditureEstimates()
            let byDay = Dictionary(exp.map { ($0.day, $0.kcal) }, uniquingKeysWith: { a, _ in a })
            SparkCard(title: "Expenditure", period: "Last 7 days", values: week.compactMap { byDay[$0] }.map(p.energy.fromKcal),
                      color: palette.warn, value: number(p.energy.fromKcal(exp.last?.kcal ?? t.expenditure)), unit: p.energy.rawValue) { detail = .expenditure }
        case "weight":
            let series = trendSeries(weights.map { DayValue(day: $0.day, value: $0.trendKg) }, through: dayKey())
            let byDay = Dictionary(series.map { ($0.day, $0.trend) }, uniquingKeysWith: { a, _ in a })
            SparkCard(title: "Weight Trend", period: "Last 7 days", values: week.compactMap { byDay[$0] }.map(p.weight.fromKg),
                      color: Color.weightTone, value: series.last.map { number(p.weight.fromKg($0.trend), digits: 1) } ?? "–",
                      unit: p.weight.rawValue) { detail = .weightTrend }
                .contextMenu { Button("Weigh in", systemImage: "scalemass") { sheet = .weighIn } }
        case "energyBalance":
            let intake = ctx.dailyIntake()
            let exp = Dictionary(ctx.expenditureEstimates().map { ($0.day, $0.kcal) }, uniquingKeysWith: { a, _ in a })
            let past = week.dropLast()
            let diffs = past.compactMap { d in intake[d].flatMap { i in exp[d].map { i - $0 } } }
            let avg = diffs.isEmpty ? 0 : diffs.reduce(0, +) / Double(diffs.count)
            SparkCard(title: "Energy Balance", period: "Last 7 days", values: diffs.map(p.energy.fromKcal), color: palette.calories,
                      value: (avg > 0 ? "+" : "") + number(p.energy.fromKcal(avg)), unit: "\(p.energy.rawValue)/day") { detail = .energyBalance }
        case "scale":
            let byDay = Dictionary(weights.map { ($0.day, $0.trendKg) }, uniquingKeysWith: { a, _ in a })
            let vals = week.compactMap { byDay[$0] }.map(p.weight.fromKg)
            SparkCard(title: "Scale Weight", period: "Last 7 days", values: vals, color: palette.good,
                      value: weights.first.map { number(p.weight.fromKg($0.kg), digits: 1) } ?? "–", unit: p.weight.rawValue) { detail = .scaleWeight }
                .contextMenu { Button("Weigh in", systemImage: "scalemass") { sheet = .weighIn } }
        case "nutritionTrend":
            let intake = ctx.dailyIntake()
            let vals = week.dropLast().compactMap { intake[$0] }.map(p.energy.fromKcal)
            SparkCard(title: "Calories & Macros", period: "Last 7 days", values: vals, color: palette.calories,
                      value: vals.isEmpty ? "–" : number(vals.reduce(0, +) / Double(vals.count)), unit: "\(p.energy.rawValue) avg") { detail = .nutrition }
        case "goal":
            let series = trendSeries(weights.map { DayValue(day: $0.day, value: $0.trendKg) }, through: dayKey())
            let start = programs.first.map(\.startDay) ?? series.first?.day ?? dayKey()
            let since = series.filter { $0.day >= start }
            let step = max(1, since.count / 12)
            let pts = stride(from: 0, to: since.count, by: step).map { since[$0].trend } + (since.last.map { [$0.trend] } ?? [])
            let goalKg = p.goalWeightKg
            let first = since.first?.trend ?? 0, now = since.last?.trend ?? 0
            let done = goalKg.map { g in g != first ? max(0, min(1, (now - first) / (g - first))) : 1 }
            SparkCard(title: "Goal Progress", period: "Last \(max(1, daysBetween(start, dayKey()))) days", values: pts.map(p.weight.fromKg),
                      color: palette.good, value: done.map { "\(Int($0 * 100 + 0.5))" } ?? number(p.weight.fromKg(now - first), digits: 1),
                      unit: done == nil ? p.weight.rawValue : "%") { detail = .goal }
        default: EmptyView()
        }
    }

    private func weightCard(_ p: Profile) -> some View {
        let series = trendSeries(weights.map { DayValue(day: $0.day, value: $0.trendKg) }, through: dayKey())
        return Card(title: "Trend weight", systemImage: "scalemass") {
            if let now = series.last, let w = weights.first {
                HStack(alignment: .firstTextBaseline) {
                    Text(p.weight.format(now.trend)).font(.numberLarge).monospacedDigit()
                    Spacer()
                    if let wk = weeklyTrendChange(series) { Delta(text: signed(p.weight, wk) + "/wk", good: goodDirection(wk)) }
                }
                if series.count > 2 { Sparkline(values: series.suffix(60).map(\.trend), color: palette.accent) }
                Text("Scale \(p.weight.format(w.kg)) \(relative(w.day))").font(.secondaryText).foregroundStyle(.secondary)
            } else {
                Text("Weigh in to start your trend.").foregroundStyle(.secondary)
                Button("Weigh in") { sheet = .weighIn }
            }
        }
        .onTapGesture { detail = .weightTrend }
    }

    private func expenditureCard(_ t: TargetSet, _ p: Profile) -> some View {
        let exp = ExpenditureSummary(ctx.expenditureEstimates())
        return Card(title: "Expenditure", systemImage: "flame") {
            HStack(alignment: .firstTextBaseline) {
                Text(p.energy.format(exp?.current ?? t.expenditure)).font(.numberLarge).monospacedDigit()
                Spacer()
                Text("a day").font(.secondaryText).foregroundStyle(.secondary)
            }
            if let exp, exp.series.count > 2 {
                Sparkline(values: exp.series.suffix(60).map(\.kcal), color: Macro.calories.color)
            }
            Text(exp?.status ?? "Starting estimate.").font(.secondaryText).foregroundStyle(.secondary)
        }
        .onTapGesture { detail = .expenditure }
    }

    private func goalCard(_ g: Program, _ p: Profile) -> some View {
        let series = trendSeries(weights.map { DayValue(day: $0.day, value: $0.trendKg) }, through: dayKey())
        let weeks = max(0, Calendar.current.dateComponents([.day], from: date(fromKey: g.startDay), to: Date()).day ?? 0) / 7
        return Card(title: "Goal", systemImage: "target") {
            HStack(alignment: .firstTextBaseline) {
                Text(g.goalValue.label).font(.numberLarge)
                Spacer()
                Text("week \(weeks + 1)").font(.secondaryEmphasis).foregroundStyle(.secondary)
            }
            Text(goalDetail(g, p)).font(.secondaryText).foregroundStyle(.secondary)
            // Where the trend stood on the day this goal started (imports can move that day back).
            let startKg = series.first { $0.day >= g.startDay }?.trend ?? g.startWeightKg
            if let now = series.last?.trend, startKg > 0 {
                let change = now - startKg
                HStack {
                    Text("Since you started").font(.secondaryText)
                    Spacer()
                    Delta(text: signed(p.weight, change), good: goodDirection(change))
                }
                if let goal = p.goalWeightKg {
                    let start = startKg, total = goal - start
                    let done = total != 0 ? max(0, min(1, (now - start) / total)) : 1
                    VStack(alignment: .leading, spacing: Space.s) {
                        HStack {
                            Text("To \(p.weight.format(goal))").font(.secondaryText)
                            Spacer()
                            Text("\(Int((done * 100).rounded()))%").font(.secondaryEmphasis).monospacedDigit()
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(palette.good.opacity(0.16))
                                Capsule().fill(palette.good).frame(width: max(8, g.size.width * done))
                            }
                        }
                        .frame(height: 8)
                        if let wk = weeklyTrendChange(series), let d = goalDate(trendKg: now, goalKg: goal, weeklyKg: wk) {
                            Text("At this rate: \(d.formatted(.dateTime.day().month(.abbreviated).year().locale(appLocale)))")
                                .font(.note).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onTapGesture { detail = .goal }
    }

    /// Losing is good when you're cutting, gaining when bulking.
    private func goodDirection(_ change: Double) -> Bool? {
        switch programs.first?.goalValue {
        case .lose: return change < 0
        case .gain: return change > 0
        default: return nil
        }
    }
}

/// Monday of this week (weeks start on Monday in Spain).
func mondayThisWeek() -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2
    return cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
}

/// Lets any page send you to another (the dashboard's shortcuts).
private struct OpenPageKey: EnvironmentKey {
    static let defaultValue: (Page) -> Void = { _ in }
}

extension EnvironmentValues {
    var openPage: (Page) -> Void {
        get { self[OpenPageKey.self] }
        set { self[OpenPageKey.self] = newValue }
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
