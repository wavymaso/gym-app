import SwiftUI
#if os(iOS)
import UIKit
#endif

// The look of the app: themes (dark and bold by default), colours, cards, rings.
// The chosen palette is global so every view, sheet and window uses the same one;
// changing theme rebuilds the window (see ThemedRoot in GymApp.swift).

enum AppTheme: String, CaseIterable, Identifiable {
    // Dark
    case midnight, graphite, ocean, oled, forest, ember, crimson, amethyst, mocha, nord, neon, slate
    // Light
    case daylight, sand, mint, blush, arctic, paper
    // Glass
    case glass, aurora, sunsetGlass, oceanGlass, frost
    // Follows the system
    case system
    var id: String { rawValue }

    enum Group: String, CaseIterable { case dark = "Dark", light = "Light", glass = "Glass" }
    var group: Group {
        switch self {
        case .daylight, .sand, .mint, .blush, .arctic, .paper, .system: return .light
        case .glass, .aurora, .sunsetGlass, .oceanGlass, .frost: return .glass
        default: return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "Automatic"
        case .oled: return "OLED Black"
        case .sunsetGlass: return "Sunset Glass"
        case .oceanGlass: return "Ocean Glass"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    var detail: String {
        switch self {
        case .midnight: return "Near-black, electric colours"
        case .graphite: return "Dark grey, warm orange"
        case .ocean: return "Deep blue, teal"
        case .oled: return "Pure black, saves battery on your iPhone"
        case .forest: return "Deep green, earthy and calm"
        case .ember: return "Charcoal and fire orange"
        case .crimson: return "Dark with blood red, aggressive"
        case .amethyst: return "Deep purple, violet and pink"
        case .mocha: return "Coffee browns, warm and soft"
        case .nord: return "Cool arctic greys and pastel blues"
        case .neon: return "Black with cyber pink and cyan"
        case .slate: return "Blue-grey, muted and professional"
        case .daylight: return "Light and clean"
        case .sand: return "Warm cream and terracotta"
        case .mint: return "Fresh white and mint green"
        case .blush: return "Soft pink and rose"
        case .arctic: return "Icy white and blue"
        case .paper: return "Off-white, ink black, minimal"
        case .glass: return "Apple's Liquid Glass over colour"
        case .aurora: return "Glass over northern lights greens and purples"
        case .sunsetGlass: return "Glass over orange, pink and violet"
        case .oceanGlass: return "Glass over deep sea blues and teal"
        case .frost: return "Light Liquid Glass over pale colour"
        case .system: return "Midnight at night, Daylight by day"
        }
    }

    /// The palette to use, given whether the system is in dark mode (only matters for Automatic).
    func palette(systemDark: Bool) -> Palette {
        switch self {
        case .system: return systemDark ? .midnight : .daylight
        default: return Palette.all[self] ?? .midnight
        }
    }

    /// nil lets the system decide (Automatic).
    var scheme: ColorScheme? {
        if self == .system { return nil }
        return Palette.all[self]?.scheme ?? .dark
    }
}

struct Palette: Equatable {
    var name: String
    var scheme: ColorScheme
    var background: Color          // behind everything
    var surface: Color             // cards
    var raised: Color              // things on cards: chips, fields, empty ring tracks
    var stroke: Color              // card outlines
    var accent: Color              // buttons, selection, links
    var calories: Color
    var protein: Color
    var fat: Color
    var carbs: Color
    var good = Color(hex: 0x34C77B)
    var warn = Color(hex: 0xFF9F2E)
    var glass = false              // cards are Liquid Glass over a colourful backdrop

    static let midnight = Palette(name: "midnight", scheme: .dark, background: Color(hex: 0x09090C), surface: Color(hex: 0x15151B),
                                  raised: Color(hex: 0x22222B), stroke: .white.opacity(0.06), accent: Color(hex: 0x4C7DFF),
                                  calories: Color(hex: 0x4C7DFF), protein: Color(hex: 0xFF4F70), fat: Color(hex: 0xFFB830),
                                  carbs: Color(hex: 0x2FD39A))
    static let graphite = Palette(name: "graphite", scheme: .dark, background: Color(hex: 0x111111), surface: Color(hex: 0x1D1D1F),
                                  raised: Color(hex: 0x2A2A2D), stroke: .white.opacity(0.07), accent: Color(hex: 0xFF7A1A),
                                  calories: Color(hex: 0xFF7A1A), protein: Color(hex: 0xFF4D5E), fat: Color(hex: 0xFFD04A),
                                  carbs: Color(hex: 0x4CC38A))
    static let ocean = Palette(name: "ocean", scheme: .dark, background: Color(hex: 0x06111D), surface: Color(hex: 0x0E1F31),
                               raised: Color(hex: 0x172D45), stroke: .white.opacity(0.07), accent: Color(hex: 0x14B8C8),
                               calories: Color(hex: 0x22C7DA), protein: Color(hex: 0xFF6A88), fat: Color(hex: 0xFFC65A),
                               carbs: Color(hex: 0x7BE38E))
    static let glass = Palette(name: "glass", scheme: .dark, background: Color(hex: 0x0A0D1F), surface: .white.opacity(0.07),
                               raised: .white.opacity(0.11), stroke: .white.opacity(0.14), accent: Color(hex: 0x7A92FF),
                               calories: Color(hex: 0x6F8CFF), protein: Color(hex: 0xFF5C86), fat: Color(hex: 0xFFC247),
                               carbs: Color(hex: 0x3EE0A8), glass: true)
    static let daylight = Palette(name: "daylight", scheme: .light, background: Color(hex: 0xF2F2F7), surface: .white,
                                  raised: Color(hex: 0xEDEDF2), stroke: .black.opacity(0.06), accent: Color(hex: 0x2F6BFF),
                                  calories: Color(hex: 0x2F6BFF), protein: Color(hex: 0xE8445A), fat: Color(hex: 0xEFA300),
                                  carbs: Color(hex: 0x1FA774))
}

extension Palette {
    /// A palette from hex colours; the outline follows light or dark.
    static func make(_ name: String, dark: Bool = true, bg: UInt32, surface: UInt32, raised: UInt32, accent: UInt32,
                     kcal: UInt32? = nil, protein: UInt32, fat: UInt32, carbs: UInt32, glass: Bool = false) -> Palette {
        var p = Palette(name: name, scheme: dark ? .dark : .light, background: Color(hex: bg), surface: Color(hex: surface),
                        raised: Color(hex: raised), stroke: dark ? .white.opacity(0.07) : .black.opacity(0.07), accent: Color(hex: accent),
                        calories: Color(hex: kcal ?? accent), protein: Color(hex: protein), fat: Color(hex: fat), carbs: Color(hex: carbs))
        if glass {
            p.glass = true
            p.surface = dark ? .white.opacity(0.07) : .white.opacity(0.45)
            p.raised = dark ? .white.opacity(0.11) : .black.opacity(0.06)
            p.stroke = dark ? .white.opacity(0.14) : .white.opacity(0.6)
        }
        return p
    }

    static let all: [AppTheme: Palette] = [
        .midnight: .midnight, .graphite: .graphite, .ocean: .ocean, .glass: .glass, .daylight: .daylight,
        .oled: make("oled", bg: 0x000000, surface: 0x0D0D0F, raised: 0x1C1C1F, accent: 0x5E8BFF, protein: 0xFF4F70, fat: 0xFFB830, carbs: 0x2FD39A),
        .forest: make("forest", bg: 0x0B1410, surface: 0x14211A, raised: 0x1F3127, accent: 0x4CC38A, kcal: 0x8FD16A, protein: 0xFF7A6B, fat: 0xF2C14E, carbs: 0x3DB9A6),
        .ember: make("ember", bg: 0x120D0B, surface: 0x1E1614, raised: 0x2C211D, accent: 0xFF6A2B, protein: 0xFF3D5A, fat: 0xFFC233, carbs: 0x5CCB8A),
        .crimson: make("crimson", bg: 0x0E0809, surface: 0x1B1113, raised: 0x2A1A1D, accent: 0xE5243B, kcal: 0xFF5A5F, protein: 0xFF8FA3, fat: 0xFFB347, carbs: 0x6FD3A0),
        .amethyst: make("amethyst", bg: 0x0F0B17, surface: 0x1B1426, raised: 0x2A1F3B, accent: 0xA77BF3, protein: 0xFF6FB5, fat: 0xFFC56E, carbs: 0x5FD9C0),
        .mocha: make("mocha", bg: 0x15100D, surface: 0x221A15, raised: 0x33271F, accent: 0xD9A066, protein: 0xE8746B, fat: 0xF0C987, carbs: 0x9CC58C),
        .nord: make("nord", bg: 0x232831, surface: 0x2E3440, raised: 0x3B4252, accent: 0x88C0D0, kcal: 0x81A1C1, protein: 0xBF616A, fat: 0xEBCB8B, carbs: 0xA3BE8C),
        .neon: make("neon", bg: 0x05050A, surface: 0x101018, raised: 0x1B1B28, accent: 0x00E5FF, protein: 0xFF2D95, fat: 0xFFE600, carbs: 0x39FF88),
        .slate: make("slate", bg: 0x101419, surface: 0x1A2028, raised: 0x262E39, accent: 0x6E9CD2, protein: 0xE07A8A, fat: 0xE3B65E, carbs: 0x63C39B),
        .sand: make("sand", dark: false, bg: 0xF6F0E6, surface: 0xFFFBF5, raised: 0xEDE4D6, accent: 0xC8643B, protein: 0xD9485F, fat: 0xD99A1E, carbs: 0x3E9B6E),
        .mint: make("mint", dark: false, bg: 0xEEF7F2, surface: 0xFFFFFF, raised: 0xE1EFE7, accent: 0x1FA37A, protein: 0xE5536B, fat: 0xE0A21B, carbs: 0x2E86DE),
        .blush: make("blush", dark: false, bg: 0xFBEFF2, surface: 0xFFFFFF, raised: 0xF4E0E6, accent: 0xE0527F, protein: 0xC2185B, fat: 0xF0A030, carbs: 0x2BA88A),
        .arctic: make("arctic", dark: false, bg: 0xEEF4FA, surface: 0xFFFFFF, raised: 0xDFE9F4, accent: 0x2F7BE0, protein: 0xE04B65, fat: 0xE6A11A, carbs: 0x1AA57F),
        .paper: make("paper", dark: false, bg: 0xF7F6F2, surface: 0xFFFFFF, raised: 0xECEAE4, accent: 0x111111, kcal: 0x333333, protein: 0xD64545, fat: 0xD9A02B, carbs: 0x3A9A63),
        .aurora: make("aurora", bg: 0x050F14, surface: 0, raised: 0, accent: 0x5CF2C2, kcal: 0x4BD8A9, protein: 0xC77DFF, fat: 0xFFD166, carbs: 0x48CAE4, glass: true),
        .sunsetGlass: make("sunsetGlass", bg: 0x1A0A14, surface: 0, raised: 0, accent: 0xFF8A5B, kcal: 0xFF7A59, protein: 0xFF4F9A, fat: 0xFFC14D, carbs: 0x9B6BFF, glass: true),
        .oceanGlass: make("oceanGlass", bg: 0x03111F, surface: 0, raised: 0, accent: 0x4CC9F0, kcal: 0x3A86FF, protein: 0xF72585, fat: 0xFFBE0B, carbs: 0x06D6A0, glass: true),
        .frost: make("frost", dark: false, bg: 0xE8EEF8, surface: 0, raised: 0, accent: 0x3F6BFF, kcal: 0x6F8CFF, protein: 0xFF6B9A, fat: 0xFFC247, carbs: 0x2EC4A0, glass: true),
    ]
}

/// The palette in use (set by ThemedRoot before anything is drawn).
var palette: Palette = .midnight

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
        background {
            if palette.glass { GlassBackdrop() } else { Color.pageBackground.ignoresSafeArea() }
        }
    }

