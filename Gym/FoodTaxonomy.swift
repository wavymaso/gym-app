import Foundation
import SwiftData

// The taxonomy in the app: each food classified from what we know about it (its name, the
// database's food group and NOVA group, its macros, recipe ingredients), with your corrections on
// top. The local AI only fills in what rules can't place, and only the canonical food and role.

extension Food {
    var override: Taxonomy.Override? {
        get { taxonomyOverride.isEmpty ? nil : try? JSONDecoder().decode(Taxonomy.Override.self, from: Data(taxonomyOverride.utf8)) }
        set {
            let empty = newValue == nil || (newValue?.canonical == nil && newValue?.role == nil && newValue?.nova == nil)
            taxonomyOverride = empty ? "" : String(decoding: (try? JSONEncoder().encode(newValue)) ?? Data(), as: UTF8.self)
        }
    }
    var suggestion: Taxonomy.Suggestion? {
        get { taxonomySuggestion.isEmpty ? nil : try? JSONDecoder().decode(Taxonomy.Suggestion.self, from: Data(taxonomySuggestion.utf8)) }
        set { taxonomySuggestion = newValue.map { String(decoding: (try? JSONEncoder().encode($0)) ?? Data(), as: UTF8.self) } ?? "" }
    }
}

extension ModelContext {
    func taxonomyInput(_ f: Food) -> Taxonomy.Input {
        var x = Taxonomy.Input(name: f.name, brand: f.brand, source: f.source, kcal: f.per100.kcal, protein: f.per100.protein, fat: f.per100.fat,
                               carbs: f.per100.carbs, sugar: f.per100.sugar, isLiquid: f.isLiquid, state: f.state)
        if f.nova > 0 { x.offNova = f.nova }
        if !f.foodGroup.isEmpty && f.foodGroup != "-" {
            if f.source == "usda" { x.usdaCategory = f.foodGroup } else { x.offGroup = f.foodGroup }
        }
        if f.source == "recipe" {
            let foods = ingredients(of: f.key).compactMap { $0.foodKey.flatMap { food(key: $0) } }
            x.ingredientNovas = foods.map { taxonomy(of: $0, depth: 1).nova }
        }
        return x
    }

    func taxonomy(of f: Food, depth: Int = 0) -> Taxonomy.Result {
        var x = taxonomyInput(f)
        if depth > 0 { x.ingredientNovas = [] }
        return Taxonomy.classify(x, override: f.override, suggestion: f.suggestion)
    }

    /// Fill in each food's NOVA and food group: from the offline database first, then Open Food
    /// Facts (one request a second). "-" marks a food we looked up and found nothing for.
    @MainActor func fillTaxonomyData() async {
        let foods = (try? fetch(FetchDescriptor<Food>())) ?? []
        var changed = false
        for f in foods where f.foodGroup.isEmpty {
            if f.source == "off", let code = f.barcode ?? f.key.split(separator: ":").last.map(String.init), let t = LocalFoods.shared.taxonomy(code: code) {
                if let n = t.nova { f.nova = n }
                f.foodGroup = t.group ?? "-"; changed = true
            } else if f.source == "usda", let id = Int(f.key.dropFirst(5)), let c = LocalFoods.shared.genericCategory(fdc: id) {
                f.foodGroup = c; changed = true
            }
        }
        if changed { commit() }
        for f in foods where f.source == "off" && (f.foodGroup.isEmpty || (f.foodGroup == "-" && f.nova == 0 && !Self.lookedUpOnline.contains(f.key))) {
            Self.lookedUpOnline.insert(f.key)
            guard let code = f.barcode ?? f.key.split(separator: ":").last.map(String.init),
                  let r = try? await FoodAPI.product(barcode: code) else { if f.foodGroup.isEmpty { f.foodGroup = "-" }; continue }
            if let n = r.nova { f.nova = n }
            f.foodGroup = r.group ?? "-"
            commit()
            try? await Task.sleep(for: .seconds(1))
        }
    }
    @MainActor private static var lookedUpOnline: Set<String> = []

    /// Ask the local model about foods the rules can't place (confidence under 0.6, no suggestion yet).
    /// It picks a canonical food and role from fixed lists; nutrition is never asked for or changed.
    @MainActor func suggestTaxonomy() async {
        let foods = ((try? fetch(FetchDescriptor<Food>())) ?? []).filter { $0.override?.role == nil && $0.suggestion == nil && taxonomy(of: $0).confidence < 0.6 }
        for f in foods.prefix(20) {
            let ids = Taxonomy.canonical.map { "\($0.id) (\($0.name), \($0.role.rawValue))" }.joined(separator: "; ")
            let prompt = """
            Classify one food for a meal planner. Do not estimate nutrition.
            Food: "\(f.name)"\(f.brand.map { ", brand \($0)" } ?? ""). Per 100 g: \(Int(f.per100.kcal)) kcal, \(Int(f.per100.protein)) g protein, \(Int(f.per100.fat)) g fat, \(Int(f.per100.carbs)) g carbs.
            Canonical foods (id (name, role)): \(ids)
            Roles: \(FoodRole.allCases.map(\.rawValue).joined(separator: ", "))
            Reply with JSON only: {"canonical": "<id or null>", "role": "<role>", "confidence": 0.0}
            """
            guard let reply = try? await PhotoAI.askCoach(prompt, allowGemini: false).text,
                  let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"),
                  let obj = try? JSONSerialization.jsonObject(with: Data(reply[start...end].utf8)) as? [String: Any] else { continue }
            let canonical = (obj["canonical"] as? String).flatMap { Taxonomy.byID[$0] != nil ? $0 : nil }
            let role = (obj["role"] as? String).flatMap(FoodRole.init(rawValue:))
            guard canonical != nil || role != nil else { continue }
            f.suggestion = Taxonomy.Suggestion(canonical: canonical, role: role, confidence: min(0.65, (obj["confidence"] as? Double) ?? 0.5))
            commit()
        }
    }

    /// Corrections you gave in chat (17 Oct 2026), applied once as permanent corrections; and role
    /// corrections from the earlier planner screen moved onto the foods.
    func applyTaxonomySeeds() {
        guard !UserDefaults.standard.bool(forKey: "taxonomySeed1") else { return }
        let seeds: [String: FoodRole] = ["off:5025125000181": .carbSide, "off:3596710516148": .carbSide,       // Sourdough Bread, Pipe Rigate
                                         "off:8410376036060": .treat, "off:7340001801583": .proteinSnack]       // Tortitas con chocolate, Barebells
        for (k, r) in seeds { if let f = food(key: k), f.override?.role == nil { var o = f.override ?? .init(); o.role = r; f.override = o } }
        if let p = profile, !p.planner.roles.isEmpty {
            for (k, r) in p.planner.roles { if let f = food(key: k), f.override?.role == nil { var o = f.override ?? .init(); o.role = r; f.override = o } }
            var s = p.planner; s.roles = [:]; p.planner = s
        }
        commit()
        UserDefaults.standard.set(true, forKey: "taxonomySeed1")
    }
}
