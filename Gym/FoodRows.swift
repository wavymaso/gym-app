import SwiftData
import SwiftUI

struct FoodRowLabel: View {
    let name: String
    let brand: String?
    let source: String
    let per100: Nutrients
    let unit: String
    let favorite: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(name).font(.body.weight(.medium)).lineLimit(1)
                    if favorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(Macro.fat.color) }
                    if per100.looksWrong {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(palette.warn)
                            .help("Its calories don't match its protein, carbs and fat: the label may be wrong")
                    }
                }
                Text([brand, sourceLabel].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(number(per100.kcal)) kcal").font(.callout.weight(.semibold)).monospacedDigit()
                    Text("/100 \(unit)").font(.caption).foregroundStyle(.secondary)
                }
                MacroLine(n: per100)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var sourceLabel: String? {
        switch source {
        case "custom": return "My food"
        case "recipe": return "Recipe"
        default: return nil
        }
    }
}

/// A food in the logger, MacroFactor-style: emoji, name, "325🔥 6P 1F 71C • 250 g", and a round +.
struct MFFoodRow: View {
    let name: String
    let brand: String?
    let n: Nutrients
    let amount: String
    let favorite: Bool
    var busy = false
    let open: () -> Void
    let plus: (() -> Void)?
    var logNow: (() -> Void)? = nil          // long-press ＋: log it straight away
    @State private var added = false

    var body: some View {
        HStack(spacing: 14) {
            Button(action: open) {
                HStack(spacing: 14) {
                    Text(foodEmoji(name: name, brand: brand)).font(.system(size: 30)).frame(width: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(brand.map { "\(name) · \($0)" } ?? name).font(.body).lineLimit(2).multilineTextAlignment(.leading)
                            if favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(palette.fat) }
                            if n.looksWrong { Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(palette.warn) }
                        }
                        (Text("\(number(n.kcal))") + Text(Image(systemName: "flame.fill")).font(.caption2)
                         + Text("  \(number(n.protein))P  \(number(n.fat))F  \(number(n.carbs))C  •  \(amount)"))
                            .font(.subheadline).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if busy { ProgressView().controlSize(.small) }
            if let plus {
                Image(systemName: added ? "checkmark" : "plus").font(.headline)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 40, height: 40)
                    .background(added ? palette.good : Color.raisedBackground, in: Circle())
                    .foregroundStyle(added ? .white : .primary)
                    .scaleEffect(added && !Motion.reduceMotion ? 1.1 : 1)
                    .contentShape(Circle())
                    .onLongPressGesture(minimumDuration: 0.4) {
                        guard let logNow else { return }
                        Haptics.press()
                        logNow()
                    }
                    .onTapGesture {
                        plus()
                        animate(Motion.bouncy) { added = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { animate { added = false } }
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Add to cart")
                    .accessibilityAction(named: "Log now") { logNow?() }
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
    }
}

/// Nothing found anywhere: three ways to log it anyway.
struct NoMatch: View {
    let query: String
    let describe: () -> Void
    let create: () -> Void
    let scanLabel: () -> Void

    var body: some View {
        VStack(spacing: Space.m) {
            Image(systemName: "magnifyingglass").font(.title).foregroundStyle(.secondary)
                .frame(width: 56, height: 56).background(Color.raisedBackground, in: Circle())
            Text("No “\(query)” anywhere").font(.cardTitle)
            Text("Not in your foods, USDA or Open Food Facts. Log it another way:").font(.secondaryText).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: Space.s) {
                action("Describe it to the AI", "sparkles", primary: true, describe)
                action("Scan the nutrition label", "text.viewfinder", primary: false, scanLabel)
                action("Create “\(query)”", "plus", primary: false, create)
            }
            .padding(.top, Space.xs)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Space.xl)
    }

    private func action(_ t: String, _ icon: String, primary: Bool, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Label(t, systemImage: icon).font(.secondaryText.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 46)
                .background(primary ? palette.accent : Color.raisedBackground, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                .foregroundStyle(primary ? Color.white : .primary)
        }
        .pressable()
    }
}
