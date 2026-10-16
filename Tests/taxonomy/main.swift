// Prints the taxonomy review list for every food in a store (a copy of your real data): canonical
// food, role, NOVA group, raw/cooked, confidence, least certain first. With --ai, asks the local
// model about uncertain foods first (on this copy only).
import Foundation
import SwiftData
setvbuf(stdout, nil, _IONBF, 0)
let ai = CommandLine.arguments.contains("--ai")
Task { @MainActor in
    let c = try! ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(url: URL(fileURLWithPath: CommandLine.arguments[1])))
    let ctx = c.mainContext
    UserDefaults.standard.removeObject(forKey: "taxonomySeed1")
    ctx.applyTaxonomySeeds()
    await ctx.fillTaxonomyData()
    if ai { await ctx.suggestTaxonomy() }
    let foods = ((try? ctx.fetch(FetchDescriptor<Food>())) ?? []).map { ($0, ctx.taxonomy(of: $0)) }
        .sorted { ($0.1.confidence, $0.0.name) < ($1.1.confidence, $1.0.name) }
    print("FOOD TAXONOMY · \(foods.count) foods · least certain first")
    for (f, t) in foods {
        let group = f.foodGroup.isEmpty || f.foodGroup == "-" ? "" : " · group: \(f.foodGroup)"
        print(String(format: "%3.0f%%  %@", t.confidence * 100, f.name as NSString))
        print("      → \(t.canonicalName ?? "(no canonical food)") · \(t.role.label) · NOVA \(t.nova) (\(t.novaSource))\(f.otherWeightUnit != nil || !f.weightState.isEmpty ? (t.state.map { " · values per \($0 == .raw ? "raw/dry" : "cooked") weight" } ?? "") : "")")
        print("        \(t.roleSource == .user ? "your correction" : t.why.joined(separator: "; "))\(group)")
    }
    exit(0)
}
dispatchMain()
