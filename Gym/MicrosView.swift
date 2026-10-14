import SwiftData
import SwiftUI

/// Fibre, sugar, saturated fat, sodium and vitamins/minerals for some food, against daily references.
/// `days` > 1 shows daily averages.
struct NutrientPanel: View {
    let total: Nutrients
    let entries: [FoodEntry]
    var days: Int = 1
    var title = "Nutrients"
    @Query private var profiles: [Profile]
    @AppStorage("nutrientPanelOpen") private var open = true

    var body: some View {
        let sex = profiles.first?.sexValue ?? .male
        let k = 1 / Double(max(days, 1))
        let n = total.scaled(k)
        let withMicros = entries.filter { $0.nutrients.micros != nil }.count
        Card(title: title, systemImage: "leaf", accessory: AnyView(
            Button(open ? "Hide" : "Show") { withAnimation(.snappy) { open.toggle() } }.buttonStyle(.borderless).font(.caption.weight(.semibold))
        )) {
            if open {
                VStack(spacing: 9) {
                    let p = profiles.first, k = max(n.kcal, 1)
                    row("Fibre", n.fiber, nutrientTarget("fiber", kcal: k, sex: sex, profile: p).value, "g", limit: false)
                    row("Sugar", n.sugar, nutrientTarget("sugar", kcal: k, sex: sex, profile: p).value, "g", limit: true)
                    row("Saturated fat", n.satFat, nutrientTarget("satFat", kcal: k, sex: sex, profile: p).value, "g", limit: true)
                    row("Sodium", n.sodium, nutrientTarget("sodium", kcal: k, sex: sex, profile: p).value, "mg", limit: true)
                }
                Divider()
                if withMicros == 0 {
                    Text("Vitamins and minerals show up for foods logged from USDA or Open Food Facts from now on.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(Micro.all) { m in tile(m, n.micros?[m.key], nutrientTarget(m.key, kcal: n.kcal, sex: sex, profile: profiles.first).value) }
                    }
                    Text("\(withMicros) of \(entries.count) foods have vitamin and mineral data, so real intake is likely higher.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ name: String, _ v: Double?, _ ref: Double, _ unit: String, limit: Bool) -> some View {
        let p = v.map { ref > 0 ? $0 / ref : 0 } ?? 0
        let color: Color = limit ? (p > 1 ? palette.warn : palette.good) : (p >= 1 ? palette.good : palette.accent)
        return HStack(spacing: 10) {
            Text(name).font(.caption.weight(.semibold)).frame(width: 92, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule().fill(color).frame(width: max(6, g.size.width * min(1, p))).opacity(v == nil ? 0 : 1)
                }
            }
            .frame(height: 7)
            Text(v.map { "\(number($0, digits: $0 < 10 ? 1 : 0))\(limit ? " / max " : " / ")\(number(ref)) \(unit)" } ?? "no data")
                .font(.caption2).monospacedDigit().foregroundStyle(.secondary).frame(width: 118, alignment: .trailing)
        }
    }

    private func tile(_ m: Micro, _ v: Double?, _ target: Double) -> some View {
        let p = v.map { $0 / target } ?? 0
        let color: Color = m.isLimit ? (p > 1 ? palette.warn : palette.good) : (p >= 1 ? palette.good : p >= 0.5 ? Macro.fat.color : palette.accent)
        return HStack(spacing: 8) {
            ZStack {
                Ring(progress: p, color: color, lineWidth: 4)
                Text(v == nil ? "–" : "\(Int((p * 100).rounded()))").font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text(m.label).font(.caption.weight(.semibold)).lineLimit(1)
                Text(v.map { "\(number($0, digits: $0 < 10 ? 1 : 0)) \(m.unit)" } ?? "no data").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.raisedBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
}
