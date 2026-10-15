import Charts
import SwiftData
import SwiftUI

// MacroFactor's dashboard fundamentals, in our colours: the weekly nutrition grid, small insight
// cards with a sparkline, the wide page title, the "Search for a food" bar and the + Shortcuts sheet.

extension Font {
    /// Wide, heavy page titles ("DASHBOARD").
    static func pageTitle(_ size: CGFloat = 32) -> Font { .system(size: size, weight: .black).width(.expanded) }
}

/// Monday to Sunday × calories, protein, fat, carbs: a bar per day against its target (the tick).
struct WeekGrid: View {
    let entries: [FoodEntry]
    let target: (String) -> Targets?
    let energy: EnergyUnit
    @AppStorage("weekGridRemaining") private var remaining = false
    @State private var selected = dayKey()

    var body: some View {
        let days = weekDays
        let byDay = Dictionary(grouping: entries.filter { days.contains($0.day) }, by: \.day)
            .mapValues { $0.reduce(Nutrients.zero) { $0 + $1.nutrients }.targets }
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                grid(days, byDay).layoutPriority(1)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Macro.allCases, id: \.self) { m in valueCell(m, byDay[selected], target(selected)).frame(height: rowHeight + rowGap) }
                }
                .frame(width: 80, alignment: .leading)
                .padding(.top, 2)
            }
            Picker("", selection: $remaining) { Text("Consumed").tag(false); Text("Remaining").tag(true) }
                .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                .padding(.bottom, isPhone ? 22 : 0)            // clear of the page dots
        }
    }

    private let rowHeight: CGFloat = 52
    private let rowGap: CGFloat = 10

    private var weekDays: [String] {
        let today = date(fromKey: dayKey())
        let weekday = (Calendar.current.component(.weekday, from: today) + 5) % 7      // Monday = 0
        let monday = addDays(dayKey(), -weekday)
        return (0..<7).map { addDays(monday, $0) }
    }

    private func grid(_ days: [String], _ byDay: [String: Targets]) -> some View {
        HStack(spacing: 3) {
            ForEach(days, id: \.self) { d in
                Button { animate(Motion.snappy) { selected = d } } label: {
                    VStack(spacing: rowGap) {
                        ForEach(Macro.allCases, id: \.self) { m in bar(m, byDay[d], target(d), future: d > dayKey()) }
                        Text(date(fromKey: d).formatted(.dateTime.weekday(.narrow).locale(appLocale)))
                            .font(.caption.weight(d == selected ? .bold : .regular)).fixedSize()
                            .foregroundStyle(d == selected ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(d == selected ? Color.primary.opacity(0.85) : .clear, lineWidth: 2))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func bar(_ m: Macro, _ eaten: Targets?, _ t: Targets?, future: Bool) -> some View {
        let v = eaten.map { m.value($0) } ?? 0, goal = t.map { m.value($0) } ?? 0
        let frac = goal > 0 ? v / goal : 0
        let tickY = rowHeight * 0.18                     // the target sits near the top; over it fills past the tick
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.raisedBackground.opacity(future ? 0.5 : 1))
            if v > 0 {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(LinearGradient(colors: [m.color, m.color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 8, height: min(rowHeight, (rowHeight - tickY) * frac))
                    .animation(Motion.pick(Motion.smooth), value: frac)
                    .shadow(color: GlowStyle.on ? m.color.opacity(0.6) : .clear, radius: 5)
            }
            Capsule().fill(frac >= 0.9 && frac <= 1.1 ? Color.white : Color.white.opacity(0.35))
                .frame(width: 12, height: 2.5).offset(y: -(rowHeight - tickY))
        }
        .frame(maxWidth: 24).frame(height: rowHeight)
    }

    private func valueCell(_ m: Macro, _ eaten: Targets?, _ t: Targets?) -> some View {
        let v = eaten.map { m.value($0) } ?? 0, goal = t.map { m.value($0) } ?? 0
        let shown = remaining ? goal - v : v
        let unit = m == .calories ? "" : " \(m.short)"
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text("\(number(m == .calories ? energy.fromKcal(shown) : shown))\(unit)").font(.number(20, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(remaining && shown < 0 ? palette.warn : .primary)
                    .liveNumber(shown).lineLimit(1).minimumScaleFactor(0.7)
                if m == .calories { Image(systemName: "flame.fill").font(.caption).foregroundStyle(m.color) }
            }
            Text(remaining ? (shown < 0 ? "over" : "left") : "of \(number(m == .calories ? energy.fromKcal(goal) : goal))")
                .font(.caption).foregroundStyle(.secondary)
        }
        .animation(Motion.snappy, value: remaining)
    }
}

/// A small insight card: title, period, a sparkline with dots, the current value.
struct SparkCard: View {
    let title: String
    let period: String
    let values: [Double]
    let color: Color
    let value: String
    let unit: String
    var band: [Double]? = nil
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    Text(period).font(.caption).foregroundStyle(.secondary)
                }
                chart.frame(height: 54)
                Divider()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.number(22, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardSurface(cornerRadius: 20))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var chart: some View {
        if values.count >= 2 {
            let lo = values.min()!, hi = values.max()!
            let pad = max((hi - lo) * 0.25, 0.5)
            Chart(Array(values.enumerated()), id: \.offset) { p in
                LineMark(x: .value("Day", p.offset), y: .value("V", p.element))
                    .foregroundStyle(color).interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 2.5))
                PointMark(x: .value("Day", p.offset), y: .value("V", p.element))
                    .symbol { Circle().stroke(color, lineWidth: 2).background(Circle().fill(Color.cardBackground)).frame(width: 9, height: 9) }
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartYScale(domain: (lo - pad)...(hi + pad))
            .indexTip(count: values.count, title: { i in i == values.count - 1 ? "Latest" : "\(values.count - 1 - i) days ago" }) { i in
                [TipRow(label: title, value: "\(number(values[i], digits: unit == "kg" || unit == "lb" ? 1 : 0)) \(unit)", color: color)]
            }
            .shadow(color: GlowStyle.on ? color.opacity(0.5) : .clear, radius: 6)
        } else {
            Text("Not enough data yet").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// "Search for a food" above the tab bar (phone), like MacroFactor.
struct FoodSearchBar: View {
    let search: () -> Void
    let scan: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: search) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.headline)
                    Text("Search for a food").foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: scan) { Image(systemName: "barcode.viewfinder").font(.title3) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 18).frame(height: 50)
        .modifier(GlassCapsule())
        .padding(.horizontal, 16).padding(.bottom, 8)
    }
}

/// The + button: MacroFactor's Shortcuts sheet (four big ones, then a list).
struct ShortcutsSheet: View {
    let choose: (QuickSheet) -> Void
    let train: () -> Void
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.headline) }.buttonStyle(.plain)
                Spacer()
                Text("Shortcuts").font(.title3.weight(.bold))
                Spacer()
                Image(systemName: "xmark").font(.headline).hidden()
            }
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 14)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        big("Weight", "scalemass.fill", DashItem.color("weighIn")) { pick(.weighIn) }
                        big("Search", "magnifyingglass", palette.accent) { pick(.food) }
                        #if os(iOS)
                        big("Barcode", "barcode.viewfinder", palette.carbs) { pick(.scan) }
                        #endif
                        big("Quick Add", "bolt.fill", palette.fat) { pick(.quickAdd) }
                    }
                    .padding(.vertical, 18)
                    row("AI photo", "camera.fill", Color(hex: 0xA77BF3)) { pick(.photo) }
                    row("Describe a meal", "quote.opening", Color(hex: 0x7B8CF3)) { pick(.describe) }
                    row("Water +250 ml", "drop.fill", Color(hex: 0x3BB2F6)) {
                        ctx.addWater(250)
                        #if os(iOS)
                        Haptics.success()
                        #endif
                        dismiss()
                    }
                    row("Scan a label", "text.viewfinder", palette.fat) { pick(.label) }
                    row("Recipe from a link", "link", Color(hex: 0xFF5C86)) { pick(.recipeLink) }
                    row("Start a workout", "dumbbell.fill", palette.protein) { dismiss(); train() }
                }
            }
        }
        .pageBackground()
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 440, height: 520)
        #endif
        .appStyle()
    }

    private func pick(_ s: QuickSheet) { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { choose(s) } }

    private func big(_ title: String, _ icon: String, _ c: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.title2.weight(.semibold)).foregroundStyle(c)
                    .frame(width: 62, height: 62)
                    .background(c.opacity(0.16), in: Circle())
                    .overlay(Circle().stroke(c.opacity(0.25)))
                Text(title).font(.subheadline).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func row(_ title: String, _ icon: String, _ c: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon).font(.title3).foregroundStyle(c).frame(width: 30)
                Text(title).font(.body)
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 22).padding(.vertical, 17)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 70) }
    }
}
