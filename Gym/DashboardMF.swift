import Charts
import SwiftData
import SwiftUI

// MacroFactor's dashboard fundamentals, in our colours: the weekly nutrition grid, small insight
// cards with a sparkline, the wide page title, the "Search for a food" bar and the + Shortcuts sheet.

extension Font {
    /// Page titles: wide, tight, heavy, like an engraved label.
    static func pageTitle(_ size: CGFloat = 32) -> Font { .system(size: size * 0.86, weight: .bold).width(.expanded) }
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
        VStack(spacing: Space.l) {
            HStack(alignment: .top, spacing: Space.m) {
                grid(days, byDay).layoutPriority(1)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Macro.allCases, id: \.self) { m in valueCell(m, byDay[selected], target(selected)).frame(height: rowHeight + rowGap) }
                }
                .frame(width: 80, alignment: .leading)
                .padding(.top, Space.xxs)
            }
            Picker("", selection: $remaining) { Text("Consumed").tag(false); Text("Remaining").tag(true) }
                .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                .padding(.bottom, isPhone ? Space.xl : 0)            // clear of the page dots
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
        HStack(spacing: Space.xs) {
            ForEach(days, id: \.self) { d in
                Button { animate(Motion.snappy) { selected = d } } label: {
                    VStack(spacing: rowGap) {
                        ForEach(Macro.allCases, id: \.self) { m in bar(m, byDay[d], target(d), future: d > dayKey()) }
                        Text(date(fromKey: d).formatted(.dateTime.weekday(.narrow).locale(appLocale)))
                            .font(d == selected ? Font.label : Font.note).fixedSize()
                            .foregroundStyle(d == selected ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s)
                    .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
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
            RoundedRectangle(cornerRadius: Radius.xs, style: .continuous).fill(Color.raisedBackground.opacity(future ? 0.5 : 1))
            if v > 0 {
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .fill(m.color)
                    .frame(width: 8, height: min(rowHeight, (rowHeight - tickY) * frac))
                    .animation(Motion.pick(Motion.smooth), value: frac)
            }
            Capsule().fill(frac >= 0.9 && frac <= 1.1 ? palette.text1 : palette.text1.opacity(0.35))
                .frame(width: 12, height: 2.5).offset(y: -(rowHeight - tickY))
        }
        .frame(maxWidth: 24).frame(height: rowHeight)
    }

    private func valueCell(_ m: Macro, _ eaten: Targets?, _ t: Targets?) -> some View {
        let v = eaten.map { m.value($0) } ?? 0, goal = t.map { m.value($0) } ?? 0
        let shown = remaining ? goal - v : v
        let unit = m == .calories ? "" : " \(m.short)"
        return VStack(alignment: .leading, spacing: Space.hairline) {
            HStack(spacing: Space.xs) {
                Text("\(number(m == .calories ? energy.fromKcal(shown) : shown))\(unit)").font(.numberMedium).monospacedDigit()
                    .foregroundStyle(remaining && shown < 0 ? palette.warn : .primary)
                    .liveNumber(shown).lineLimit(1).minimumScaleFactor(0.7)
                if m == .calories { Image(systemName: "flame.fill").font(.note).foregroundStyle(m.color) }
            }
            Text(remaining ? (shown < 0 ? "over" : "left") : "of \(number(m == .calories ? energy.fromKcal(goal) : goal))")
                .font(.note).foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(title).font(.cardTitle).lineLimit(1).minimumScaleFactor(0.8)
                    Text(period).font(.note).foregroundStyle(.secondary)
                }
                chart.frame(height: 54)
                Divider()
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text(value).font(.numberMedium).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    Text(unit).font(.note).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.label).foregroundStyle(.tertiary)
                }
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardSurface(cornerRadius: Radius.l))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value) \(unit), \(period)")
        .accessibilityAddTraits(.isButton)
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
        } else {
            Text("Not enough data yet").font(.note).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// "Search for a food" above the tab bar (phone), like MacroFactor.
struct FoodSearchBar: View {
    let search: () -> Void
    let scan: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            Button(action: search) {
                HStack(spacing: Space.m) {
                    Image(systemName: "magnifyingglass").font(.cardTitle)
                    Text("Search for a food").foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: scan) { Image(systemName: "barcode.viewfinder").font(.subsectionTitle) }.buttonStyle(.plain)
        }
        .padding(.horizontal, Space.l).frame(height: 50)
        .modifier(GlassCapsule())
        .padding(.horizontal, Space.l).padding(.bottom, Space.s)
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
                Button { dismiss() } label: { Image(systemName: "xmark").font(.cardTitle) }.buttonStyle(.plain)
                Spacer()
                Text("Shortcuts").font(.subsectionTitle)
                Spacer()
                Image(systemName: "xmark").font(.cardTitle).hidden()
            }
            .padding(.horizontal, Space.xl).padding(.top, Space.xl).padding(.bottom, Space.l)
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
                    .padding(.vertical, Space.l)
                    row("AI photo", "camera.fill", Color.weightTone) { pick(.photo) }
                    row("Describe a meal", "quote.opening", Color.calmTone) { pick(.describe) }
                    row("Water +250 ml", "drop.fill", Color.waterTone) {
                        ctx.addWater(250)
                        #if os(iOS)
                        Haptics.success()
                        #endif
                        dismiss()
                    }
                    row("Scan a label", "text.viewfinder", palette.fat) { pick(.label) }
                    row("Recipe from a link", "link", Color.linkTone) { pick(.recipeLink) }
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
            VStack(spacing: Space.m) {
                Image(systemName: icon).font(.sectionTitle).foregroundStyle(palette.text1)
                    .frame(width: 62, height: 62)
                    .background(Color.raisedBackground, in: Circle())
                    .overlay(Circle().strokeBorder(palette.hairline, lineWidth: 0.5))
                Text(title).font(.secondaryText).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func row(_ title: String, _ icon: String, _ c: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.l) {
                Image(systemName: icon).font(.subsectionTitle).foregroundStyle(.secondary).frame(width: 30)
                Text(title).font(.bodyText)
                Spacer()
                Image(systemName: "chevron.right").font(.secondaryEmphasis).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Space.xl).padding(.vertical, Space.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider().padding(.leading, 70) }
    }
}
