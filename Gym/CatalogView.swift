import SwiftUI
import SwiftData

/// Planner settings → Simple foods: the catalogue the planner fills meal slots from (after your
/// staples and usual combinations), grouped by role. Remove anything you'd never buy; mark tier 3
/// foods (and whey) in stock to let them be planned.
struct CatalogView: View {
    @Environment(\.modelContext) private var ctx
    @State private var removed: Set<String> = []
    @State private var stock: Set<String> = []

    var body: some View {
        let foods = SimpleFoods.bundled
        List {
            Section {
                Text("Whole foods first: tier 1 whole foods, tier 2 simple staples, sold at Mercadona, Alcampo or Costco. Values per 100 g are the Spanish products' median, or the generic USDA food where packaged products were mostly prepared forms.")
                    .font(.note).foregroundStyle(.secondary)
            }
            ForEach(FoodRole.allCases, id: \.self) { role in
                let list = foods.filter { $0.role == role && $0.tier <= 2 && $0.availableAtMyStores }
                if !list.isEmpty {
                    Section(role.label) { ForEach(list) { f in row(f, inStockToggle: f.id == "protein-shake") } }
                }
            }
            Section {
                ForEach(foods.filter { $0.tier == 3 }) { f in row(f, inStockToggle: true) }
            } header: { Text("Tier 3 · only when in stock") } footer: { Text("Never a meal's only protein unless you choose that.") }
        }
        .themedList()
        .navigationTitle("Simple foods")
        .onAppear { let p = ctx.profile?.planner; removed = Set(p?.catalogRemoved ?? []); stock = Set(p?.inStock ?? []) }
    }

    private func row(_ f: SimpleFood, inStockToggle: Bool) -> some View {
        let off = removed.contains(f.id)
        return HStack {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("\(f.name) · T\(f.tier)").strikethrough(off).foregroundStyle(off ? .secondary : .primary)
                Text("\(Int(f.values.kcal)) kcal · \(number(f.values.protein, digits: 1)) P · \(number(f.values.fat, digits: 1)) F · \(number(f.values.carbs, digits: 1)) C per 100 g\(f.pack.map { " · pack \(Int($0)) g" } ?? "")")
                    .font(.note).foregroundStyle(.secondary).monospacedDigit()
                Text(SimpleFoods.myStores.filter { (f.stores[$0] ?? 0) > 0 }.map { $0.capitalized }.joined(separator: ", ")).font(.fine).foregroundStyle(.tertiary)
            }
            Spacer()
            if inStockToggle {
                Toggle("In stock", isOn: Binding(get: { stock.contains(f.id) }, set: { v in if v { stock.insert(f.id) } else { stock.remove(f.id) }; save() }))
                    .labelsHidden()
            } else {
                Button(off ? "Add back" : "Remove") { if off { removed.remove(f.id) } else { removed.insert(f.id) }; save(); Haptics.tick() }
                    .buttonStyle(.borderless).font(.label)
            }
        }
    }

    private func save() {
        guard let p = ctx.profile else { return }
        var s = p.planner
        s.catalogRemoved = removed.sorted(); s.inStock = stock.sorted()
        p.planner = s; ctx.commit()
    }
}
