import Charts
import SwiftUI

// Touch and hold (or drag) on any chart: a bubble with that day's values, like MacroFactor.

struct TipRow {
    var label: String
    var value: String
    var color: Color = .primary
}

extension View {
    /// For charts plotted by day: `days` are the plotted day keys, `rows` what to show for one.
    func dayTip(_ title: String = "Daily Total", days: [String], format: Date.FormatStyle = .dateTime.weekday(.abbreviated).day().month(.abbreviated).year(),
                rows: @escaping (String) -> [TipRow]) -> some View {
        modifier(DayTip(title: title, days: days, format: format, rows: rows))
    }

    /// For charts plotted by position (hours, sparklines): `rows` for the nearest index.
    func indexTip(count: Int, title: @escaping (Int) -> String, rows: @escaping (Int) -> [TipRow]) -> some View {
        modifier(IndexTip(count: count, title: title, rows: rows))
    }
}

private struct DayTip: ViewModifier {
    let title: String
    let days: [String]
    let format: Date.FormatStyle
    let rows: (String) -> [TipRow]
    @State private var picked: Date?
    @State private var lastDay: String?

    func body(content: Content) -> some View {
        content
            .chartXSelection(value: $picked)
            .onChange(of: picked) { _, p in
                // One tick per point crossed while scrubbing.
                guard let p else { lastDay = nil; return }
                let d = days.min(by: { abs(date(fromKey: $0).timeIntervalSince(p)) < abs(date(fromKey: $1).timeIntervalSince(p)) })
                if d != lastDay { lastDay = d; Haptics.tick() }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let p = picked, let frame = proxy.plotFrame,
                       let day = days.min(by: { abs(date(fromKey: $0).timeIntervalSince(p)) < abs(date(fromKey: $1).timeIntervalSince(p)) }),
                       let x = proxy.position(forX: date(fromKey: day)) {
                        let r = rows(day)
                        if !r.isEmpty {
                            TipBubble(title: title, subtitle: date(fromKey: day).formatted(format.locale(appLocale)), rows: r,
                                      x: geo[frame].origin.x + x, plot: geo[frame], width: geo.size.width)
                        }
                    }
                }
            }
    }
}

private struct IndexTip: ViewModifier {
    let count: Int
    let title: (Int) -> String
    let rows: (Int) -> [TipRow]
    @State private var picked: Int?

    func body(content: Content) -> some View {
        content
            .chartXSelection(value: $picked)
            .onChange(of: picked) { old, new in if new != nil, old != new { Haptics.tick() } }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let p = picked, count > 0, let frame = proxy.plotFrame {
                        let i = min(max(p, 0), count - 1)
                        if let x = proxy.position(forX: i) {
                            TipBubble(title: title(i), subtitle: nil, rows: rows(i), x: geo[frame].origin.x + x, plot: geo[frame], width: geo.size.width)
                        }
                    }
                }
            }
    }
}

private struct TipBubble: View {
    let title: String
    let subtitle: String?
    let rows: [TipRow]
    let x: CGFloat
    let plot: CGRect
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.secondary.opacity(0.7)).frame(width: 1, height: plot.height).position(x: x, y: plot.midY)
            VStack(spacing: 3) {
                if !title.isEmpty { Text(title).font(.subheadline.weight(.semibold)) }
                if let subtitle { Text(subtitle).font(.caption) }
                Divider().overlay(Color.black.opacity(0.2))
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 6) {
                        if r.color != .primary { Circle().fill(r.color).frame(width: 7, height: 7) }
                        Text("\(r.label):").font(.caption)
                        Text(r.value).font(.caption.weight(.semibold)).monospacedDigit()
                    }
                }
            }
            .padding(10).foregroundStyle(.black)
            .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .fixedSize()
            .position(x: min(max(x, 85), width - 85), y: plot.minY + 36)
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Date labels that never crowd: the format and how many depend on how long the chart spans.
    func dateAxis(days: [String]) -> some View {
        let span = days.isEmpty ? 0 : daysBetween(days.min()!, days.max()!)
        let style: Date.FormatStyle
        switch span {
        case ..<10: style = .dateTime.weekday(.abbreviated)
        case ..<120: style = .dateTime.day().month(.abbreviated)
        case ..<400: style = .dateTime.month(.abbreviated)
        default: style = .dateTime.month(.abbreviated).year(.twoDigits)
        }
        return chartXAxis {
            AxisMarks(values: .automatic(desiredCount: span < 10 ? max(span + 1, 2) : 5)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                AxisTick()
                AxisValueLabel(format: style.locale(appLocale), collisionResolution: .greedy)
            }
        }
    }
}
