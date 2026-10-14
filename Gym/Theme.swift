import SwiftUI

// The look of the app: themes (dark and bold by default), colours, cards, rings.
// The chosen palette is global so every view, sheet and window uses the same one;
// changing theme rebuilds the window (see ThemedRoot in GymApp.swift).

enum AppTheme: String, CaseIterable, Identifiable {
    case midnight, graphite, ocean, daylight, system
    var id: String { rawValue }

    var label: String {
        switch self {
        case .midnight: return "Midnight"
        case .graphite: return "Graphite"
        case .ocean: return "Ocean"
        case .daylight: return "Daylight"
        case .system: return "Automatic"
        }
    }

    var detail: String {
        switch self {
        case .midnight: return "Near-black, electric colours"
        case .graphite: return "Dark grey, warm orange"
        case .ocean: return "Deep blue, teal"
        case .daylight: return "Light and clean"
        case .system: return "Midnight at night, Daylight by day"
        }
    }

    /// The palette to use, given whether the system is in dark mode (only matters for Automatic).
    func palette(systemDark: Bool) -> Palette {
        switch self {
        case .midnight: return .midnight
        case .graphite: return .graphite
        case .ocean: return .ocean
        case .daylight: return .daylight
        case .system: return systemDark ? .midnight : .daylight
        }
    }

    /// nil lets the system decide (Automatic).
    var scheme: ColorScheme? {
        switch self {
        case .daylight: return .light
        case .system: return nil
        default: return .dark
        }
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
    static let daylight = Palette(name: "daylight", scheme: .light, background: Color(hex: 0xF2F2F7), surface: .white,
                                  raised: Color(hex: 0xEDEDF2), stroke: .black.opacity(0.06), accent: Color(hex: 0x2F6BFF),
                                  calories: Color(hex: 0x2F6BFF), protein: Color(hex: 0xE8445A), fat: Color(hex: 0xEFA300),
                                  carbs: Color(hex: 0x1FA774))
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
    static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight, design: .rounded) }
}

extension View {
    /// Locale, colours and light/dark for a sheet or window (the Mac doesn't pass these on to sheets).
    func appStyle() -> some View {
        environment(\.locale, appLocale)
            .tint(palette.accent)
            .preferredColorScheme(palette.scheme)
    }

    /// A settings-style form on the theme's background.
    func themedForm() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.pageBackground)
    }

    /// A list on the theme's background.
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.pageBackground)
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
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(palette.stroke))
    }
}

/// A progress ring. Past 100% a second, darker lap shows how far over.
struct Ring: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 10
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(shown, 0), 1))
                .stroke(AngularGradient(colors: [color.opacity(0.7), color], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * min(max(shown, 0.01), 1))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
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
        .onAppear { withAnimation(.spring(duration: 0.9)) { shown = progress } }
        .onChange(of: progress) { _, p in withAnimation(.spring(duration: 0.6)) { shown = p } }
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
