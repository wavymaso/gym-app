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
    @State private var sources = false

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
                Button { sources = true } label: { Label("Top sources of any nutrient", systemImage: "list.number") }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).disabled(entries.isEmpty)
            }
        }
        .sheet(isPresented: $sources) { TopSourcesView(day: entries.map(\.day).max() ?? dayKey()) }
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

/// MacroFactor's "top contributors": for one nutrient, which foods gave you the most of it.
struct TopSourcesView: View {
    let day: String
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]
    @State private var key = "protein"
    @State private var days = 7

    private var nutrients: [(key: String, label: String, unit: String)] {
        [("kcal", "Calories", "kcal"), ("protein", "Protein", "g"), ("carbs", "Carbs", "g"), ("fat", "Fat", "g"),
         ("fiber", "Fibre", "g"), ("sugar", "Sugar", "g"), ("satFat", "Saturated fat", "g"), ("sodium", "Sodium", "mg")]
        + Micro.all.map { ($0.key, $0.label, $0.unit) }
    }

    private func value(_ n: Nutrients, _ k: String) -> Double {
        switch k {
        case "kcal": return n.kcal
        case "protein": return n.protein
        case "carbs": return n.carbs
        case "fat": return n.fat
        case "fiber": return n.fiber ?? 0
        case "sugar": return n.sugar ?? 0
        case "satFat": return n.satFat ?? 0
        case "sodium": return n.sodium ?? 0
        default: return n.micros?[k] ?? 0
        }
    }

    var body: some View {
        let from = addDays(day, -(days - 1))
        let list = (try? ctx.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.day >= from && $0.day <= day }))) ?? []
        let byFood = Dictionary(grouping: list, by: \.name).mapValues { es in
            (amount: es.reduce(0) { $0 + value($1.nutrients, key) }, times: es.count, brand: es.first?.brand)
        }
        let total = byFood.values.reduce(0) { $0 + $1.amount }
        let ranked = byFood.filter { $0.value.amount > 0 }.sorted { $0.value.amount > $1.value.amount }
        let unit = nutrients.first { $0.key == key }?.unit ?? ""
        let color: Color = key == "protein" ? palette.protein : key == "fat" ? palette.fat : key == "carbs" ? palette.carbs : palette.calories
        NavigationStack {
            List {
                Section {
                    Picker("Nutrient", selection: $key) { ForEach(nutrients, id: \.key) { Text($0.label).tag($0.key) } }
                    Picker("Period", selection: $days) { Text("This day").tag(1); Text("7 days").tag(7); Text("30 days").tag(30) }
                        .pickerStyle(.segmented)
                    LabeledContent("Total", value: "\(number(total / Double(days), digits: total / Double(days) < 10 ? 1 : 0)) \(unit) a day")
                }
                Section("Top sources") {
                    if ranked.isEmpty { Text("Nothing logged with this nutrient in the period.").foregroundStyle(.secondary) }
                    ForEach(Array(ranked.prefix(25).enumerated()), id: \.offset) { i, item in
                        let share = total > 0 ? item.value.amount / total : 0
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 20, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.key).lineLimit(1)
                                    Text("\(item.value.times)× · \(item.value.brand ?? "")").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text("\(number(item.value.amount, digits: item.value.amount < 10 ? 1 : 0)) \(unit)").monospacedDigit()
                                Text("\(Int(share * 100 + 0.5))%").font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                            }
                            GeometryReader { g in Capsule().fill(color).frame(width: max(4, g.size.width * share)) }.frame(height: 4).padding(.leading, 20)
                        }
                    }
                }
            }
            .themedList()
            .navigationTitle("Top sources")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .appStyle()
        #if os(macOS)
        .frame(width: 520, height: 640)
        #endif
    }
}
