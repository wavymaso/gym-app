import SwiftData
import SwiftUI

// A food before you log it (MacroFactor's food screen): what this amount gives you, how much of
// today's targets it takes, every nutrient against its target, and a number pad with units.

/// "1/2", "1 1/2", "150", "0,5" → a number.
func parseAmount(_ text: String) -> Double? {
    let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    guard !t.isEmpty else { return nil }
    let parts = t.split(separator: " ").map(String.init)
    var total = 0.0
    for p in parts {
        if p.contains("/") {
            let f = p.split(separator: "/")
            guard f.count == 2, let a = Double(f[0]), let b = Double(f[1]), b != 0 else { return nil }
            total += a / b
        } else {
            guard let v = Double(p) else { return nil }
            total += v
        }
    }
    return total
}

struct FoodDetailView: View {
    let food: Food
    let day: String
    var initial: (amount: Double, unit: String)? = nil
    /// The main button ("Add" to the cart, "Save", "Add to recipe").
    let primary: (title: String, action: (Double, String) -> Void)
    /// "Log Foods": add and log everything now (the logger only).
    var secondary: (title: String, action: (Double, String) -> Void)? = nil
    /// Already eaten today plus what's waiting in the cart, for "Impact on targets".
    var alreadyToday: Nutrients = .zero
    /// Editing a logged entry: its time.
    var time: Binding<Date>? = nil

    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @State private var text = ""
    @State private var unit = "g"
    @State private var keypad = false
    @State private var loaded = false
    @State private var copied = false
    @State private var cooking = false

