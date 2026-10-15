import Foundation
import SwiftData

// Checked at every launch: the same record twice (a sync or import hiccup), recipe ingredients
// whose recipe is gone, sets without their workout, and impossible numbers. Safe repairs are
// made; the rest is reported on the Diagnostics page.

struct IntegrityReport: Codable {
    var at = Date()
    var duplicatesRemoved = 0
    var orphansRemoved = 0
    var problems: [String] = []
    var isClean: Bool { duplicatesRemoved == 0 && orphansRemoved == 0 && problems.isEmpty }
    var summary: String {
        if isClean { return "No problems found" }
        var s: [String] = []
        if duplicatesRemoved > 0 { s.append("\(duplicatesRemoved) duplicate\(duplicatesRemoved == 1 ? "" : "s") removed") }
        if orphansRemoved > 0 { s.append("\(orphansRemoved) leftover\(orphansRemoved == 1 ? "" : "s") removed") }
        s += problems
        return s.joined(separator: " · ")
    }

    static var last: IntegrityReport? {
        get { UserDefaults.standard.data(forKey: "lastIntegrity").flatMap { try? JSONDecoder().decode(IntegrityReport.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "lastIntegrity") }
    }
}

extension ModelContext {
    func integrityCheck() -> IntegrityReport {
        var r = IntegrityReport()

        // The same record twice: keep the newest edit. (Saved directly, not through commit(), so no
        // deletion is sent to the other device: the record itself stays.)
        func dedupe<T: Syncable>(_ t: T.Type) {
            let all = (try? fetch(FetchDescriptor<T>())) ?? []
            for (id, group) in Dictionary(grouping: all, by: \.syncID) where !id.isEmpty && group.count > 1 {
                for extra in group.sorted(by: { $0.modifiedAt > $1.modifiedAt }).dropFirst() { delete(extra); r.duplicatesRemoved += 1 }
            }
        }
        for t in syncTypes { dedupe(t) }

        // Recipe ingredients whose recipe no longer exists: invisible everywhere, safe to drop.
        let foodKeys = Set(((try? fetch(FetchDescriptor<Food>())) ?? []).map(\.key))
        for i in (try? fetch(FetchDescriptor<RecipeIngredient>())) ?? [] where !foodKeys.contains(i.recipeKey) {
            delete(i); r.orphansRemoved += 1
        }

        // Sets whose workout is gone: reported, not deleted (they still count for your history).
        let workoutKeys = Set(((try? fetch(FetchDescriptor<Workout>())) ?? []).map(\.key))
        let loose = ((try? fetch(FetchDescriptor<WorkoutSet>())) ?? []).filter { !workoutKeys.contains($0.workoutKey) }.count
        if loose > 0 { r.problems.append("\(loose) set\(loose == 1 ? "" : "s") without a workout") }

        // Numbers that can't be right.
        let bad = ((try? fetch(FetchDescriptor<FoodEntry>())) ?? []).filter { e in
            let n = e.nutrients
            return [n.kcal, n.protein, n.fat, n.carbs].contains { !$0.isFinite || $0 < 0 } || n.kcal > 20000
        }
        if !bad.isEmpty { r.problems.append("\(bad.count) food entr\(bad.count == 1 ? "y has" : "ies have") impossible numbers (\(bad.prefix(3).map(\.day).joined(separator: ", ")))") }
        let badWeights = ((try? fetch(FetchDescriptor<WeightEntry>())) ?? []).filter { !$0.kg.isFinite || $0.kg < 20 || $0.kg > 400 }.count
        if badWeights > 0 { r.problems.append("\(badWeights) weigh-in\(badWeights == 1 ? "" : "s") outside 20–400 kg") }

        if r.duplicatesRemoved + r.orphansRemoved > 0 {
            try? save()
            dataVersion += 1
        }
        if !r.isClean { Log.problem("database", "Integrity: \(r.summary)") }
        return r
    }
}
