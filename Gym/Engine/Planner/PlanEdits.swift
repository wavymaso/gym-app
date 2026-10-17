import Foundation

// Your changes to one day's plan (Plan view): a food you swapped in, and foods you keep at a portion
// (locked, or a serving you set). Kept per day with the planner settings (synced); a week old, gone.

struct DayEdits: Codable, Equatable {
    var picks: [String: String] = [:]       // "slot|kind" → the food you chose for that slot (swap)
    var start: [String: Double] = [:]       // "slot|key" → its starting portion (matched to what it replaced)
    var pins: [String: Double] = [:]        // "slot|key" → grams kept exactly (a food you locked, or a serving you set)
    var pinKinds: [String: String] = [:]    // "slot|key" → the template slot it fills ("extra": an added food, e.g. a second protein)

    static func slotKey(_ slot: Int, _ kind: TemplateSlot.Kind) -> String { "\(slot)|\(kind.rawValue)" }
    static func itemKey(_ slot: Int, _ key: String) -> String { "\(slot)|\(key)" }

    var isEmpty: Bool { self == DayEdits() }

    /// Everything that changes one meal (to tell which meals an edit touched).
    func signature(_ slot: Int) -> String {
        let p = "\(slot)|"
        func part<V>(_ d: [String: V]) -> String { d.filter { $0.key.hasPrefix(p) }.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",") }
        return [part(picks), part(start), part(pins), part(pinKinds)].joined(separator: ";")
    }

    /// For the builder: per slot index.
    var byslot: (picks: [Int: [TemplateSlot.Kind: String]], start: [Int: [String: Double]], pins: [Int: [String: Double]], pinKinds: [Int: [String: String]]) {
        var pk: [Int: [TemplateSlot.Kind: String]] = [:], st: [Int: [String: Double]] = [:], pn: [Int: [String: Double]] = [:], kd: [Int: [String: String]] = [:]
        func split(_ s: String) -> (Int, String)? { let a = s.split(separator: "|", maxSplits: 1).map(String.init); guard a.count == 2, let i = Int(a[0]) else { return nil }; return (i, a[1]) }
        for (k, v) in picks { if let (i, r) = split(k), let kind = TemplateSlot.Kind(rawValue: r) { pk[i, default: [:]][kind] = v } }
        for (k, v) in start { if let (i, key) = split(k) { st[i, default: [:]][key] = v } }
        for (k, v) in pins { if let (i, key) = split(k) { pn[i, default: [:]][key] = v } }
        for (k, v) in pinKinds { if let (i, key) = split(k) { kd[i, default: [:]][key] = v } }
        return (pk, st, pn, kd)
    }

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        picks = (try? c.decodeIfPresent([String: String].self, forKey: .picks)) ?? [:]
        start = (try? c.decodeIfPresent([String: Double].self, forKey: .start)) ?? [:]
        pins = (try? c.decodeIfPresent([String: Double].self, forKey: .pins)) ?? [:]
        pinKinds = (try? c.decodeIfPresent([String: String].self, forKey: .pinKinds)) ?? [:]
    }
}

extension MealBuilder {
    /// Foods as the builder sizes them: an absolute maximum per food in a meal (one tub of queso batido),
    /// at least 150 g of vegetables, template unit caps (3 chocolate rice cakes).
    static func prepared(_ all: [PlanFood], templates: [MealTemplate], exclusions: Set<String>) -> [PlanFood] {
        var foods = all.filter { !exclusions.contains($0.key) }
        for i in foods.indices {
            if let c = foods[i].canonical, let mx = Portion.absoluteMax[c] {
                foods[i].maxGrams = max(foods[i].step, min(foods[i].maxGrams, mx))
                foods[i].usualGrams = min(foods[i].usualGrams, foods[i].maxGrams); foods[i].minGrams = min(foods[i].minGrams, foods[i].maxGrams)
            }
            if foods[i].role == .vegetable {
                foods[i].minGrams = max(foods[i].minGrams, Portion.vegetableMin); foods[i].maxGrams = max(foods[i].maxGrams, 2 * Portion.vegetableMin)
                foods[i].usualGrams = max(foods[i].usualGrams, Portion.vegetableMin)
            }
        }
        for t in templates { for ts in t.slots { for (c, n) in ts.maxUnits { for i in foods.indices where foods[i].canonical == c { foods[i].maxGrams = min(foods[i].maxGrams, Double(n) * foods[i].step) } } } }
        return foods
    }

    /// Swap: up to `n` foods for the same slot of this meal (same template slot, so the same role),
    /// ranked like the plan's own choice (your staples, foods you eat with the rest of the meal, how
    /// often you have them, basics last) and filtered by the style setting. Each comes at a portion matching
    /// the protein of what it replaces (protein slot) or its calories (any other slot).
    static func alternatives(slot: PlanSlot, kind: TemplateSlot.Kind, replacing current: PlanItem, foods all: [PlanFood], templates: [MealTemplate],
                             ctx: BuildContext, exclusions: Set<String> = [], n: Int = 5) -> [(food: PlanFood, grams: Double)] {
        let foods = prepared(all, templates: templates, exclusions: exclusions)
        let byKey = Dictionary(foods.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        guard let t = MealTemplates.template(for: slot, in: templates), let ts = t.slots.first(where: { $0.kind == kind }) else { return [] }
        let others = slot.items.filter { $0.key != current.key }.compactMap { byKey[$0.key] }
        let inMeal = Set(others.compactMap(\.canonical) + [byKey[current.key]?.canonical].compactMap { $0 })
        var c = ctx; c.offset = 0
        let ranked = rank(t, ts, slot: slot, foods: foods.filter { $0.key != current.key && !inMeal.contains($0.canonical ?? "") }, ctx: c, chosen: others, taken: [:], usedToday: [:], budget: nil)
        let was = byKey[current.key]?.macros(current.grams) ?? Macros()
        return ranked.prefix(n).map { f in
            let raw: Double
            if kind == .protein, f.per100.protein > 1, was.protein > 1 { raw = was.protein / f.per100.protein * 100 }
            else if f.per100.kcal > 0, was.kcal > 0 { raw = was.kcal / f.per100.kcal * 100 } else { raw = f.usualGrams }
            let g = min(f.maxGrams, max(max(f.minGrams, f.step), (raw / f.step).rounded() * f.step))
            return (f, g)
        }
    }
}
