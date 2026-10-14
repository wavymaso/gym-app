import Charts
import SwiftData
import SwiftUI

// What opens when you tap a dashboard insight card (MacroFactor's detail screens): the headline
// numbers for the range, a big chart, the range (1W … All) and grouping (day, week, month), a
// legend, then "Insights & Data": changes over 3–90 days and what each number means.

enum InsightKind: String, Identifiable, Hashable {
    case weightTrend, scaleWeight, expenditure, goal, energyBalance, nutrition
    var id: String { rawValue }
    var title: String {
        switch self {
        case .weightTrend: return "Weight Trend"
        case .scaleWeight: return "Scale Weight"
        case .expenditure: return "Expenditure"
        case .goal: return "Goal Progress"
        case .energyBalance: return "Energy Balance"
        case .nutrition: return "Calories & Macros"
        }
    }
}

enum DetailRange: String, CaseIterable, Identifiable {
    case w1 = "1W", m1 = "1M", m3 = "3M", m6 = "6M", y1 = "1Y", all = "All"
    var id: String { rawValue }
    var days: Int? { [7, 30, 91, 182, 365, nil][Self.allCases.firstIndex(of: self)!] }
}

enum InsightGrouping: String, CaseIterable, Identifiable {
    case day = "D", week = "W", month = "M"
    var id: String { rawValue }
    var label: String { ["Daily", "Weekly", "Monthly"][Self.allCases.firstIndex(of: self)!] }
}

/// A value on a day.
struct Point: Identifiable, Equatable {
    var day: String
    var value: Double
    var extra: Double? = nil          // trend line, band width, …
    var flag = false                  // holding (expenditure)
    var id: String { day }
    var when: Date { date(fromKey: day) }
}

/// Averages per week (from Monday) or month.
func grouped(_ pts: [Point], _ g: InsightGrouping) -> [Point] {
    guard g != .day else { return pts }
    var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
    let groups = Dictionary(grouping: pts) { p -> String in
        let d = date(fromKey: p.day)
        let start = g == .week ? cal.dateInterval(of: .weekOfYear, for: d)?.start : cal.dateInterval(of: .month, for: d)?.start
        return dayKey(start ?? d)
    }
    return groups.map { k, v in
        let extras = v.compactMap(\.extra)
        return Point(day: k, value: v.map(\.value).reduce(0, +) / Double(v.count),
                     extra: extras.isEmpty ? nil : extras.reduce(0, +) / Double(extras.count), flag: v.contains(where: \.flag))
    }.sorted { $0.day < $1.day }
}

