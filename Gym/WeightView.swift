import Charts
import SwiftData
import SwiftUI

/// Log your weight and see the trend: scale weights as dots, the trend as a line.
struct WeightView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @Query(sort: \WeightEntry.day, order: .reverse) private var entries: [WeightEntry]
    @State private var range = ChartRange.month
    @State private var weighing = false

    var body: some View {
        let unit = profiles.first?.weight ?? .kg
        let series = trendSeries(entries.map { DayValue(day: $0.day, value: $0.trendKg) }, through: dayKey())
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero(series, unit)
                if !series.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16, alignment: .top)], spacing: 16) {
                        stat("Per week", weeklyTrendChange(series).map { signed(unit, $0) } ?? "–", "Over the last 2 weeks")
                        stat("30 days", change(series, 30).map { signed(unit, $0) } ?? "–", "Trend change")
                        stat("Since start", change(series, series.count).map { signed(unit, $0) } ?? "–",
                             "From \(date(fromKey: series[0].day).formatted(.dateTime.day().month(.abbreviated).locale(appLocale)))")
                    }
                    Card(title: "Weight", systemImage: "chart.xyaxis.line") {
                        Picker("", selection: $range) { ForEach(ChartRange.allCases, id: \.self) { Text($0.label).tag($0) } }
                            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                        WeightChart(series: range.clip(series), unit: unit, goalKg: profiles.first?.goalWeightKg).frame(height: 260)
                        HStack(spacing: 16) {
                            Label("Scale", systemImage: "circle.fill").labelStyle(DotLabel(color: Color.primary.opacity(0.4)))
                            Label("Trend", systemImage: "circle.fill").labelStyle(DotLabel(color: palette.accent))
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                BodySection()
                if !entries.isEmpty {
                    Card(title: "Weigh-ins", systemImage: "list.bullet") {
                        ForEach(entries.prefix(60)) { e in
                            HStack {
                                Text(date(fromKey: e.day).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().locale(appLocale)))
                                Spacer()
                                Text(unit.format(e.kg)).monospacedDigit()
                            }
                            .contextMenu { Button("Delete", role: .destructive) { ctx.delete(e); ctx.commit() } }
                            if e.id != entries.prefix(60).last?.id { Divider() }
                        }
                    }
                }
            }
            .padding(pagePadding)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .navigationTitle("Weight")
    }

    private func hero(_ series: [(day: String, scale: Double, trend: Double, logged: Bool)], _ unit: WeightUnit) -> some View {
        let layout = isPhone ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        return layout {
            VStack(alignment: .leading, spacing: 4) {
                Text("TREND WEIGHT").font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(series.last.map { number(unit.fromKg($0.trend), digits: 1) } ?? "–").font(.number(44)).monospacedDigit()
                        .lineLimit(1).fixedSize()
                    Text(unit.rawValue).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    if let wk = weeklyTrendChange(series) { Delta(text: signed(unit, wk) + "/wk", good: nil) }
                }
                if let w = entries.first {
                    Text("Last weigh-in \(unit.format(w.kg)) \(relative(w.day))").font(.callout).foregroundStyle(.secondary)
                }
            }
            if !isPhone { Spacer() }
            Button { weighing = true } label: {
                Label("Weigh in", systemImage: "plus").font(.headline).padding(.horizontal, 6).padding(.vertical, 4)
                    .frame(maxWidth: isPhone ? .infinity : nil)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(18)
        .modifier(CardSurface(cornerRadius: 20))
        .sheet(isPresented: $weighing) { WeighInSheet() }
    }

    private func stat(_ title: String, _ value: String, _ note: String) -> some View {
        Card(title: title) {
            Text(value).font(.number(26)).monospacedDigit()
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func change(_ s: [(day: String, scale: Double, trend: Double, logged: Bool)], _ n: Int) -> Double? {
        guard s.count >= 2 else { return nil }
        let back = s[max(0, s.count - n)]
        return s.last!.trend - back.trend
    }
}

enum ChartRange: CaseIterable {
    case month, quarter, half, year, all
    var label: String { ["1M", "3M", "6M", "1Y", "All"][Self.allCases.firstIndex(of: self)!] }
    var days: Int? { [30, 91, 182, 365, nil][Self.allCases.firstIndex(of: self)!] }
    func clip<T>(_ xs: [T]) -> [T] { days.map { Array(xs.suffix($0)) } ?? xs }
}

/// Scale weigh-ins as dots, trend as a line.
struct WeightChart: View {
    let series: [(day: String, scale: Double, trend: Double, logged: Bool)]
    let unit: WeightUnit
    var goalKg: Double? = nil

    var body: some View {
        let values = series.flatMap { [$0.trend] + ($0.logged ? [$0.scale] : []) }.map(unit.fromKg)
        let goal = goalKg.map(unit.fromKg)
        let showGoal = goal.map { g in g >= (values.min() ?? 0) - 6 && g <= (values.max() ?? 0) + 6 } ?? false
        let lo = min((values.min() ?? 0), showGoal ? goal! : .infinity) - 0.5, hi = max((values.max() ?? 1), showGoal ? goal! : -.infinity) + 0.5
        Chart {
            if showGoal, let goal {
                RuleMark(y: .value("Goal", goal)).foregroundStyle(palette.good.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .leading) { Text("Goal").font(.caption2.weight(.bold)).foregroundStyle(palette.good) }
            }
            ForEach(series.filter(\.logged), id: \.day) { p in
                PointMark(x: .value("Day", date(fromKey: p.day)), y: .value("Scale", unit.fromKg(p.scale)))
                    .foregroundStyle(Color.primary.opacity(0.4)).symbolSize(22)
            }
            ForEach(series, id: \.day) { p in
                AreaMark(x: .value("Day", date(fromKey: p.day)), yStart: .value("Low", lo), yEnd: .value("Trend", unit.fromKg(p.trend)))
                    .foregroundStyle(LinearGradient(colors: [palette.accent.opacity(0.3), palette.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
            }
            ForEach(series, id: \.day) { p in
                LineMark(x: .value("Day", date(fromKey: p.day)), y: .value("Trend", unit.fromKg(p.trend)))
                    .foregroundStyle(palette.accent).lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: lo...hi)
        .numberYAxis(digits: hi - lo < 4 ? 1 : 0)
        .dayTip("Weight", days: series.map(\.day)) { day in
            guard let p = series.first(where: { $0.day == day }) else { return [] }
            return (p.logged ? [TipRow(label: "Scale", value: unit.format(p.scale), color: Color.primary.opacity(0.5))] : [])
                + [TipRow(label: "Trend", value: unit.format(p.trend), color: palette.accent)]
        }
        .dateAxis(days: series.map(\.day))
        .appStyle()
    }
}
