import SwiftUI

/// One food in a planned meal (Plan view → tap a food): its portion in the product's units, keep it,
/// swap it for one of 5 others for the same slot, or log what you ate.
struct PlanItemSheet: View {
    enum Action { case keep(Double), unkeep, swap(PlanFood, Double), log(Double) }

    let item: PlanItem
    let food: PlanFood?
    let kind: TemplateSlot.Kind?
    let options: [(food: PlanFood, grams: Double)]
    let act: (Action) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var grams = 0.0

    private var step: Double { max(food?.step ?? 10, 1) }
    private var lo: Double { max(step, food?.minGrams ?? step) }
    private var hi: Double { max(lo, food?.maxGrams ?? 1000) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack {
                        Button { grams = max(lo, ((grams - step) / step).rounded() * step) } label: { Image(systemName: "minus.circle.fill").font(.sectionTitle) }
                            .buttonStyle(.borderless).disabled(grams <= lo + 0.01).accessibilityLabel("Less")
                        Spacer()
                        VStack(spacing: Space.xxs) {
                            Text(food?.shown(grams) ?? "\(Int(grams)) g").font(.numberLarge).monospacedDigit()
                            if food?.unitName != nil { Text("\(Int(grams)) g").font(.fine).foregroundStyle(.secondary) }
                            if let m = food?.macros(grams) {
                                Text("\(Int(m.kcal)) kcal · \(Int(m.protein)) P · \(Int(m.carbs)) C · \(Int(m.fat)) F").font(.fine).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        Spacer()
                        Button { grams = min(hi, ((grams + step) / step).rounded() * step) } label: { Image(systemName: "plus.circle.fill").font(.sectionTitle) }
                            .buttonStyle(.borderless).disabled(grams >= hi - 0.01).accessibilityLabel("More")
                    }
                    HStack {
                        Button(item.isPinned && abs(grams - item.grams) < 0.5 ? "Kept at this portion" : "Keep this portion") { act(.keep(grams)); dismiss() }
                            .buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent).disabled(item.isPinned && abs(grams - item.grams) < 0.5)
                        if item.isPinned { Button("Let the plan size it") { act(.unkeep); dismiss() }.buttonStyle(.bordered) }
                    }
                    .font(.secondaryEmphasis)
                    Text("A kept food stays at this portion; the rest of the meal (and the day if needed) is resized around it.")
                        .font(.fine).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } header: { Text("Portion") }

            if kind != nil {
                Section {
                    if options.isEmpty {
                        Text("No other food fits this slot in your style. Add a staple, or allow more foods in the meal's template.").font(.note).foregroundStyle(.secondary)
                    }
                    ForEach(options, id: \.food.key) { o in
                        let m = o.food.macros(o.grams)
                        Button { act(.swap(o.food, o.grams)); dismiss() } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: Space.hairline) {
                                    HStack(spacing: Space.xs) {
                                        Text(o.food.name).lineLimit(1)
                                        if o.food.staple { Image(systemName: "basket.fill").font(.fine).foregroundStyle(palette.accent).accessibilityLabel("Staple") }
                                        if o.food.basic { Text("basic").font(.fine).foregroundStyle(.tertiary) }
                                    }
                                    Text("\(Int(m.kcal)) kcal · \(Int(m.protein)) P · \(Int(m.carbs)) C · \(Int(m.fat)) F").font(.note).foregroundStyle(.secondary).monospacedDigit()
                                }
                                Spacer()
                                Text(o.food.shown(o.grams)).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: { Text("Swap for") } footer: {
                    Text(kind == .protein ? "Same slot of the meal, matched to this food's protein; the meal is then resized." : "Same slot of the meal, matched to this food's calories; the meal is then resized.")
                }
            }

            Section {
                Button { act(.log(grams)); dismiss() } label: { Label("Log \(food?.shown(grams) ?? "\(Int(grams)) g") as eaten", systemImage: "checkmark.circle") }
            }
        }
        .themedList()
        .navigationTitle(food?.name ?? "Food")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .onAppear { grams = item.grams }
    }
}