    /// A settings-style form on the theme's background.
    func themedForm() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .pageBackground()
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
    static var pageBackground: Color { palette.glass ? .clear : palette.background }     // glass: the backdrop shows through
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

/// How much flair: Standard, or Maximal (gradient edges, glow on rings, bars and charts).
enum StyleLevel: String, CaseIterable, Identifiable {
    case standard, maximal
    var id: String { rawValue }
    var label: String { self == .standard ? "Standard" : "Maximal" }
}

enum GlowStyle {
    static var on: Bool { UserDefaults.standard.string(forKey: "styleLevel") == StyleLevel.maximal.rawValue }
}

/// Every card's surface: plain, glowing (Maximal) or Liquid Glass (Glass theme).
struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if palette.glass {
            if #available(iOS 26, macOS 26, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                content.background(.ultraThinMaterial, in: shape).overlay(shape.stroke(palette.stroke))
            }
        } else if GlowStyle.on {
            content
                .background(shape.fill(LinearGradient(colors: [palette.surface.mix(with: palette.accent, by: 0.07), palette.surface],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(shape.stroke(LinearGradient(colors: [palette.accent.opacity(0.55), .white.opacity(0.03), palette.protein.opacity(0.3)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2))
                .shadow(color: palette.accent.opacity(palette.scheme == .dark ? 0.18 : 0.1), radius: 16, y: 6)
        } else {
            content.background(Color.cardBackground, in: shape).overlay(shape.stroke(palette.stroke))
        }
    }
}

/// A floating capsule (the search bar, the tab bar on Glass).
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if palette.glass, #available(iOS 26, macOS 26, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(palette.glass ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.raisedBackground), in: Capsule())
                .overlay(Capsule().stroke(palette.stroke))
        }
    }
}

