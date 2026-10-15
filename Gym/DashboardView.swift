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
            VStack(alignment: .leading, spacing: 16) {
                header
                if let t = target(on: dayKey()), let p = profile {
                    if ctx.dueCheckIn != nil { checkInBanner }
                    let todayN = loggedDays.filter { $0.day == dayKey() }.reduce(Nutrients.zero) { $0 + $1.nutrients }
                    let tt = ctx.dayTargets(on: dayKey()) ?? p.adjust(t.targets, on: dayKey())
                    heroWidgets(todayN, tt, p)
                    if !isPhone { quickActions }
                    ForEach(DashLayout.load(layoutJSON).sections) { sec in
                        if !sec.items.isEmpty { section(sec, todayN, tt, t, p) }
                    }
                    Button { sheet = .layout } label: { Label("Customize dashboard", systemImage: "slider.horizontal.3").font(.callout.weight(.semibold)) }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).frame(maxWidth: .infinity).padding(.top, 4)
                }
            }
            .padding(pagePadding)
            .frame(maxWidth: isPhone ? 1000 : 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .debugScrollAnchor()
        .pageBackground()
        .navigationTitle("Dashboard")
        .navigationDestination(item: $detail) { InsightDetailView(kind: $0) }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
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
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("DASHBOARD").font(.pageTitle(isPhone ? 30 : 34)).lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(GlowStyle.on || palette.glass
                                     ? AnyShapeStyle(LinearGradient(colors: [.primary, palette.accent], startPoint: .leading, endPoint: .trailing))
                                     : AnyShapeStyle(.primary))
                Text("\(greeting) · \(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(appLocale)))")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer()
            let s = streak
            if s > 1 {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill").foregroundStyle(palette.warn)
                    Text("\(s)").font(.number(17)).monospacedDigit()
                    if !isPhone { Text("day streak").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.cardBackground, in: Capsule())
                .overlay(Capsule().stroke(palette.stroke))
                .help("Days in a row you've logged food")
            }
            Button { sheet = .layout } label: {
                Image(systemName: "slider.horizontal.3").font(.headline).frame(width: 44, height: 44)
                    .modifier(GlassCapsule())
            }
            .buttonStyle(.plain)
            if isPhone {
                // More: profile, settings, weight, insights, exercises, data
                Button { openPage(.settings) } label: {
                    Image(systemName: "person.crop.circle").font(.title3).frame(width: 44, height: 44)
                        .modifier(GlassCapsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, isPhone ? 8 : 0)
        .capType()
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
            HStack(spacing: 14) {
                Image(systemName: "calendar.badge.checkmark").font(.title2).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: Radius.m))
                VStack(alignment: .leading, spacing: 2) {
                    Text(isPhone ? "Weekly check-in ready" : "Your weekly check-in is ready").font(.headline).foregroundStyle(.white)
                    Text(isPhone ? "Review the week, update targets" : "See how the week went and update your targets.")
                        .font(.callout).foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.8))
            }
            .padding(16)
            .background(LinearGradient(colors: [palette.accent, palette.accent.mix(with: .purple, by: 0.35)], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
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
                rings.padding(.horizontal, 2).tag(0)
                week.padding(.horizontal, 2).tag(1)
                balance.padding(.horizontal, 2).tag(2)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            #endif
            .frame(height: 452)
        } else {
            rings
            HStack(alignment: .top, spacing: 16) { week; balance }
        }
    }

    @ViewBuilder private func section(_ sec: DashLayout.Section, _ eaten: Nutrients, _ t: Targets, _ set: TargetSet, _ p: Profile) -> some View {
        switch sec.kind {
        case .nutrition:
            Button { detail = .nutrition } label: { Label("Calories & macros history", systemImage: "chart.bar.xaxis").font(.caption.weight(.semibold)) }
                .buttonStyle(.borderless)
            NutritionSection(items: sec.items, remaining: sec.remaining, eaten: eaten, target: t, energy: p.energy,
                             waterMl: ctx.water(on: dayKey()).reduce(0) { $0 + $1.ml }, waterGoal: ctx.waterGoalMl, sex: p.sexValue, profile: p)
        case .insights where isPhone:
            Text(sec.kind.label).font(.title2.bold()).padding(.top, 6)
            let small = sec.items.filter { ["expenditure", "weight", "scale", "nutritionTrend", "energyBalance", "goal"].contains($0) }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(small, id: \.self) { id in sparkCard(id, set, p) }
            }
            ForEach(sec.items.filter { !small.contains($0) }, id: \.self) { id in card(id, set, p) }
        case .insights, .habits:
            Text(sec.kind.label).font(.title3.bold()).padding(.top, 6)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: isPhone ? 300 : 320), spacing: 16, alignment: .top)], spacing: 16) {
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
                    Text(p.weight.format(now.trend)).font(.number(28)).monospacedDigit()
                    Spacer()
                    if let wk = weeklyTrendChange(series) { Delta(text: signed(p.weight, wk) + "/wk", good: goodDirection(wk)) }
                }
                if series.count > 2 { Sparkline(values: series.suffix(60).map(\.trend), color: palette.accent) }
                Text("Scale \(p.weight.format(w.kg)) \(relative(w.day))").font(.callout).foregroundStyle(.secondary)
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
                Text(p.energy.format(exp?.current ?? t.expenditure)).font(.number(28)).monospacedDigit()
                Spacer()
                Text("a day").font(.callout).foregroundStyle(.secondary)
            }
            if let exp, exp.series.count > 2 {
                Sparkline(values: exp.series.suffix(60).map(\.kcal), color: Macro.calories.color)
            }
            Text(exp?.status ?? "Starting estimate.").font(.callout).foregroundStyle(.secondary)
        }
        .onTapGesture { detail = .expenditure }
    }

    private func goalCard(_ g: Program, _ p: Profile) -> some View {
        let series = trendSeries(weights.map { DayValue(day: $0.day, value: $0.trendKg) }, through: dayKey())
        let weeks = max(0, Calendar.current.dateComponents([.day], from: date(fromKey: g.startDay), to: Date()).day ?? 0) / 7
        return Card(title: "Goal", systemImage: "target") {
            HStack(alignment: .firstTextBaseline) {
                Text(g.goalValue.label).font(.number(24))
                Spacer()
                Text("week \(weeks + 1)").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(goalDetail(g, p)).font(.callout).foregroundStyle(.secondary)
            // Where the trend stood on the day this goal started (imports can move that day back).
            let startKg = series.first { $0.day >= g.startDay }?.trend ?? g.startWeightKg
            if let now = series.last?.trend, startKg > 0 {
                let change = now - startKg
                HStack {
                    Text("Since you started").font(.callout)
                    Spacer()
                    Delta(text: signed(p.weight, change), good: goodDirection(change))
                }
                if let goal = p.goalWeightKg {
                    let start = startKg, total = goal - start
                    let done = total != 0 ? max(0, min(1, (now - start) / total)) : 1
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("To \(p.weight.format(goal))").font(.callout)
                            Spacer()
                            Text("\(Int((done * 100).rounded()))%").font(.callout.weight(.bold)).monospacedDigit()
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
                                .font(.caption).foregroundStyle(.secondary)
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

/// The hero: a big calorie ring with what's left, and a ring per macro.
struct TodayRings: View {
    let eaten: Targets
    let target: Targets
    let energy: EnergyUnit

    var body: some View {
        rings.capType()
    }

    private var rings: some View {
        Card(title: "") {
            let layout = isPhone ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(spacing: 36))
            layout {
                calorieRing
                HStack(spacing: isPhone ? 0 : 28) {
                    ForEach([Macro.protein, .fat, .carbs], id: \.self) { m in
                        macroRing(m)
                        if isPhone && m != .carbs { Spacer(minLength: 0) }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, isPhone ? 0 : 8)
            .frame(maxWidth: .infinity)
        }
    }

    private var calorieRing: some View {
        let left = target.kcal - eaten.kcal
        return ZStack {
            Ring(progress: target.kcal > 0 ? eaten.kcal / target.kcal : 0, color: Macro.calories.color, lineWidth: 18)
            VStack(spacing: 0) {
                Text(number(energy.fromKcal(abs(left)))).font(.number(44)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                    .contentTransition(.numericText(value: left)).animation(Motion.snappy, value: left)
                Text("\(energy.rawValue) \(left >= 0 ? "left" : "over")").font(.subheadline.weight(.semibold))
                    .foregroundStyle(left >= 0 ? Color.secondary : palette.warn)
                Text("\(number(energy.fromKcal(eaten.kcal))) of \(energy.format(target.kcal))").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            }
            .padding(30)
        }
        .frame(width: isPhone ? 180 : 210, height: isPhone ? 180 : 210)
    }

    private func macroRing(_ m: Macro) -> some View {
        let e = m.value(eaten), t = m.value(target)
        return VStack(spacing: 8) {
            ZStack {
                Ring(progress: t > 0 ? e / t : 0, color: m.color, lineWidth: 9)
                VStack(spacing: -2) {
                    Text(number(e)).font(.number(18)).monospacedDigit()
                        .contentTransition(.numericText(value: e)).animation(Motion.snappy, value: e)
                    Text("/\(number(t))").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .frame(width: isPhone ? 72 : 92, height: isPhone ? 72 : 92)
            Text(m.label).font(.subheadline.weight(.semibold))
            Text(e <= t ? "\(number(t - e)) g left" : "\(number(e - t)) g over").font(.caption)
                .foregroundStyle(e <= t ? Color.secondary : palette.warn).monospacedDigit()
        }
    }
}

/// A big square button with an icon, for the dashboard.
struct QuickAction: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(color)
                    .frame(width: 40, height: 40).background(color.opacity(0.16), in: Circle())
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .modifier(CardSurface(cornerRadius: Radius.l))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "−0,4 kg/wk" in green when it's the way you want, orange when not, grey when it doesn't matter.
struct Delta: View {
    let text: String
    let good: Bool?
    var body: some View {
        let c: Color = good == nil ? .secondary : (good! ? palette.good : palette.warn)
        Text(text).font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(c)
            .padding(.horizontal, 8).padding(.vertical, 4).background(c.opacity(0.14), in: Capsule())
    }
}

/// The last seven days: calories against target, and averages.
struct WeekNutritionCard: View {
    let entries: [FoodEntry]
    let target: (String) -> Targets?
    let energy: EnergyUnit

    var body: some View {
        let days = (0..<7).map { addDays(dayKey(), $0 - 6) }
        let byDay = Dictionary(grouping: entries, by: \.day).mapValues { $0.reduce(Nutrients.zero) { $0 + $1.nutrients } }
        let logged = days.filter { byDay[$0] != nil && $0 != dayKey() }
        let avg = logged.isEmpty ? nil : logged.reduce(0) { $0 + (byDay[$1]?.kcal ?? 0) } / Double(logged.count)
        let avgP = logged.isEmpty ? nil : logged.reduce(0) { $0 + (byDay[$1]?.protein ?? 0) } / Double(logged.count)
        let onTarget = logged.filter { d in
            guard let t = target(d)?.kcal, t > 0, let k = byDay[d]?.kcal else { return false }
            return abs(k - t) / t <= 0.1
        }.count
        Card(title: "Last 7 days", systemImage: "chart.bar") {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days, id: \.self) { d in
                    let k = byDay[d]?.kcal ?? 0, t = target(d)?.kcal ?? 0
                    VStack(spacing: 5) {
                        GeometryReader { g in
                            let h = g.size.height, top = max(t * 1.25, k, 1)
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 5).fill(Color.raisedBackground)
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(d == dayKey() ? Macro.calories.color.opacity(0.5) : (t > 0 && abs(k - t) / t <= 0.1 ? Macro.calories.color : Macro.calories.color.opacity(0.75)))
                                    .frame(height: h * k / top)
                                if t > 0 {
                                    Rectangle().fill(.primary.opacity(0.5)).frame(height: 1.5).offset(y: -h * t / top)
                                }
                            }
                        }
                        .frame(height: 90)
                        Text(date(fromKey: d).formatted(.dateTime.weekday(.narrow).locale(appLocale)))
                            .font(.caption2.weight(d == dayKey() ? .bold : .regular)).foregroundStyle(d == dayKey() ? .primary : .secondary)
                    }
                }
            }
            HStack {
                stat("Average", avg.map { energy.format($0) } ?? "–")
                Spacer()
                stat("Protein", avgP.map { "\(number($0)) g" } ?? "–")
                Spacer()
                stat("On target", logged.isEmpty ? "–" : "\(onTarget)/\(logged.count)")
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.number(17, weight: .semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// This week's training and what's next.
struct TrainingCard: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.openPage) private var openPage
    @Query(filter: #Predicate<Workout> { $0.end != nil }, sort: \Workout.start, order: .reverse) private var finished: [Workout]
    @Query(sort: \Routine.order) private var routines: [Routine]
    @Query private var weekSets: [WorkoutSet]

    init() {
        let monday = dayKey(mondayThisWeek())
        _weekSets = Query(filter: #Predicate<WorkoutSet> { $0.day >= monday && $0.done })
    }

    var body: some View {
        let monday = dayKey(mondayThisWeek())
        let thisWeek = finished.filter { $0.day >= monday }
        let volume = weekSets.filter { $0.kindValue != .warmup }.reduce(0.0) { $0 + $1.kg * Double($1.reps) }
        let minutes = thisWeek.reduce(0) { $0 + $1.duration } / 60
        Card(title: "Training this week", systemImage: "dumbbell") {
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let d = addDays(monday, i)
                    let trained = thisWeek.contains { $0.day == d }
                    VStack(spacing: 4) {
                        Circle().fill(trained ? Macro.protein.color : Color.raisedBackground).frame(width: 26, height: 26)
                            .overlay { if trained { Image(systemName: "checkmark").font(.caption2.weight(.heavy)).foregroundStyle(.white) } }
                            .overlay { if d == dayKey() && !trained { Circle().stroke(Macro.protein.color, lineWidth: 2) } }
                        Text(date(fromKey: d).formatted(.dateTime.weekday(.narrow).locale(appLocale))).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack {
                stat("Workouts", "\(thisWeek.count)")
                Spacer()
                stat("Time", minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min")
                Spacer()
                stat("Volume", volume >= 1000 ? "\(number(volume / 1000, digits: 1)) t" : "\(number(volume)) kg")
            }
            if let next = nextRoutine {
                Button {
                    ctx.startWorkout(routine: next); openPage(.workouts)
                } label: {
                    Label("Start \(next.name)", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            } else if let last = finished.first {
                Text("Last: \(last.name), \(relative(last.day))").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    /// The routine after the one you did last (round and round), or the first.
    private var nextRoutine: Routine? {
        guard !routines.isEmpty else { return nil }
        guard let lastKey = finished.first(where: { $0.routineKey != nil })?.routineKey,
              let i = routines.firstIndex(where: { $0.key == lastKey }) else {
            if let last = finished.first, let byName = routines.firstIndex(where: { $0.name == last.name }) {
                return routines[(byName + 1) % routines.count]
            }
            return routines.first
        }
        return routines[(i + 1) % routines.count]
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.number(17, weight: .semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Monday of this week (weeks start on Monday in Spain).
func mondayThisWeek() -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2
    return cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
}

/// Log today's (or another day's) weight, from anywhere.
struct WeighInSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]
    @Query(sort: \WeightEntry.day, order: .reverse) private var weights: [WeightEntry]
    @State private var text = ""
    @State private var day = Date()
    @AppStorage("lastScale") private var scale = ""
    @FocusState private var focused: Bool

    var body: some View {
        let unit = profiles.first?.weight ?? .kg
        let names = profiles.first?.scaleNames ?? []
        NavigationStack {
            VStack(spacing: 18) {
                if !names.isEmpty {
                    Picker("Scale", selection: $scale) {
                        Text("Main").tag("")
                        ForEach(names, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 320)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("", text: $text, prompt: Text(weights.first.map { number(unit == .kg ? $0.kg : $0.kg / 0.45359237, digits: 1) } ?? "78,4"))
                        .font(.number(56)).multilineTextAlignment(.center).focused($focused).frame(maxWidth: 220)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                // From your last weigh-in, a tenth at a time: often no typing at all.
                                Button { nudge(-0.1) } label: { Text("−0,1").monospacedDigit() }
                                Button { nudge(0.1) } label: { Text("+0,1").monospacedDigit() }
                                Spacer()
                                Button("Save", action: save).fontWeight(.semibold).disabled(kg == nil)
                            }
                        }
                        #endif
                        .onSubmit(save)
                    Text(unit.rawValue).font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                }
                DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date)
                    .frame(maxWidth: 280)
                if let w = weights.first {
                    Text("Last: \(unit.format(w.kg)) \(relative(w.day))").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .pageBackground()
            .navigationTitle("Weigh in")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(kg == nil) }
            }
            .onAppear { focused = true }
        }
        #if os(macOS)
        .frame(width: 380, height: 300)
        #else
        .presentationDetents([.medium])
        #endif
        .appStyle()
    }

    private var kg: Double? {
        guard let v = parseImportNumber(text), v > 20, v < 700 else { return nil }
        return (profiles.first?.weight ?? .kg) == .kg ? v : v * 0.45359237
    }

    private func nudge(_ d: Double) {
        let unit = profiles.first?.weight ?? .kg
        let last = weights.first.map { unit == .kg ? $0.kg : $0.kg / 0.45359237 } ?? 75
        let v = ((parseImportNumber(text) ?? last) + d) * 10
        text = number(v.rounded() / 10, digits: 1)
        Haptics.tick()
    }

    private func save() {
        guard let kg else { return }
        ctx.logWeight(kg, on: dayKey(day), scale: (profiles.first?.scaleNames ?? []).contains(scale) ? scale : "")
        Haptics.tap()
        dismiss()
    }
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

/// A small line with no axes, for the dashboard tiles.
struct Sparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        Chart(Array(values.enumerated()), id: \.offset) { p in
            LineMark(x: .value("Day", p.offset), y: .value("Value", p.element))
                .foregroundStyle(color).interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .chartYScale(domain: (lo - max(0.5, (hi - lo) * 0.15))...(hi + max(0.5, (hi - lo) * 0.15)))
        .indexTip(count: values.count, title: { i in i == values.count - 1 ? "Latest" : "\(values.count - 1 - i) days ago" }) { i in
            [TipRow(label: "Value", value: number(values[i], digits: values[i] < 200 ? 1 : 0), color: color)]
        }
        .frame(height: 44)
    }
}

/// Monday to Sunday: calories each day against that day's target, today outlined, and the week's totals.
struct WeekTargetsWidget: View {
    let entries: [FoodEntry]
    let target: (String) -> Targets?
    let energy: EnergyUnit

    var body: some View {
        let monday = dayKey(mondayThisWeek())
        let days = (0..<7).map { addDays(monday, $0) }
        let byDay = Dictionary(grouping: entries.filter { $0.day >= monday }, by: \.day).mapValues { $0.reduce(Nutrients.zero) { $0 + $1.nutrients } }
        let weekEaten = days.reduce(0.0) { $0 + (byDay[$1]?.kcal ?? 0) }
        let weekTarget = days.reduce(0.0) { $0 + (target($1)?.kcal ?? 0) }
        let today = byDay[dayKey()] ?? .zero, tt = target(dayKey())
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(days, id: \.self) { d in
                    let k = byDay[d]?.kcal ?? 0, t = target(d)?.kcal ?? 0
                    let top = max(days.compactMap { target($0)?.kcal }.max() ?? 1, 1) * 1.2
                    VStack(spacing: 5) {
                        GeometryReader { g in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 5).fill(Color.raisedBackground).frame(height: g.size.height * t / top)
                                RoundedRectangle(cornerRadius: 5).fill(k >= t * 0.98 && t > 0 ? Macro.calories.color : Macro.calories.color.opacity(0.7))
                                    .frame(height: g.size.height * min(k, top) / top)
                                Rectangle().fill(k >= t && t > 0 ? Color.primary : Color.primary.opacity(0.35)).frame(height: 2)
                                    .offset(y: -g.size.height * t / top + 1).opacity(t > 0 ? 1 : 0)
                            }
                            .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
                        }
                        .padding(3)
                        .overlay { if d == dayKey() { RoundedRectangle(cornerRadius: 7).stroke(palette.accent, lineWidth: 1.5) } }
                        Text(date(fromKey: d).formatted(.dateTime.weekday(.narrow).locale(appLocale)))
                            .font(.caption2.weight(d == dayKey() ? .bold : .regular)).foregroundStyle(d == dayKey() ? .primary : .secondary)
                    }
                }
            }
            .frame(height: 150)
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("This week").font(.caption).foregroundStyle(.secondary)
                    Text("\(number(energy.fromKcal(weekEaten))) / \(energy.format(weekTarget))").font(.number(15, weight: .semibold)).monospacedDigit()
                }
                Spacer()
                if let tt {
                    HStack(spacing: 10) {
                        mini("flame.fill", today.kcal, tt.kcal, Macro.calories.color)
                        mini("P", today.protein, tt.protein, Macro.protein.color)
                        mini("F", today.fat, tt.fat, Macro.fat.color)
                        mini("C", today.carbs, tt.carbs, Macro.carbs.color)
                    }
                }
            }
        }
    }

    private func mini(_ label: String, _ v: Double, _ t: Double, _ c: Color) -> some View {
        VStack(spacing: 0) {
            if label.count > 1 { Image(systemName: label).font(.caption2).foregroundStyle(c) } else { Text(label).font(.caption2.weight(.bold)).foregroundStyle(c) }
            Text(number(v)).font(.caption.weight(.bold)).monospacedDigit()
            Text(number(t)).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
