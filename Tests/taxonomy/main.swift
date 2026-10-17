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
    UserDefaults.standard.removeObject(forKey: "taxonomySeed2")
    ctx.applyTaxonomySeeds2()
    await ctx.fillTaxonomyData()
    if ai { await ctx.suggestTaxonomy() }
    if CommandLine.arguments.contains("--usual") {
        let mp = ctx.mealPatterns()
        print("YOUR USUAL MEALS · learned from \(Set(mp.meals.map(\.day)).count) days, \(mp.meals.count) meals")
        for band in MealBand.allCases {
            let ms = mp.meals.filter { $0.band == band }
            guard !ms.isEmpty else { continue }
            print("\n\(band.label.uppercased())")
            for m in ms { print("  \(m.day): \(m.foods.sorted().map { Taxonomy.byID[$0]?.name ?? $0 }.joined(separator: " + "))") }
            let pairs = (mp.pairs[band] ?? [:]).sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(6)
            if !pairs.isEmpty {
                print("  pairs: " + pairs.map { kv in kv.key.split(separator: "|").map { Taxonomy.byID[String($0)]?.name ?? String($0) }.joined(separator: " & ") + String(format: " (%.1f)", kv.value) }.joined(separator: "; "))
            }
        }
        exit(0)
    }
    if CommandLine.arguments.contains("--staples") {
        let sg = ctx.stapleSuggestions()
        print("STAPLE SUGGESTIONS · logged on ≥ \(ctx.profile!.planner.stapleMinDays) of the last \(ctx.profile!.planner.stapleWindowDays) days")
        if sg.isEmpty { print("  (none)") }
        for x in sg { print("  \(x.name): \(x.days) days · usually \(Int(x.grams)) g at \(x.band.label.lowercased())") }
        let logs = ctx.loggedFoods(days: 29).filter { $0.day < dayKey() }
        let imported = ((try? ctx.fetch(FetchDescriptor<FoodEntry>())) ?? []).filter { $0.foodKey == "import" && $0.day >= addDays(dayKey(), -28) }.count
        print("\nEvery food logged in the last 28 days (days logged):")
        for (k, rows) in Dictionary(grouping: logs, by: \.key).sorted(by: { Set($0.value.map(\.day)).count > Set($1.value.map(\.day)).count }) {
            print("  \(Set(rows.map(\.day)).count) days  \(rows.last!.name)  (\(k))")
        }
        print("\nDays in the window with food-by-food entries: \(Set(logs.map(\.day)).count); days that are only an imported day total: \(imported)")
        exit(0)
    }
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