    var body: some View {
        let n = food.nutrients(amount, unit: unit)
        let energy = profiles.first?.energy ?? .kcal
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header(n, energy)
                impact(n)
                breakdown(n)
            }
            .padding(.horizontal, Space.l).padding(.top, Space.s).padding(.bottom, Space.xl)
        }
        .pageBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) { bottom }
        .navigationTitle(food.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear(perform: load)
    }

    private var amount: Double { parseAmount(text) ?? 0 }
    private var targets: Targets? { ctx.dayTargets(on: day) }

    // MARK: Top: calories and macros

    /// Raw or cooked: what the values are per, the ratio, and what you're logging converted.
    private var cookingLine: some View {
        Button { cooking = true } label: {
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(spacing: Space.s) {
                    Image(systemName: "flame")
                    if let st = food.state {
                        Text("Values per \(st == .raw ? "raw / dry" : "cooked") weight\(food.ratio.map { " · cooked = \(number($0.value, digits: 2))× raw (\($0.measured ? "your batch" : "typical"))" } ?? "")")
                    } else {
                        Text("Raw or cooked? Set it to log either weight")
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.fine)
                }
                if unit == Cooking.cookedUnit || unit == Cooking.rawUnit {
                    Text("\(number(amount)) \(unit) = \(number(food.grams(amount, unit: unit))) g \(food.state == .raw ? "raw / dry" : "cooked")").foregroundStyle(palette.accent)
                }
            }
            .font(.note).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $cooking) { NavigationStack { CookingSheet(food: food) }.appStyle().presentationDetents([.medium, .large]) }
    }

    private func header(_ n: Nutrients, _ energy: EnergyUnit) -> some View {
        let kcal = max(n.kcal, 0.001)
        let share: [Macro: Double] = [.protein: n.protein * 4 / kcal, .fat: n.fat * 9 / kcal, .carbs: n.carbs * 4 / kcal]
        return VStack(alignment: .leading, spacing: Space.l) {
            if food.per100.looksWrong && !food.verified {
                VStack(alignment: .leading, spacing: Space.s) {
                    Label("Calories and macros don't add up (\(number(food.per100.kcal)) kcal vs \(number(food.per100.protein * 4 + food.per100.carbs * 4 + food.per100.fat * 9)) from macros per 100 g). The entry may be wrong: check the packet.",
                          systemImage: "exclamationmark.triangle.fill").font(.note).foregroundStyle(palette.warn)
                    Button("I checked: the numbers are right") { animate { food.verified = true }; ctx.commit(); Haptics.tap() }
                        .font(.label)
                }
            } else if food.verified {
                Label("Checked against the packet", systemImage: "checkmark.seal.fill").font(.note).foregroundStyle(palette.good)
            }
            HStack {
                if let b = food.brand { Text(b).font(.secondaryText).foregroundStyle(.secondary) }
                Spacer()
                if let time { DatePicker("Time", selection: time, displayedComponents: .hourAndMinute).labelsHidden() }
            }
            if !food.isLiquid { cookingLine }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(number(energy.fromKcal(n.kcal))).font(.numberHero).liveNumber(n.kcal)
                    Text(energy == .kcal ? "Calories" : "kJ").font(.secondaryText).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                ForEach([Macro.protein, .fat, .carbs], id: \.self) { m in
                    VStack(spacing: Space.xs) {
                        Text("\(Int((share[m] ?? 0) * 100 + 0.5))%").font(.fineLabel)
                            .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
                            .background(m.color.opacity(0.28), in: Capsule()).foregroundStyle(m.color)
                        Text(number(m.value(n.targets), digits: 1)).font(.numberMedium).liveNumber(m.value(n.targets))
                        Text(m.label).font(.note).foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 62)
                }
            }
            HStack(spacing: Space.l) {
                actionButton(food.isFavorite ? "heart.fill" : "heart", food.isFavorite ? "Favourite" : "Favourite") {
                    food.isFavorite.toggle(); ctx.commit()
                }
                if food.source != "custom" && food.source != "recipe" {
                    actionButton(copied ? "checkmark" : "square.and.pencil", copied ? "Copied" : "To my foods") { copyToMine() }
                }
            }
        }
    }

    private func actionButton(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Space.s) {
                Image(systemName: icon).font(.subsectionTitle).frame(width: 46, height: 40)
                    .background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                Text(title).font(.note)
            }
        }
        .buttonStyle(.plain)
    }

    private func copyToMine() {
        let f = Food(key: "custom:\(UUID().uuidString)", name: food.name, brand: food.brand, source: "custom", per100: food.per100,
                     servings: food.servings, isLiquid: food.isLiquid)
        ctx.insert(f); ctx.commit()
        animate { copied = true }
    }

    // MARK: Impact on targets

    @ViewBuilder private func impact(_ n: Nutrients) -> some View {
        if let t = targets {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Impact on Targets").font(.subsectionTitle)
                HStack {
                    ForEach(Macro.allCases, id: \.self) { m in
                        let target = max(m.value(t), 1)
                        let before = m.value(alreadyToday.targets) / target, adds = m.value(n.targets) / target
                        VStack(spacing: Space.s) {
                            ZStack {
                                Circle().stroke(Color.raisedBackground, lineWidth: 6)
                                Circle().trim(from: 0, to: min(before, 1)).stroke(m.color.opacity(0.35), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                Circle().trim(from: min(before, 1), to: min(before + adds, 1))
                                    .stroke(before + adds > 1.05 ? palette.warn : m.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                Text("\(Int(adds * 100 + 0.5))%").font(.secondaryEmphasis).monospacedDigit()
                            }
                            .frame(width: 66, height: 66)
                            .animation(Motion.snappy, value: adds)
                            Text(m.label).font(.note).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text("Of today's target. The faint part is what you've already eaten\(alreadyToday.kcal > 0 ? " or added" : "").")
                    .font(.note).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Every nutrient

    @ViewBuilder private func breakdown(_ n: Nutrients) -> some View {
        let sex = profiles.first?.sexValue ?? .male
        let p = profiles.first
        let kcal = targets?.kcal ?? 2000
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Nutrients").font(.subsectionTitle)
            group("Carbs", [
                ("Carbs", n.carbs, targets?.carbs, "g", false),
                ("Fibre", n.fiber, nutrientTarget("fiber", kcal: kcal, sex: sex, profile: p).value, "g", false),
                ("Net (non-fibre)", n.fiber.map { max(0, n.carbs - $0) }, nil, "g", false),
                ("Sugars", n.sugar, nutrientTarget("sugar", kcal: kcal, sex: sex, profile: p).value, "g", true),
            ])
            group("Fat", [
                ("Fat", n.fat, targets?.fat, "g", false),
                ("Saturated", n.satFat, nutrientTarget("satFat", kcal: kcal, sex: sex, profile: p).value, "g", true),
            ])
            group("Protein", [("Protein", n.protein, targets?.protein, "g", false)])
            let micros: [(String, Double?, Double?, String, Bool)] =
                [("Sodium", n.sodium, nutrientTarget("sodium", kcal: kcal, sex: sex, profile: p).value, "mg", true)] +
                Micro.all.compactMap { m in
                    n.micros?[m.key].map { (m.label, $0, nutrientTarget(m.key, kcal: kcal, sex: sex, profile: p).value, m.unit, m.isLimit) }
                }
            group("Vitamins & minerals", micros)
        }
    }

    @ViewBuilder private func group(_ title: String, _ rows: [(String, Double?, Double?, String, Bool)]) -> some View {
        let shown = rows.filter { $0.1 != nil }
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                Text(title).font(.cardTitle)
                ForEach(shown, id: \.0) { r in bar(r.0, r.1!, r.2, r.3, limit: r.4) }
            }
            .padding(Space.l)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        }
    }

    private func bar(_ label: String, _ v: Double, _ target: Double?, _ unit: String, limit: Bool) -> some View {
        let digits = unit == "g" && v < 100 ? 1 : 0
        let frac = target.map { v / max($0, 0.0001) } ?? 0
        let color: Color = limit ? (frac > 1 ? palette.warn : Color.secondary) : palette.good
        return VStack(spacing: Space.xs) {
            HStack {
                Text(label).font(.secondaryText)
                Spacer()
                Text(target.map { "\(number(v, digits: digits)) / \(number($0, digits: unit == "g" ? 0 : 0)) \(unit)" } ?? "\(number(v, digits: digits)) \(unit)")
                    .font(.secondaryText).monospacedDigit().foregroundStyle(.secondary)
                Text(target == nil ? "No target" : "\(Int(frac * 100 + 0.5))%").font(.secondaryEmphasis).monospacedDigit()
                    .frame(minWidth: 62, alignment: .trailing)
            }
            if target != nil {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.raisedBackground)
                        Capsule().fill(color).frame(width: g.size.width * min(frac, 1))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: Amount: the field, unit chips, the pad

    private var bottom: some View {
        VStack(spacing: Space.m) {
            HStack(spacing: Space.s) {
                Button { animate(Motion.snappy) { keypad.toggle() } } label: {
                    HStack {
                        Text(text.isEmpty ? "0" : text).font(.subsectionTitle).monospacedDigit()
                        Spacer()
                        Text(unitLabel(unit)).font(.secondaryText).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.horizontal, Space.l).frame(height: 52)
                    .background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).stroke(keypad ? palette.accent : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                if !keypad { actions }
            }
            if keypad {
                unitChips
                pad
            }
        }
        .padding(.horizontal, Space.m).padding(.top, Space.m).padding(.bottom, Space.s)
        .background(.bar)
    }

    @ViewBuilder private var actions: some View {
        if let secondary {
            Button(secondary.title) { finish(secondary.action) }
                .buttonStyle(PadButtonStyle(kind: .dark)).frame(width: 104, height: 52).disabled(amount <= 0)
        }
        Button(primary.title) { finish(primary.action) }
            .buttonStyle(PadButtonStyle(kind: .primary)).frame(width: secondary == nil ? 140 : 84, height: 52).disabled(amount <= 0)
    }

    private var unitChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(food.units, id: \.self) { u in
                    Button(unitLabel(u)) { switchUnit(to: u) }
                        .font(.secondaryEmphasis).lineLimit(1)
                        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
                        .background(u == unit ? Color.primary : Color.raisedBackground, in: Capsule())
                        .foregroundStyle(u == unit ? Color.pageBackground : .primary)
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var pad: some View {
        let keys: [[String]] = [["1", "2", "3", "/"], ["4", "5", "6", "␣"], ["7", "8", "9", "⌫"], [".", "0", "L", "A"]]
        return Grid(horizontalSpacing: Space.s, verticalSpacing: Space.s) {
            ForEach(keys, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { k in key(k) }
                }
            }
        }
    }

    @ViewBuilder private func key(_ k: String) -> some View {
        switch k {
        case "L":
            if let secondary {
                Button(secondary.title) { finish(secondary.action) }.buttonStyle(PadButtonStyle(kind: .dark)).disabled(amount <= 0)
            } else { Color.clear.frame(height: 50) }
        case "A":
            Button(primary.title) { finish(primary.action) }.buttonStyle(PadButtonStyle(kind: .primary)).disabled(amount <= 0)
        default:
            Button {
                tap(k)
            } label: {
                Group {
                    if k == "⌫" { Image(systemName: "delete.left.fill") }
                    else if k == "␣" { Image(systemName: "space") }
                    else { Text(k) }
                }
            }
            .buttonStyle(PadButtonStyle(kind: ["/", "␣", "⌫"].contains(k) ? .dark : .key))
            .accessibilityLabel(["⌫": "Delete", "␣": "Space", "/": "Fraction", ".": "Decimal point"][k] ?? k)
        }
    }

    private func tap(_ k: String) {
        #if os(iOS)
        Haptics.tap()
        #endif
        if fresh { text = ""; fresh = false }
        switch k {
        case "⌫": if !text.isEmpty { text.removeLast() }
        case "␣": if !text.isEmpty && !text.hasSuffix(" ") { text += " " }
        case ".": if !(text.split(separator: " ").last ?? "").contains(".") { text += text.isEmpty || text.hasSuffix(" ") ? "0." : "." }
        default: if text.count < 9 { text += k }
        }
    }
    /// The first key press replaces the suggested amount (like a selected field).
    @State private var fresh = true

    private func unitLabel(_ u: String) -> String {
        guard let s = food.servings.first(where: { $0.name == u }) else { return u }
        return "\(s.name) · \(number(s.grams)) \(food.baseUnit)"
    }

    /// Changing unit keeps the same weight: 150 g → 1.5 servings of 100 g.
    private func switchUnit(to u: String) {
        guard u != unit else { return }
        let grams = food.grams(amount, unit: unit)
        let per = food.grams(1, unit: u)
        unit = u
        if grams > 0, per > 0 {
            let v = grams / per
            text = number(v, digits: v >= 10 || v == v.rounded() ? 0 : 2).replacingOccurrences(of: ",", with: ".")
        }
        fresh = true
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let (a, u) = initial ?? food.suggestedAmount
        unit = food.units.contains(u) ? u : food.baseUnit
        text = number(a, digits: a == a.rounded() ? 0 : 2).replacingOccurrences(of: ",", with: ".")
        #if os(iOS)
        keypad = true
        #endif
    }

    private func finish(_ action: (Double, String) -> Void) {
        guard amount > 0 else { return }
        #if os(iOS)
        Haptics.success()
        #endif
        action(amount, unit)
    }
}

/// The number pad's keys: plain, dark (symbols, Log Foods) and the white main button.
struct PadButtonStyle: ButtonStyle {
    enum Kind { case key, dark, primary }
    let kind: Kind
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(kind == .key ? .title2.weight(.regular) : .headline)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(fillFor(configuration.isPressed), in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .opacity(configuration.isPressed && kind == .primary ? 0.75 : 1)
            .foregroundStyle(kind == .primary ? palette.onAccent : .primary)
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }

    /// The main button is brushed metal on the metal themes.
    private func fillFor(_ pressed: Bool) -> AnyShapeStyle {
        kind == .primary ? palette.accentFill : AnyShapeStyle(background.opacity(pressed ? 0.6 : 1))
    }

    private var background: Color {
        switch kind {
        case .key: return Color.primary.opacity(0.16)
        case .dark: return Color.primary.opacity(0.08)
        case .primary: return palette.onAccent
        }
    }
}
