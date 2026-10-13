import SwiftUI

/// One colour per nutrient, used everywhere (bars, charts, labels).
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

    var color: Color {
        switch self {
        case .calories: return Color(red: 0.24, green: 0.48, blue: 0.95)
        case .protein: return Color(red: 0.91, green: 0.31, blue: 0.36)
        case .fat: return Color(red: 0.96, green: 0.72, blue: 0.24)
        case .carbs: return Color(red: 0.29, green: 0.70, blue: 0.53)
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
    static var cardBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    static var pageBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
}

/// A rounded panel with a small title, like the dashboard tiles.
struct Card<Content: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(title)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.06)))
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
                    Capsule().fill(macro.color.opacity(0.18))
                    Capsule().fill(macro.color).frame(width: g.size.width * min(1, target > 0 ? eaten / target : 0))
                }
            }
            .frame(height: 8)
        }
    }

    private func amount(_ v: Double) -> String {
        macro == .calories ? energy.format(v) : "\(number(v)) g"
    }
}
