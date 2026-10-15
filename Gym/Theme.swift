import SwiftUI
#if os(iOS)
import UIKit
#endif

// The look of the app: Appearance × Finish, from the tokens in Tokens.swift. The palette is global
// so every view, sheet and window uses the same one; changing it rebuilds the window (ThemedRoot).

/// What views read. Everything comes from the tokens: no colour is defined here.
struct Palette: Equatable {
    var tokens: Tokens
    var reduceDepth = false

    var name: String { "\(tokens.appearance.rawValue)-\(tokens.finish.rawValue)" }
    var scheme: ColorScheme { tokens.isDark ? .dark : .light }
    var background: Color { tokens.background.color }
    var grouped: Color { tokens.grouped.color }
    var surface: Color { tokens.card.color }              // cards
    var raised: Color { tokens.raised.color }              // things on cards: chips, fields, empty ring tracks
    var stroke: Color { tokens.separator.color }           // separators and outlines
    var hairline: Color { tokens.hairline }                // the top edge of a card
    var text1: Color { tokens.text1.color }
    var text2: Color { tokens.text2.color }
    var text3: Color { tokens.text3.color }
    var accent: Color { tokens.accent.color }              // the finish: buttons, main ring, selection, key numbers
    var onAccent: Color { tokens.onAccent.color }
    var calories: Color { tokens.calories.color }
    var protein: Color { tokens.protein.color }
    var fat: Color { tokens.fat.color }
    var carbs: Color { tokens.carbs.color }
    var good: Color { tokens.good.color }
    var warn: Color { tokens.over.color }                  // over target (muted amber-copper, not red)
    var under: Color { tokens.under.color }
    var record: Color { tokens.record.color }
    var warning: Color { tokens.warning.color }
    var onData: Color { tokens.onData.color }              // on a data-coloured fill
    var inverseFill: Color { text1 }                       // a selected segment: the primary text colour as a fill…
    var onInverse: Color { background }                    // …with the page tone on it

    /// Brushed metal for primary buttons, the main ring and selection: a 3-stop gradient in the finish's hue.
    var accentFill: AnyShapeStyle { reduceDepth ? AnyShapeStyle(accent) : MetalTexture.paint(tokens) }
    var titleStyle: AnyShapeStyle { AnyShapeStyle(text1) }

    static func make(_ a: Appearance, _ f: Finish, systemDark: Bool = true, reduceDepth: Bool = false) -> Palette {
        Palette(tokens: Tokens.make(a.resolved(systemDark: systemDark), f), reduceDepth: reduceDepth)
    }
    static let standard = Palette.make(.dark, .titanium)
}

/// Settings: the two choices, plus "Reduce depth". Older theme choices move over once.
enum ThemeChoice {
    static var appearance: Appearance { Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .automatic }
    static var finish: Finish { Finish(rawValue: UserDefaults.standard.string(forKey: "finish") ?? "") ?? .titanium }

    /// The old 29 themes → appearance and finish.
    static func migrate() {
        let d = UserDefaults.standard
        guard d.string(forKey: "appearance") == nil, let old = d.string(forKey: "theme") else { return }
        let light = ["daylight", "sand", "mint", "blush", "arctic", "paper", "frost"]
        let a: Appearance = old == "system" ? .automatic : old == "oled" ? .black : light.contains(old) ? .light : .dark
        let f: Finish = switch old {
            case "noir", "bronze", "mocha", "sand", "ember": .gold
            case "sterling", "arctic", "frost", "paper": .silver
            case "roseGold", "blush", "crimson", "sunsetGlass": .roseGold
            case "graphite", "oled", "neon": .graphite
            default: .titanium
        }
        d.set(a.rawValue, forKey: "appearance")
        d.set(f.rawValue, forKey: "finish")
        d.set(false, forKey: "reduceDepth")
    }
}

/// The palette in use (set by ThemedRoot before anything is drawn).
var palette: Palette = .standard

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

/// One colour per nutrient, used everywhere (rings, bars, charts, labels).
enum Macro: CaseIterable {
    case calories, protein, fat, carbs

