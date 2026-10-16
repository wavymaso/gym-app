import SwiftData
import SwiftUI

/// Every food in your library: what it is (canonical food), its role, how processed it is (NOVA)
/// and raw/cooked, least certain first. Tap to correct; corrections are permanent.
struct TaxonomyReviewView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Food.name) private var foods: [Food]
    @State private var editing: Food?
    @State private var asking = false

    var body: some View {
        let rows = foods.map { ($0, ctx.taxonomy(of: $0)) }.sorted { ($0.1.confidence, $0.0.name) < ($1.1.confidence, $1.0.name) }
        List {
            Section {
                Text("Least certain first. The planner uses the role to build meals (a protein main and a carb side, condiments only alongside) and NOVA for the whole-food preference. Your corrections always win.")
                    .font(.caption).foregroundStyle(.secondary)
                #if os(macOS)
                Button(asking ? "Asking the local model…" : "Ask the local model about uncertain foods") {
                    asking = true; Task { await ctx.suggestTaxonomy(); asking = false }
                }
                .disabled(asking)
                #endif
            }
            ForEach(rows, id: \.0.key) { f, t in
                Button { editing = f } label: { row(f, t) }.buttonStyle(.plain)
            }
        }
        .themedList()
        .navigationTitle("Food taxonomy")
        .sheet(item: $editing) { f in NavigationStack { TaxonomyEditor(food: f) }.appStyle() }
        .task { await ctx.fillTaxonomyData() }
    }

    private func row(_ f: Food, _ t: Taxonomy.Result) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Circle().fill(t.confidence >= 0.9 ? palette.good : t.confidence >= 0.7 ? palette.under : palette.warn).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.name).lineLimit(1)
                Text("\(t.canonicalName ?? "no canonical food") · \(t.role.label) · NOVA \(t.nova)\(t.novaEstimated ? " (estimated)" : "")\(t.state.map { " · \($0 == .raw ? "raw" : "cooked")" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
                Text(t.roleSource == .user ? "your correction" : "\(Int(t.confidence * 100))% · \(t.why.joined(separator: "; "))").font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
            }
        }
    }
}

struct TaxonomyEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let food: Food
    @State private var canonical: String = ""
    @State private var role: FoodRole = .proteinMain
    @State private var nova = 0
    @State private var loaded = false

    var body: some View {
        let t = ctx.taxonomy(of: food)
        Form {
            Section {
                Picker("Canonical food", selection: $canonical) {
                    Text("None").tag("")
                    ForEach(Taxonomy.canonical.sorted { $0.name < $1.name }, id: \.id) { c in Text(c.name).tag(c.id) }
                }
                Picker("Role", selection: $role) { ForEach(FoodRole.allCases, id: \.self) { Text($0.label).tag($0) } }
                Picker("NOVA group", selection: $nova) {
                    Text("Automatic (\(t.nova), \(t.novaSource))").tag(0)
                    Text("1 · unprocessed").tag(1); Text("2 · culinary ingredient").tag(2); Text("3 · processed").tag(3); Text("4 · ultra-processed").tag(4)
                }
            } header: { Text(food.name) } footer: {
                Text("Now: \(t.canonicalName ?? "none") · \(t.role.label) · NOVA \(t.nova) (\(t.novaSource)). \(t.why.joined(separator: "; ")).")
            }
            Section {
                Button("Raw or cooked…") { cooking = true }
            }
            if food.override != nil {
                Section { Button("Back to automatic", role: .destructive) { food.override = nil; ctx.commit(); dismiss() } }
            }
        }
        .themedForm()
        .navigationTitle("Classify")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    // Only what differs from the automatic answer is stored as a correction.
                    let auto = Taxonomy.classify(ctx.taxonomyInput(food), override: nil, suggestion: food.suggestion)
                    food.override = Taxonomy.Override(canonical: canonical.isEmpty || canonical == auto.canonical ? nil : canonical,
                                                      role: role == auto.role && food.override?.role == nil ? nil : role,
                                                      nova: nova == 0 ? nil : nova)
                    ctx.commit(); Haptics.success(); dismiss()
                }
            }
        }
        .sheet(isPresented: $cooking) { NavigationStack { CookingSheet(food: food) }.appStyle() }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            canonical = t.canonical ?? ""; role = t.role; nova = food.override?.nova ?? 0
        }
    }
    @State private var cooking = false
}