struct InsightDetailView: View {
    let kind: InsightKind
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @Query(sort: \WeightEntry.day) private var weights: [WeightEntry]
    @Query(filter: #Predicate<Program> { $0.isActive }) private var programs: [Program]
    @AppStorage("insightRange") private var range: DetailRange = .m3
    @State private var grouping: InsightGrouping = .day
    @State private var zoomed = true
    @State private var goalOnTrend = true
    @State private var editing: WeightEntry?
    @State private var weighing = false
    @State private var picked: Date?                  // touch-and-drag on the chart
    @State var macro: Macro = .calories               // Calories & Macros: which one
    @State private var listLimit = 60                 // rows in the raw-data list

    var body: some View {
        let unit = profiles.first?.weight ?? .kg
        let energy = profiles.first?.energy ?? .kcal
        let all = series(unit, energy)
        let shown = clip(all)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if kind == .nutrition {
                    Picker("", selection: $macro) { ForEach(Macro.allCases, id: \.self) { Text($0.label).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden()
                }
                if kind == .goal {
                    Picker("", selection: $goalOnTrend) {
                        Label("Scale Weight", systemImage: "chart.xyaxis.line").tag(false)
                        Label("Trend Weight", systemImage: "wand.and.stars").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                headline(shown, unit, energy)
                chart(shown, unit, energy).frame(height: 300)
                if kind != .goal { controls }
                legend
                Text("Insights & Data").font(.title2.bold()).padding(.top, 6)
                if [.weightTrend, .expenditure, .scaleWeight].contains(kind) { changes(all, unit, energy) }
                explainers(all, unit, energy)
                dataSources
                if kind == .scaleWeight { weighInList(unit) } else if kind != .goal { dataList(all, unit, energy) }
                if kind == .weightTrend {
                    NavigationLink { InsightDetailView(kind: .scaleWeight) } label: {
                        HStack {
                            Label("Scale weight & all weigh-ins", systemImage: "scalemass").font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(16).modifier(CardSurface())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(pagePadding)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .debugScrollAnchor()
        .pageBackground()
        .navigationTitle(kind.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        #endif
        .toolbar {
            if kind == .scaleWeight || kind == .weightTrend {
                ToolbarItem { Button { weighing = true } label: { Label("Weigh in", systemImage: "plus") } }
            }
        }
        .sheet(isPresented: $weighing) { WeighInSheet() }
        .sheet(item: $editing) { EditWeighIn(entry: $0, unit: unit) }
    }

    private var color: Color {
        switch kind {
        case .weightTrend: return Color(hex: 0xA77BF3)
        case .scaleWeight, .goal: return palette.good
        case .expenditure: return Color(hex: 0xFF8A5B)
        case .energyBalance: return palette.calories
        case .nutrition: return macro.color
        }
    }

    private var isEnergy: Bool { [.expenditure, .energyBalance].contains(kind) || (kind == .nutrition && macro == .calories) }

    // MARK: Data

    private func series(_ unit: WeightUnit, _ energy: EnergyUnit) -> [Point] {
        let trend = trendSeries(weights.map { DayValue(day: $0.day, value: $0.trendKg) }, through: dayKey())
        switch kind {
        case .weightTrend:
            return trend.map { Point(day: $0.day, value: unit.fromKg($0.trend), extra: $0.logged ? unit.fromKg($0.scale) : nil) }
        case .scaleWeight:
            return weights.map { Point(day: $0.day, value: unit.fromKg($0.kg)) }
        case .expenditure:
            return ctx.expenditureEstimates().map {
                Point(day: $0.day, value: energy.fromKcal($0.kcal), extra: energy.fromKcal(max(40, (1 - $0.confidence) * 280)), flag: $0.paused)
            }
        case .goal:
            guard let goal = profiles.first?.goalWeightKg else { return [] }
            let start = programs.first?.startDay ?? trend.first?.day ?? dayKey()
            return trend.filter { $0.day >= start && (goalOnTrend || $0.logged) }
                .map { Point(day: $0.day, value: unit.fromKg(abs((goalOnTrend ? $0.trend : $0.scale) - goal))) }
        case .nutrition:
            let today = dayKey()
            let entries = (try? ctx.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.day < today }))) ?? []
            let partial = ctx.partialDays
            let byDay: [String: [FoodEntry]] = Dictionary(grouping: entries, by: \.day)
            var out: [Point] = []
            for (day, es) in byDay where !partial.contains(day) {
                let n: Nutrients = es.reduce(Nutrients.zero) { $0 + $1.nutrients }
                let v: Double = macro.value(n.targets)
                let tv: Double? = ctx.dayTargets(on: day).map { macro.value($0) }
                let conv: (Double) -> Double = { macro == .calories ? energy.fromKcal($0) : $0 }
                out.append(Point(day: day, value: conv(v), extra: tv.map(conv)))
            }
            return out.sorted { $0.day < $1.day }
        case .energyBalance:
            let intake = ctx.dailyIntake()
            let exp = Dictionary(ctx.expenditureEstimates().map { ($0.day, $0.kcal) }, uniquingKeysWith: { a, _ in a })
            return intake.keys.sorted().filter { $0 < dayKey() }.compactMap { d in
                exp[d].map { Point(day: d, value: energy.fromKcal(intake[d]! - $0)) }
            }
        }
    }

    private func clip(_ pts: [Point]) -> [Point] {
        if kind == .goal { return pts }
        guard let n = range.days else { return grouped(pts, grouping) }
        let from = addDays(dayKey(), -(n - 1))
        return grouped(pts.filter { $0.day >= from }, grouping)
    }

    // MARK: Headline

    @ViewBuilder private func headline(_ pts: [Point], _ unit: WeightUnit, _ energy: EnergyUnit) -> some View {
        let u = isEnergy ? energy.rawValue : kind == .nutrition ? "g" : unit.rawValue
        let digits = isEnergy || kind == .nutrition ? 0 : 1
        HStack(alignment: .top) {
            if kind == .goal {
                stat("Distance", pts.last.map { number($0.value, digits: 1) } ?? "–", u)
            } else {
                let avg = pts.isEmpty ? nil : pts.map(\.value).reduce(0, +) / Double(pts.count)
                stat(kind == .scaleWeight ? "Latest" : "Average", (kind == .scaleWeight ? pts.last?.value : avg).map { number($0, digits: digits) } ?? "–", u)
                if kind == .nutrition {
                    let withT = pts.compactMap(\.extra)
                    stat("Target", withT.isEmpty ? "–" : number(withT.reduce(0, +) / Double(withT.count)), u)
                } else if kind != .energyBalance, let f = pts.first, let l = pts.last {
                    stat("Difference", (l.value - f.value >= 0 ? "+" : "−") + number(abs(l.value - f.value), digits: digits), u)
                }
            }
            Spacer()
            if kind != .energyBalance && kind != .goal && kind != .nutrition {
                Button { withAnimation(.snappy) { zoomed.toggle() } } label: {
                    Image(systemName: zoomed ? "arrow.up.and.down.text.horizontal" : "arrow.down.and.line.horizontal.and.arrow.up")
                        .font(.headline).frame(width: 46, height: 46).modifier(GlassCapsule())
                }
                .buttonStyle(.plain)
            }
        }
        if let f = pts.first, let l = pts.last {
            Text("\(date(fromKey: f.day).formatted(.dateTime.day().month(.abbreviated).year().locale(appLocale))) – \(l.day == dayKey() ? "Today" : date(fromKey: l.day).formatted(.dateTime.day().month(.abbreviated).year().locale(appLocale)))")
                .font(.subheadline).foregroundStyle(.secondary).padding(.top, -12)
        }
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.number(34, weight: .semibold)).monospacedDigit().contentTransition(.numericText())
                Text(unit).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 150, alignment: .leading)
    }

    // MARK: Chart

    @ViewBuilder private func chart(_ pts: [Point], _ unit: WeightUnit, _ energy: EnergyUnit) -> some View {
        if pts.count < 2 {
            Text("Not enough data in this range yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if kind == .goal {
            goalChart(pts)
        } else if kind == .nutrition {
            let u = isEnergy ? energy.rawValue : "g"
            Chart {
                ForEach(pts) { p in
                    BarMark(x: .value("Day", p.when, unit: grouping == .month ? .month : grouping == .week ? .weekOfYear : .day), y: .value("Eaten", p.value))
                        .foregroundStyle(p.extra.map { abs(p.value - $0) / max($0, 1) <= 0.1 } == true ? color : color.opacity(0.55))
                }
                ForEach(pts.filter { $0.extra != nil }) { p in
                    RectangleMark(x: .value("Day", p.when, unit: grouping == .month ? .month : grouping == .week ? .weekOfYear : .day),
                                  y: .value("Target", p.extra!), width: .ratio(1), height: 2.5)
                        .foregroundStyle(Color.primary.opacity(0.85))
                }
            }
            .chartYAxis { AxisMarks(position: .trailing) { _ in AxisGridLine(stroke: StrokeStyle(dash: [4, 4])); AxisValueLabel() } }
            .dateAxis(days: pts.map(\.day))
            .dayTip(grouping == .day ? "Daily Total" : grouping == .week ? "Week Average" : "Month Average", days: pts.map(\.day)) { d in
                pts.filter { $0.day == d }.flatMap { p in
                    [TipRow(label: macro.label, value: "\(number(p.value)) \(u)", color: color)]
                        + (p.extra.map { [TipRow(label: "Target", value: "\(number($0)) \(u)")] } ?? [])
                }
            }
        } else if kind == .energyBalance {
            Chart(pts) { p in
                BarMark(x: .value("Day", p.when, unit: grouping == .month ? .month : grouping == .week ? .weekOfYear : .day), y: .value("Balance", p.value))
                    .foregroundStyle(p.value < 0 ? palette.good : palette.warn)
                RuleMark(y: .value("Zero", 0)).foregroundStyle(Color.secondary.opacity(0.4))
            }
            .chartYAxis { AxisMarks(position: .trailing) { _ in AxisGridLine(stroke: StrokeStyle(dash: [4, 4])); AxisValueLabel() } }
            .dateAxis(days: pts.map(\.day))
            .dayTip(grouping == .day ? "Daily Total" : grouping == .week ? "Week Average" : "Month Average", days: pts.map(\.day)) { d in
                pts.filter { $0.day == d }.map { TipRow(label: $0.value < 0 ? "Deficit" : "Surplus", value: signedKcal(energy.toKcal($0.value), energy),
                                                        color: $0.value < 0 ? palette.good : palette.warn) }
            }
        } else {
            let values = pts.map(\.value) + pts.compactMap { kind == .weightTrend ? $0.extra : nil }
                + (kind == .expenditure ? pts.flatMap { [$0.value - ($0.extra ?? 0), $0.value + ($0.extra ?? 0)] } : [])
            let lo = values.min()!, hi = values.max()!
            let pad = max((hi - lo) * 0.12, kind == .expenditure ? 60 : 0.3)
            Chart {
                if kind == .expenditure {
                    ForEach(pts) { p in
                        AreaMark(x: .value("Day", p.when), yStart: .value("Low", p.value - (p.extra ?? 0)), yEnd: .value("High", p.value + (p.extra ?? 0)))
                            .foregroundStyle(color.opacity(0.22)).interpolationMethod(.monotone)
                    }
                }
                if kind == .weightTrend {
                    ForEach(pts.filter { $0.extra != nil }) { p in
                        LineMark(x: .value("Day", p.when), y: .value("Scale", p.extra!), series: .value("S", "scale"))
                            .foregroundStyle(color.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1.2))
                    }
                }
                ForEach(pts) { p in
                    LineMark(x: .value("Day", p.when), y: .value(kind.title, p.value), series: .value("S", "main"))
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.6)).interpolationMethod(.monotone)
                    if pts.count <= 31 || kind == .scaleWeight && pts.count <= 60 {
                        PointMark(x: .value("Day", p.when), y: .value(kind.title, p.value))
                            .symbol { Circle().stroke(color, lineWidth: 2).background(Circle().fill(Color.pageBackground)).frame(width: 9, height: 9) }
                    }
                    if p.flag && kind == .expenditure && pts.count <= 120 {
                        PointMark(x: .value("Day", p.when), y: .value(kind.title, p.value)).symbol(.square).symbolSize(28)
                            .foregroundStyle(color.opacity(0.6))
                    }
                }
            }
            .chartYScale(domain: zoomed ? (lo - pad)...(hi + pad) : (min(0, lo))...(hi + pad))
            .chartPlotStyle { $0.clipped() }
            .dateAxis(days: pts.map(\.day))
            .chartXSelection(value: $picked)
            .chartOverlay { proxy in
                // "Daily total" bubble for the touched day
                GeometryReader { geo in
                    if let d = picked, let p = pts.min(by: { abs($0.when.timeIntervalSince(d)) < abs($1.when.timeIntervalSince(d)) }),
                       let x = proxy.position(forX: p.when), let frame = proxy.plotFrame {
                        let px = geo[frame].origin.x + x
                        Rectangle().fill(Color.secondary.opacity(0.6)).frame(width: 1).position(x: px, y: geo[frame].midY).frame(height: geo[frame].height)
                        VStack(spacing: 3) {
                            Text(grouping == .day ? "Daily Total" : grouping == .week ? "Week Average" : "Month Average").font(.subheadline.weight(.semibold))
                            Text(p.when.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().locale(appLocale))).font(.caption)
                            Divider()
                            Text("\(kind == .nutrition ? macro.label : kind.title): \(number(p.value, digits: isEnergy || kind == .nutrition ? 0 : 1)) \(isEnergy ? energy.rawValue : kind == .nutrition ? "g" : unit.rawValue)")
                                .font(.caption.weight(.semibold)).monospacedDigit()
                        }
                        .padding(10).foregroundStyle(.black)
                        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
                        .fixedSize()
                        .position(x: min(max(px, 90), geo.size.width - 90), y: geo[frame].minY + 40)
                    }
                }
            }
            .chartYAxis { AxisMarks(position: .trailing) { _ in AxisGridLine(stroke: StrokeStyle(dash: [4, 4])); AxisValueLabel() } }
            .shadow(color: GlowStyle.on ? color.opacity(0.5) : .clear, radius: 6)
        }
    }

    /// Month by month: how far from the goal, and whether each month moved towards it or away.
    private func goalChart(_ pts: [Point]) -> some View {
        let months = Dictionary(grouping: pts) { String($0.day.prefix(7)) }.sorted { $0.key < $1.key }
        var bars: [(label: String, from: Double, to: Double, towards: Bool, first: Bool)] = []
        var prev: Double?
        for (i, (_, v)) in months.enumerated() {
            let end = v.sorted { $0.day < $1.day }.last!.value
            if let p = prev { bars.append(("M\(i)", p, end, end < p, false)) } else { bars.append(("M0", 0, end, false, true)) }
            prev = end
        }
        bars.append(("Now", 0, prev ?? 0, true, true))
        let names = bars.indices.map { $0 == bars.count - 1 ? "Now" : "Month \($0)" }
        let step = max(1, bars.count / 4)
        return Chart(Array(bars.enumerated()), id: \.offset) { i, b in
            BarMark(x: .value("Month", i), yStart: .value("From", b.from), yEnd: .value("To", max(b.to, b.from + 0.02)), width: .ratio(0.7))
                .foregroundStyle(b.first ? (i == bars.count - 1 ? Color.secondary.opacity(0.5) : palette.good.opacity(0.85))
                                 : b.towards ? palette.good.mix(with: .black, by: 0.4) : palette.good.opacity(0.85))
        }
        .chartXAxis {
            AxisMarks(values: names.indices.filter { $0 % step == 0 || $0 == names.count - 1 }) { v in
                AxisValueLabel { if let i = v.as(Int.self), i < names.count { Text(names[i]) } }
            }
        }
        .chartXScale(domain: -0.6...(Double(bars.count) - 0.4))
        .indexTip(count: bars.count, title: { names[$0] }) { i in
            let b = bars[i]
            let u = profiles.first?.weight ?? .kg
            return [TipRow(label: "Distance to goal", value: u.format(u.toKg(b.to)), color: palette.good)]
                + (b.first ? [] : [TipRow(label: b.towards ? "Towards" : "Away", value: u.format(u.toKg(abs(b.to - b.from))))])
        }
        .chartYAxis { AxisMarks(position: .trailing) { _ in AxisGridLine(stroke: StrokeStyle(dash: [4, 4])); AxisValueLabel() } }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(DetailRange.allCases) { r in
                    Button { withAnimation(.snappy) { range = r } } label: {
                        Text(r.rawValue).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 40)
                            .background(range == r ? Color.primary : .clear, in: Capsule())
                            .foregroundStyle(range == r ? (palette.scheme == .dark ? Color.black : Color.white) : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3).modifier(GlassCapsule())
            Menu {
                ForEach(InsightGrouping.allCases) { g in Button(g.label) { grouping = g } }
            } label: {
                HStack(spacing: 6) { Text(grouping.rawValue).font(.subheadline.weight(.semibold)); Image(systemName: "chevron.down").font(.caption.weight(.bold)) }
                    .padding(.horizontal, 16).frame(height: 46).modifier(GlassCapsule())
            }
            .menuStyle(.button).buttonStyle(.plain)
        }
    }

    private var legend: some View {
        HStack(spacing: 22) {
            switch kind {
            case .weightTrend:
                legendItem("Scale weight", color.opacity(0.45), line: true)
                legendItem("Trend weight", color, dot: true)
            case .scaleWeight: legendItem("Scale weight", color, dot: true)
            case .expenditure:
                legendItem("Uncertainty", color.opacity(0.3), square: true)
                legendItem("Expenditure", color, dot: true)
                legendItem("Holding", color.opacity(0.6), square: true)
            case .goal:
                legendItem("Away", palette.good.opacity(0.85), square: true)
                legendItem("Towards", palette.good.mix(with: .black, by: 0.4), square: true)
            case .nutrition:
                legendItem("Eaten", color, square: true)
                legendItem("Target", Color.primary.opacity(0.7), line: true)
            case .energyBalance:
                legendItem("Deficit", palette.good, square: true)
                legendItem("Surplus", palette.warn, square: true)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .modifier(CardSurface(cornerRadius: 16))
    }

    private func legendItem(_ t: String, _ c: Color, line: Bool = false, dot: Bool = false, square: Bool = false) -> some View {
        HStack(spacing: 7) {
            if square { RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 13, height: 13) }
            else if dot { ZStack { Capsule().fill(c).frame(width: 22, height: 3); Circle().stroke(c, lineWidth: 2).background(Circle().fill(Color.cardBackground)).frame(width: 10, height: 10) } }
            else { Capsule().fill(c).frame(width: 22, height: 3) }
            Text(t)
        }
    }

    // MARK: Insights & Data

    private func changes(_ all: [Point], _ unit: WeightUnit, _ energy: EnergyUnit) -> some View {
        let u = kind == .expenditure ? energy.rawValue : unit.rawValue
        return VStack(alignment: .leading, spacing: 14) {
            Text(kind == .expenditure ? "Expenditure Changes" : "Weight Changes").font(.title3.weight(.semibold))
            ForEach([3, 7, 14, 30, 90], id: \.self) { n in
                let from = addDays(dayKey(), -n)
                let slice = all.filter { $0.day >= from }
                let change = (slice.last?.value ?? 0) - (slice.first?.value ?? 0)
                HStack(spacing: 12) {
                    Text("\(n)-day").foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                    MiniArea(values: slice.map(\.value), color: color).frame(width: 78, height: 30)
                    Text("\(change >= 0 ? "" : "−")\(number(abs(change), digits: kind == .expenditure ? 0 : 1)) \(u)").monospacedDigit()
                        .frame(minWidth: 80, alignment: .leading)
                    Spacer(minLength: 0)
                    Label(abs(change) < (kind == .expenditure ? 5 : 0.05) ? "Steady" : change > 0 ? "Increase" : "Decrease",
                          systemImage: abs(change) < (kind == .expenditure ? 5 : 0.05) ? "arrow.right" : change > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
                        .foregroundStyle(.secondary).labelStyle(TintIconLabel(color: color))
                }
                .font(.callout)
            }
        }
        .padding(16).modifier(CardSurface())
    }

    @ViewBuilder private func explainers(_ all: [Point], _ unit: WeightUnit, _ energy: EnergyUnit) -> some View {
        let trend = trendSeries(weights.map { DayValue(day: $0.day, value: $0.trendKg) }, through: dayKey())
        let weekly = weeklyTrendChange(trend, days: 21)
        VStack(spacing: 14) {
            switch kind {
            case .weightTrend, .scaleWeight:
                if let t = trend.last {
                    explainer(number(unit.fromKg(t.trend), digits: 1), unit.rawValue, "Current Weight",
                              "Our estimate of your true weight after smoothing out day-to-day changes in water and food.")
                }
                if let w = weekly {
                    explainer(number(unit.fromKg(w), digits: 2), "\(unit.rawValue) per week", "Weekly Weight Change",
                              "Your typical weekly rate of change over the past three weeks.")
                    let perDay = w * 7700 / 7
                    explainer(number(energy.fromKcal(abs(perDay))), "\(energy.rawValue) per day", perDay < 0 ? "Energy Deficit" : "Energy Surplus",
                              "Your average daily \(perDay < 0 ? "deficit" : "surplus"), from how fast your weight trend is moving.")
                    if let t = trend.last {
                        explainer(number(unit.fromKg(t.trend + w / 7 * 30), digits: 1), unit.rawValue, "30-Day Projection",
                                  "Where your weight would be in 30 days at this rate.")
                    }
                }
            case .expenditure:
                if let s = ExpenditureSummary(ctx.expenditureEstimates()) {
                    explainer(number(energy.fromKcal(s.current)), energy.rawValue, "Current Expenditure",
                              "The latest estimate of how much energy you burn a day, from your weight trend and what you eat.")
                    explainer(s.paused ? "Holding" : s.confidence < 0.6 ? "Learning" : "Updating", "", "Current Status", s.status)
                    explainer("\(Int(s.confidence * 100))", "% your data", "Confidence",
                              "How much of the estimate comes from your own logging rather than the formula it started from.")
                }
            case .goal:
                if let p = profiles.first, let goal = p.goalWeightKg {
                    explainer(number(unit.fromKg(goal), digits: 0), unit.rawValue, "Target Weight", "The goal weight you set in Strategy.")
                    let start = programs.first?.startDay ?? trend.first?.day ?? dayKey()
                    explainer("\(daysBetween(start, dayKey()))", "days", "Duration", "How long you've been on your current goal.")
                    if let t = trend.last, let w = weekly, let d = goalDate(trendKg: t.trend, goalKg: goal, weeklyKg: w) {
                        explainer(d.formatted(.dateTime.day().month(.abbreviated).locale(appLocale)), d.formatted(.dateTime.year().locale(appLocale)),
                                  "Estimated Arrival", "When you'd reach your goal if your weight keeps moving at its current rate.")
                    }
                }
            case .nutrition:
                let recent = all.filter { $0.day >= addDays(dayKey(), -30) }
                let u = isEnergy ? energy.rawValue : "g"
                if !recent.isEmpty {
                    let avg = recent.map(\.value).reduce(0, +) / Double(recent.count)
                    explainer(number(avg), "\(u) a day", "30-Day Average", "Your average \(macro.label.lowercased()) on logged days in the last month.")
                    let hit = recent.filter { p in p.extra.map { abs(p.value - $0) / max($0, 1) <= 0.1 } ?? false }.count
                    explainer("\(hit)/\(recent.count)", "days", "On Target", "Logged days within 10% of that day's target (darker bars).")
                    let weekAvg = recent.filter { $0.day >= addDays(dayKey(), -7) }
                    if !weekAvg.isEmpty {
                        let w = weekAvg.map(\.value).reduce(0, +) / Double(weekAvg.count)
                        explainer(number(w), "\(u) a day", "Last 7 Days", w >= avg ? "Above your monthly average." : "Below your monthly average.")
                    }
                }
            case .energyBalance:
                let recent = all.filter { $0.day >= addDays(dayKey(), -14) }
                if !recent.isEmpty {
                    let avg = recent.map(\.value).reduce(0, +) / Double(recent.count)
                    explainer((avg > 0 ? "+" : "") + number(avg), "\(energy.rawValue) per day", "Average Balance",
                              "Over the last 14 logged days: what you ate minus what you burned. Below zero is a deficit.")
                    let deficitDays = recent.filter { $0.value < 0 }.count
                    explainer("\(deficitDays)/\(recent.count)", "days", "Deficit Days", "Logged days in the last two weeks where you ate less than you burned.")
                }
            }
        }
        .padding(16).modifier(CardSurface())
    }

    private func explainer(_ value: String, _ unit: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 4) {
                Text(value).font(.number(26, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            }
            .frame(width: 120, height: 100)
            .background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Data sources and the raw numbers

    @ViewBuilder private var dataSources: some View {
        Text("Data Sources").font(.title2.bold()).padding(.top, 6)
        VStack(spacing: 0) {
            if [.expenditure, .energyBalance, .nutrition].contains(kind) {
                NavigationLink { FoodLogView() } label: { sourceRow("cylinder.split.1x2", "Nutrition", "Your food log") }.buttonStyle(.plain)
                Divider().padding(.leading, 58)
            }
            NavigationLink { WeightView() } label: { sourceRow("scalemass", "Scale Weight", "Weigh-ins, scales, measurements") }.buttonStyle(.plain)
        }
        .modifier(CardSurface())
    }

    private func sourceRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.title3).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 13).contentShape(Rectangle())
    }

    /// Every value, newest first, by month: the number, the day, and how it moved from the day before.
    @ViewBuilder private func dataList(_ all: [Point], _ unit: WeightUnit, _ energy: EnergyUnit) -> some View {
        let u = isEnergy ? energy.rawValue : kind == .nutrition ? "g" : unit.rawValue
        let digits = isEnergy || kind == .nutrition ? 0 : 1
        let rows = Array(all.reversed().prefix(listLimit))
        let prev = Dictionary(zip(all.dropFirst().map(\.day), all.dropLast().map(\.value)), uniquingKeysWith: { a, _ in a })
        let months = Dictionary(grouping: rows) { String($0.day.prefix(7)) }.sorted { $0.key > $1.key }
        ForEach(months, id: \.key) { _, ps in
            VStack(alignment: .leading, spacing: 10) {
                Text(date(fromKey: ps[0].day).formatted(.dateTime.month(.wide).year().locale(appLocale))).font(.title2.bold()).padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(ps) { p in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(number(p.value, digits: digits)) \(u)").font(.headline).monospacedDigit()
                                Text(date(fromKey: p.day).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(appLocale)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            change(p, prev[p.day], u, digits)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        if p.id != ps.last?.id { Divider().padding(.leading, 16) }
                    }
                }
                .modifier(CardSurface())
            }
        }
        if all.count > listLimit {
            Button("Show more") { listLimit += 90 }.buttonStyle(.bordered).buttonBorderShape(.capsule).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func change(_ p: Point, _ before: Double?, _ u: String, _ digits: Int) -> some View {
        if kind == .expenditure && p.flag {
            Label("Holding", systemImage: "square").foregroundStyle(.secondary).labelStyle(TintIconLabel(color: color))
        } else if kind == .nutrition, let t = p.extra {
            let d = p.value - t
            Text(abs(d) <= max(t * 0.1, 1) ? "On target" : "\(d > 0 ? "+" : "−")\(number(abs(d))) \(u) vs target")
                .font(.callout).foregroundStyle(abs(d) <= max(t * 0.1, 1) ? palette.good : .secondary)
        } else if let b = before {
            let d = p.value - b
            let step = digits == 0 ? 0.5 : 0.05
            Label(abs(d) < step ? "No change" : "\(d > 0 ? "+" : "−")\(number(abs(d), digits: digits)) \(u)",
                  systemImage: abs(d) < step ? "arrow.right" : d > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
                .font(.callout).foregroundStyle(.secondary).labelStyle(TintIconLabel(color: color))
        }
    }

    private func weighInList(_ unit: WeightUnit) -> some View {
        let months = Dictionary(grouping: weights.reversed().prefix(400), by: { String($0.day.prefix(7)) }).sorted { $0.key > $1.key }
        return ForEach(months, id: \.key) { _, ws in
            VStack(alignment: .leading, spacing: 10) {
                Text(date(fromKey: ws[0].day).formatted(.dateTime.month(.wide).year().locale(appLocale))).font(.title3.bold()).padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(ws) { w in
                        HStack(spacing: 14) {
                            Image(systemName: "scalemass.fill").foregroundStyle(palette.good).frame(width: 40, height: 40)
                                .background(palette.good.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(unit.format(w.kg)).font(.headline).monospacedDigit()
                                Text(date(fromKey: w.day).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(appLocale)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { editing = w } label: {
                                Image(systemName: "pencil").font(.subheadline.weight(.semibold)).frame(width: 36, height: 36).background(Color.raisedBackground, in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        if w.id != ws.last?.id { Divider().padding(.leading, 68) }
                    }
                }
                .modifier(CardSurface())
            }
        }
    }
}

/// A tiny filled sparkline for the changes table.
struct MiniArea: View {
    let values: [Double]
    let color: Color
    var body: some View {
        if values.count >= 2 {
            let lo = values.min()!, hi = values.max()!
            Chart(Array(values.enumerated()), id: \.offset) { i, v in
                AreaMark(x: .value("i", i), yStart: .value("lo", lo - (hi - lo) * 0.1), yEnd: .value("v", v)).foregroundStyle(color.opacity(0.25))
                LineMark(x: .value("i", i), y: .value("v", v)).foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.8))
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartYScale(domain: (lo - (hi - lo) * 0.1 - 0.0001)...(hi + 0.0001))
        } else {
            Capsule().fill(color.opacity(0.2)).frame(height: 2)
        }
    }
}

struct TintIconLabel: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.icon.foregroundStyle(color); configuration.title }
    }
}

/// Change or delete one weigh-in.
struct EditWeighIn: View {
    let entry: WeightEntry
    let unit: WeightUnit
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Day", value: date(fromKey: entry.day).formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(appLocale)))
                HStack {
                    TextField("Weight", text: $text)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text(unit.rawValue).foregroundStyle(.secondary)
                }
                Button("Delete weigh-in", role: .destructive) { ctx.delete(entry); ctx.commit(); dismiss() }
            }
            .themedForm()
            .navigationTitle("Weigh-in")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let v = parseNumber(text), v > 0 { entry.kg = unit.toKg(v); ctx.commit() }
                        dismiss()
                    }
                }
            }
        }
        .appStyle()
        .presentationDetents([.medium])
        .onAppear { text = number(unit.fromKg(entry.kg), digits: 1) }
    }
}