    var label: String {
        switch self {
        case .calories: return "Calories"
        case .protein: return "Protein"
        case .fat: return "Fat"
        case .carbs: return "Carbs"
        }
    }

    var short: String {
        switch self {
        case .calories: return "Cal"
        case .protein: return "P"
        case .fat: return "F"
        case .carbs: return "C"
        }
    }

    var color: Color {
        switch self {
        case .calories: return palette.calories
        case .protein: return palette.protein
        case .fat: return palette.fat
        case .carbs: return palette.carbs
        }
    }

    func value(_ t: Targets) -> Double {
        switch self {
        case .calories: return t.kcal
        case .protein: return t.protein
        case .fat: return t.fat
        case .carbs: return t.carbs
        }
    }
}

extension Font {
    /// Big rounded numbers (calories left, weights, totals).
    /// (Scales with the Dynamic Type setting, from the size it's designed at.)
    static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        #if os(iOS)
        let scaled = min(UIFontMetrics(forTextStyle: .body).scaledValue(for: size), size * 1.6)    // big numbers grow, but stay on screen
        return .system(size: scaled, weight: weight, design: .rounded)
        #else
        return .system(size: size, weight: weight, design: .rounded)
        #endif
    }
}

extension View {
    /// Locale, colours and light/dark for a sheet or window (the Mac doesn't pass these on to sheets).
    func appStyle() -> some View {
        environment(\.locale, appLocale)
            .tint(palette.accent)
            .preferredColorScheme(palette.scheme)
    }

    /// Behind a page: the theme's colour, or the Glass backdrop.
    func pageBackground() -> some View {
        background { Color.pageBackground.ignoresSafeArea() }
    }

    /// A settings-style form on the theme's background.
    func themedForm() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .pageBackground()
            #if os(iOS)
            .pickerStyle(.navigationLink)       // choices open a page (MacroFactor-style), not a pop-up menu
            #endif
    }

    /// A list on the theme's background.
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .pageBackground()
    }
}

#if os(iOS)
let isPhone = true
let pagePadding: CGFloat = 16
#else
let isPhone = false
let pagePadding: CGFloat = 24
#endif

/// Side by side on the Mac, stacked on the iPhone.
var adaptiveStack: AnyLayout { isPhone ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 18)) }

extension Color {
    static var cardBackground: Color { palette.surface }
    static var pageBackground: Color { palette.background }
    static var raisedBackground: Color { palette.raised }
}

/// A rounded panel with a small title, like the dashboard tiles.
struct Card<Content: View>: View {
    let title: String
    var systemImage: String?
    var accessory: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                HStack {
                    Label {
                        Text(title)
                    } icon: {
                        if let systemImage { Image(systemName: systemImage) }
                    }
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let accessory { accessory }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardSurface())
    }
}

/// Every card: a tonal step up from the page, and a 0.5 pt hairline along the top edge
/// (lighter than the card in the dark, darker in the light). No shadow.
struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = Radius.l + 2

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(Color.cardBackground, in: shape)
            .overlay {
                if !palette.reduceDepth {
                    shape.strokeBorder(palette.hairline, lineWidth: 0.5)
                        .mask(LinearGradient(colors: [Tokens.maskSolid, Tokens.maskSolid.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                }
            }
    }
}

/// A floating capsule (the search bar): a material, because content scrolls behind it.
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content.background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(palette.hairline, lineWidth: 0.5))
    }
}

/// Concentric corners: a shape inside a rounded container with `padding` keeps the same curve.
func innerRadius(_ outer: CGFloat, padding: CGFloat) -> CGFloat { max(outer - padding, 2) }