/// Behind everything on the Glass theme: soft colour for the glass to bend.
struct GlassBackdrop: View {
    var body: some View {
        ZStack {
            palette.background
            Circle().fill(palette.calories).frame(width: 420).blur(radius: 120).offset(x: -150, y: -320).opacity(0.55)
            Circle().fill(palette.protein).frame(width: 360).blur(radius: 130).offset(x: 170, y: -40).opacity(0.38)
            Circle().fill(palette.carbs).frame(width: 380).blur(radius: 140).offset(x: -120, y: 360).opacity(0.32)
            Circle().fill(Color(hex: 0x9B5CFF)).frame(width: 300).blur(radius: 120).offset(x: 160, y: 520).opacity(0.35)
        }
        .ignoresSafeArea()
    }
}

/// A progress ring. Past 100% a second, darker lap shows how far over.
struct Ring: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 10
    @State private var shown: Double = 0
    @State private var closed = false          // the moment it reaches 100%: one soft glow

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(shown, 0), 1))
                .stroke(AngularGradient(colors: [color.opacity(0.7), color], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * min(max(shown, 0.01), 1))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .shadow(color: GlowStyle.on || palette.glass ? color.opacity(0.65) : .clear, radius: lineWidth * 0.8)
                .rotationEffect(.degrees(-90))
            if shown > 1 {
                Circle()
                    .trim(from: 0, to: min(shown - 1, 1))
                    .stroke(color.mix(with: .black, by: 0.35), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .black.opacity(0.35), radius: 2)
            }
        }
        .padding(lineWidth / 2)
        .scaleEffect(closed && !Motion.reduceMotion ? 1.05 : 1)
        .shadow(color: closed ? color.opacity(0.7) : .clear, radius: closed ? lineWidth * 1.6 : 0)
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
                    Capsule().fill(LinearGradient(colors: [macro.color.opacity(0.75), macro.color], startPoint: .leading, endPoint: .trailing))
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
