import Charts
import SwiftData
import SwiftUI

/// Log your weight and see the trend: scale weights as dots, the trend as a line.
struct WeightView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @Query(sort: \WeightEntry.day, order: .reverse) private var entries: [WeightEntry]
    @State private var text = ""
    @State private var day = Date()
    @State private var range = ChartRange.month

    var body: some View {
        let unit = profiles.first?.weight ?? .kg
        let series = trendSeries(entries.map { DayValue(day: $0.day, value: $0.kg) }, through: dayKey())
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(title: "Log weight", systemImage: "scalemass") {
                    HStack {
                        TextField("", text: $text, prompt: Text(unit == .kg ? "78,4" : "172,8")).frame(width: 90)
                            .onSubmit(save)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text(unit.rawValue).foregroundStyle(.secondary)
                        DatePicker("", selection: $day, in: ...Date(), displayedComponents: .date).labelsHidden()
                        Spacer()
                        Button("Save", action: save).buttonStyle(.borderedProminent).disabled(parsed == nil)
                    }
                    Text("Weigh yourself in the morning, after the bathroom, before eating. Daily is best; the trend handles the swings.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let now = series.last {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16, alignment: .top)], spacing: 16) {
                        stat("Trend weight", unit.format(now.trend), "The number to watch")
                        stat("Per week", weeklyTrendChange(series).map { signed(unit, $0) } ?? "–", "Over the last 2 weeks")
                        stat("30 days", change(series, 30).map { signed(unit, $0) } ?? "–", "Trend change")
                        stat("Since start", change(series, series.count).map { signed(unit, $0) } ?? "–",
                             "From \(date(fromKey: series[0].day).formatted(.dateTime.day().month(.abbreviated).locale(appLocale)))")
                    }
                    Card(title: "Weight", systemImage: "chart.xyaxis.line") {
                        Picker("", selection: $range) { ForEach(ChartRange.allCases, id: \.self) { Text($0.label).tag($0) } }
                            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                        WeightChart(series: range.clip(series), unit: unit).frame(height: 260)
                        HStack(spacing: 16) {
                            Label("Scale", systemImage: "circle.fill").labelStyle(DotLabel(color: Color.primary.opacity(0.4)))
                            Label("Trend", systemImage: "circle.fill").labelStyle(DotLabel(color: .accentColor))
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !entries.isEmpty {
                    Card(title: "Weigh-ins", systemImage: "list.bullet") {
                        ForEach(entries.prefix(60)) { e in
                            HStack {
                                Text(date(fromKey: e.day).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().locale(appLocale)))
                                Spacer()
                                Text(unit.format(e.kg)).monospacedDigit()
                            }
                            .contextMenu { Button("Delete", role: .destructive) { ctx.delete(e); try? ctx.save() } }
                            if e.id != entries.prefix(60).last?.id { Divider() }
                        }
                    }
                }
            }
            .padding(pagePadding)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.pageBackground)
        .navigationTitle("Weight")
    }

    private var parsed: Double? {
        let unit = profiles.first?.weight ?? .kg
        return parseNumber(text).map(unit.toKg).flatMap { (25...350).contains($0) ? $0 : nil }
    }

    private func save() {
        guard let kg = parsed else { return }
        ctx.logWeight(kg, on: dayKey(day))
        text = ""
    }

    private func stat(_ title: String, _ value: String, _ note: String) -> some View {
        Card(title: title) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func change(_ s: [(day: String, scale: Double, trend: Double, logged: Bool)], _ n: Int) -> Double? {
        guard s.count >= 2 else { return nil }
        let back = s[max(0, s.count - n)]
        return s.last!.trend - back.trend
    }
}

func signed(_ unit: WeightUnit, _ kg: Double) -> String {
    let v = unit.fromKg(kg)
    return (v > 0.005 ? "+" : v < -0.005 ? "−" : "") + "\(number(abs(v), digits: 2)) \(unit.rawValue)"
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

    var body: some View {
        let values = series.flatMap { [$0.trend] + ($0.logged ? [$0.scale] : []) }.map(unit.fromKg)
        let lo = (values.min() ?? 0) - 0.5, hi = (values.max() ?? 1) + 0.5
        Chart {
            ForEach(series.filter(\.logged), id: \.day) { p in
                PointMark(x: .value("Day", date(fromKey: p.day)), y: .value("Scale", unit.fromKg(p.scale)))
                    .foregroundStyle(Color.primary.opacity(0.4)).symbolSize(22)
            }
            ForEach(series, id: \.day) { p in
                LineMark(x: .value("Day", date(fromKey: p.day)), y: .value("Trend", unit.fromKg(p.trend)))
                    .foregroundStyle(Color.accentColor).lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: lo...hi)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(appLocale)) } }
        .environment(\.locale, appLocale)
    }
}