/// A progress ring. Past 100% a second, darker lap shows how far over.
struct Ring: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 10
    @State private var shown: Double = 0
    @State private var closed = false          // the moment it reaches 100%: a small bounce

    /// The calorie ring is the finish's metal (a highlight travelling round it); the macros are flat.
    private var ringColors: [Color] {
        let t = palette.tokens
        if color == palette.calories || color == palette.accent, !palette.reduceDepth {
            return [t.accentLow.color, t.accent.color, t.accentHigh.color, t.accent.color]
        }
        return [color, color]
    }

    var body: some View {
        ZStack {
            Circle().stroke(palette.raised, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(shown, 0), 1))
                .stroke(AngularGradient(colors: ringColors, center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * min(max(shown, 0.01), 1))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if shown > 1 {
                Circle()
                    .trim(from: 0, to: min(shown - 1, 1))
                    .stroke(palette.warn, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))     // over target: the second lap
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
        .scaleEffect(closed && !Motion.reduceMotion ? 1.05 : 1)
        .onAppear { animate(Motion.smooth) { shown = progress } }
        .onChange(of: progress) { old, p in
            animate(Motion.smooth) { shown = p }
            if old < 0.98, p >= 0.98, p <= 1.1 {
                animate(Motion.bouncy) { closed = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { animate(Motion.smooth) { closed = false } }
            }
        }
    }
}

/// A small coloured pill: "P 142 g".
struct MacroChip: View {
    let macro: Macro
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(macro.color).frame(width: 7, height: 7)
            Text(text).monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.raisedBackground, in: Capsule())
    }
}

/// "Protein  0 / 145 g" with a coloured bar.
struct MacroBar: View {
    let macro: Macro
    let eaten: Double
    let target: Double
    let energy: EnergyUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(macro.label).font(.subheadline.weight(.medium))
                Spacer()
                HStack(spacing: 0) {
                    Text(amount(eaten)).fontWeight(.semibold)
                    Text(" / \(amount(target))").foregroundStyle(.secondary)
                }
                .font(.subheadline).monospacedDigit()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(macro.color.opacity(0.16))
                    Capsule().fill(macro.color)
                        .frame(width: max(10, g.size.width * min(1, target > 0 ? eaten / target : 0)))
                        .opacity(eaten > 0 ? 1 : 0)
                }
            }
            .frame(height: 10)
        }
    }

    private func amount(_ v: Double) -> String {
        macro == .calories ? energy.format(v) : "\(number(v)) g"
    }
}

/// Pick a label style at run time (icon only on the phone, say).
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<S: LabelStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

import Charts

extension View {
    /// Y axis numbers written our way (2360, not 2,360).
    func numberYAxis(digits: Int = 0) -> some View {
        chartYAxis {
            AxisMarks { v in
                AxisGridLine()
                AxisValueLabel { if let d = v.as(Double.self) { Text(number(d, digits: digits)) } }
            }
        }
    }
}

/// Where the day's calories come from: protein, fat and carbs as a ring.
struct MacroDonut: View {
    let targets: Targets
    var body: some View {
        let parts: [(Macro, Double)] = [(.protein, targets.protein * 4), (.fat, targets.fat * 9), (.carbs, targets.carbs * 4)]
        let total = max(1, parts.reduce(0) { $0 + $1.1 })
        ZStack {
            Chart(parts, id: \.0) { m, kcal in
                SectorMark(angle: .value("kcal", kcal), innerRadius: .ratio(0.68), angularInset: 2)
                    .cornerRadius(4).foregroundStyle(m.color)
            }
            VStack(spacing: 0) {
                Text("\(Int((parts[0].1 / total * 100).rounded()))%").font(.number(18)).foregroundStyle(Macro.protein.color)
                Text("protein").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

extension View {
    /// Testing only (-scrollBottom YES): open long pages scrolled to the end, for snapshots.
    func debugScrollAnchor() -> some View {
        #if DEBUG
        defaultScrollAnchor(UserDefaults.standard.bool(forKey: "scrollBottom") ? .bottom : UserDefaults.standard.bool(forKey: "scrollMid") ? .center : nil)
        #else
        self
        #endif
    }
}

extension View {
    /// Compact, number-heavy pieces (rings, bars, tab bar) grow with your text size only up to XXL,
    /// so they stay readable instead of wrapping digit by digit. Reading text still grows fully.
    func capType() -> some View { dynamicTypeSize(...DynamicTypeSize.xxLarge) }
}
