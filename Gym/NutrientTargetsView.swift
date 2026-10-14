import SwiftData
import SwiftUI

/// Settings → Nutrient targets: set your own daily target for any nutrient (empty = the default).
struct NutrientTargetsView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @State private var texts: [String: String] = [:]

    private let keys = ["fiber", "sugar", "satFat", "sodium"] + Micro.all.map(\.key)
    private let groups: [(String, [String])] = [
        ("Carbs & fats", ["fiber", "sugar", "satFat", "cholesterol"]),
        ("Minerals", ["sodium", "potassium", "calcium", "magnesium", "iron", "zinc"]),
        ("Vitamins", ["vitA", "vitC", "vitD", "vitE", "vitK", "b12", "folate"]),
        ("Caffeine & alcohol", ["caffeine", "alcohol"]),
    ]

    var body: some View {
        Form {
            if let p = profiles.first {
                let kcal = ctx.dayTargets(on: dayKey())?.kcal ?? 2000
                ForEach(groups, id: \.0) { title, ks in
                Section {
                    ForEach(ks.filter(keys.contains), id: \.self) { k in
                        let def = nutrientTarget(k, kcal: kcal, sex: p.sexValue, profile: nil)
                        let unit = k == "sodium" ? "mg" : (Micro.all.first { $0.key == k }?.unit ?? "g")
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(DashItem.label(k))
                                Text("\(def.limit ? "Limit" : "Target") by default: \(number(def.value, digits: def.value < 10 ? 1 : 0)) \(unit)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            TextField("Default", text: Binding(get: { texts[k] ?? "" }, set: { texts[k] = $0 }))
                                .multilineTextAlignment(.trailing).frame(width: 90)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .onSubmit { save(p) }
                            Text(unit).foregroundStyle(.secondary).frame(width: 26, alignment: .leading)
                        }
                    }
                } header: {
                    Text(title)
                } footer: {
                    if title == groups.last?.0 {
                        Text("Leave empty for the default (adult reference intakes; fibre scales with your calories). Limits are maximums, shown in orange when you go over.")
                    }
                }
                }
            }
        }
        .themedForm()
        .navigationTitle("Nutrient targets")
        .onAppear {
            if let p = profiles.first { texts = p.customGoals.mapValues { number($0, digits: $0 < 10 ? 1 : 0) } }
        }
        .onDisappear { if let p = profiles.first { save(p) } }
    }

    private func save(_ p: Profile) {
        var g: [String: Double] = [:]
        for (k, t) in texts { if let v = parseNumber(t), v > 0 { g[k] = v } }
        guard g != p.customGoals else { return }
        p.customGoals = g
        ctx.commit()
    }
}
