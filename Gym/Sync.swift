import Foundation
import SwiftData

// Keeping the Mac and the iPhone in step (like Budget): the Mac hosts, the phone syncs
// both ways whenever it can reach it.
//
// - Every record has a `syncID` (the same on both devices) and `modifiedAt`.
// - Every save goes through `commit()`, which stamps what changed and leaves a
//   `Tombstone` for anything deleted, so the other device deletes it too.
// - When both devices changed the same record, the newer edit wins.
// - Records with a natural key share it as their syncID ("builtin:bench-press",
//   a food's key, "w:<day>" for a weigh-in), so the same thing made on both devices
//   becomes one record instead of two.

/// Something deleted here, so the other device deletes it too.
@Model final class Tombstone {
    var type: String
    var syncID: String
    var deletedAt: Date
    init(type: String, syncID: String, deletedAt: Date = Date()) { self.type = type; self.syncID = syncID; self.deletedAt = deletedAt }
}

protocol Syncable: PersistentModel {
    var syncID: String { get set }
    var modifiedAt: Date { get set }
    static var syncType: String { get }
    /// The syncID a new record gets: its natural key, or a random one.
    var naturalID: String { get }
    func encode() -> [String: Any]
    func decode(_ d: [String: Any])
    static func blank() -> Self
}

extension Syncable {
    var naturalID: String { UUID().uuidString }
}

/// Every kind of record that syncs, in the order they're applied.
let syncTypes: [any Syncable.Type] = [Profile.self, Program.self, TargetSet.self, WeightEntry.self, Food.self, RecipeIngredient.self,
                                      FoodEntry.self, Exercise.self, Routine.self, RoutineExercise.self, Workout.self, WorkoutSet.self,
                                      WaterEntry.self, DailyActivity.self, SavedMeal.self, DayNote.self]

extension Notification.Name {
    static let gymDidCommit = Notification.Name("gymDidCommit")
}

extension ModelContext {
    /// Save, stamping what changed (for sync) and noting what was deleted.
    func commit() {
        let now = Date()
        for m in insertedModelsArray + changedModelsArray {
            guard let s = m as? any Syncable else { continue }
            if s.syncID.isEmpty { s.syncID = s.naturalID }
            s.modifiedAt = now
        }
        for m in deletedModelsArray {
            if let s = m as? any Syncable, !s.syncID.isEmpty { insert(Tombstone(type: type(of: s).syncType, syncID: s.syncID, deletedAt: now)) }
        }
        try? save()
        dataVersion += 1
        NotificationCenter.default.post(name: .gymDidCommit, object: nil)
    }

    /// Give records from before sync existed their IDs (once).
    func backfillSyncIDs() {
        var changed = false
        func fill<T: Syncable>(_ t: T.Type) {
            for r in (try? fetch(FetchDescriptor<T>())) ?? [] where r.syncID.isEmpty {
                r.syncID = r.naturalID; r.modifiedAt = Date(); changed = true
            }
        }
        for t in syncTypes { fill(t) }
        if changed { try? save() }
    }

    // MARK: what to send

    /// Records changed and deletions made after `since`.
    func syncChanges(since: Date) -> (records: [[String: Any]], deleted: [[String: Any]]) {
        var records: [[String: Any]] = []
        func collect<T: Syncable>(_ t: T.Type) {
            for r in (try? fetch(FetchDescriptor<T>())) ?? [] where r.modifiedAt > since && !r.syncID.isEmpty {
                records.append(["type": T.syncType, "id": r.syncID, "modifiedAt": r.modifiedAt.timeIntervalSince1970, "data": r.encode()])
            }
        }
        for t in syncTypes { collect(t) }
        let deleted = ((try? fetch(FetchDescriptor<Tombstone>(predicate: #Predicate { $0.deletedAt > since }))) ?? []).map {
            ["type": $0.type, "id": $0.syncID, "deletedAt": $0.deletedAt.timeIntervalSince1970] as [String: Any]
        }
        return (records, deleted)
    }

    // MARK: applying what arrives

    /// Apply the other device's changes. Newer edits win; nothing here is re-stamped.
    func applySync(records: [[String: Any]], deleted: [[String: Any]]) {
        if hasChanges { commit() }                              // an edit still on screen gets stamped first, not lost
        let byType = Dictionary(grouping: records) { $0["type"] as? String ?? "" }
        let tombs = (try? fetch(FetchDescriptor<Tombstone>())) ?? []
        func apply<T: Syncable>(_ t: T.Type) {
            guard let recs = byType[T.syncType] else { return }
            var byID = Dictionary(((try? fetch(FetchDescriptor<T>())) ?? []).map { ($0.syncID, $0) }, uniquingKeysWith: { a, _ in a })
            let gone = Dictionary(tombs.filter { $0.type == T.syncType }.map { ($0.syncID, $0.deletedAt) }, uniquingKeysWith: max)
            for r in recs {
                guard let id = r["id"] as? String, let ts = r["modifiedAt"] as? Double, let data = r["data"] as? [String: Any] else { continue }
                let modified = Date(timeIntervalSince1970: ts)
                if let existing = byID[id] {
                    if modified > existing.modifiedAt { existing.decode(data); existing.modifiedAt = modified }
                } else if (gone[id] ?? .distantPast) < modified {       // deleted here after that edit: stays deleted
                    let n = T.blank(); n.decode(data); n.syncID = id; n.modifiedAt = modified
                    insert(n); byID[id] = n
                }
            }
        }
        for t in syncTypes { apply(t) }
        for d in deleted {
            guard let type = d["type"] as? String, let id = d["id"] as? String, let ts = d["deletedAt"] as? Double else { continue }
            let when = Date(timeIntervalSince1970: ts)
            func remove<T: Syncable>(_ t: T.Type) {
                guard T.syncType == type else { return }
                for r in (try? fetch(FetchDescriptor<T>())) ?? [] where r.syncID == id && r.modifiedAt <= when { delete(r) }
            }
            for t in syncTypes { remove(t) }
            if !tombs.contains(where: { $0.type == type && $0.syncID == id }) { insert(Tombstone(type: type, syncID: id, deletedAt: when)) }
        }
        // A goal changed on both devices while apart: keep the newest program active.
        let active = ((try? fetch(FetchDescriptor<Program>(predicate: #Predicate { $0.isActive }))) ?? [])
            .sorted { ($0.startDay, $0.modifiedAt) > ($1.startDay, $1.modifiedAt) }
        for p in active.dropFirst() { p.isActive = false }
        try? save()
        dataVersion += 1
    }

    /// Everything that syncs, gone (the phone's first connection takes the Mac's data instead).
    func wipeSyncedData() {
        for t in syncTypes { try? delete(model: t) }
        try? delete(model: Tombstone.self)
        try? save()
    }

    var hasSyncedData: Bool { ((try? fetchCount(FetchDescriptor<Profile>())) ?? 0) > 0 }
}

// MARK: - Reading values out of JSON

private extension Dictionary where Key == String, Value == Any {
    func str(_ k: String) -> String { self[k] as? String ?? "" }
    func optStr(_ k: String) -> String? { self[k] as? String }
    func num(_ k: String) -> Double { (self[k] as? Double) ?? (self[k] as? Int).map(Double.init) ?? 0 }
    func optNum(_ k: String) -> Double? { (self[k] as? Double) ?? (self[k] as? Int).map(Double.init) }
    func int(_ k: String) -> Int { (self[k] as? Int) ?? Int((self[k] as? Double) ?? 0) }
    func bool(_ k: String) -> Bool { self[k] as? Bool ?? false }
    func date(_ k: String) -> Date { Date(timeIntervalSince1970: num(k)) }
    func optDate(_ k: String) -> Date? { optNum(k).map { Date(timeIntervalSince1970: $0) } }
    func nutrients(_ k: String) -> Nutrients { decodeJSON(self[k]) ?? .zero }
    func servings(_ k: String) -> [Serving] { decodeJSON(self[k]) ?? [] }
}

private func encodeJSON<T: Encodable>(_ v: T) -> Any {
    (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(v), options: .fragmentsAllowed)) ?? NSNull()
}

private func decodeJSON<T: Decodable>(_ any: Any?) -> T? {
    guard let any, !(any is NSNull), let data = try? JSONSerialization.data(withJSONObject: any, options: .fragmentsAllowed) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}

private func n(_ v: Any?) -> Any { v ?? NSNull() }
private func t(_ d: Date?) -> Any { d.map { $0.timeIntervalSince1970 } ?? NSNull() }

// MARK: - Each kind of record

extension Profile: Syncable {
    static var syncType: String { "profile" }
    var naturalID: String { "profile" }                       // one per person
    func encode() -> [String: Any] {
        ["sex": sex, "birthDate": t(birthDate), "heightCm": heightCm, "activity": activity, "weightUnit": weightUnit,
         "energyUnit": energyUnit, "createdAt": t(createdAt), "goalWeightKg": n(goalWeightKg), "highDays": highDays,
         "highDayExtra": highDayExtra, "fastDays": fastDays, "fastKcal": fastKcal,
         "expManualKcal": expManualKcal, "expStartDay": expStartDay, "bmrEquation": bmrEquation, "expStaticKcal": expStaticKcal,
         "expAlgorithm": expAlgorithm, "stepInformed": stepInformed, "predictiveGoal": predictiveGoal,
         "nutrientGoals": nutrientGoals, "weeklyBudget": weeklyBudget]
    }
    func decode(_ d: [String: Any]) {
        sex = d.str("sex"); birthDate = d.date("birthDate"); heightCm = d.num("heightCm"); activity = d.str("activity")
        weightUnit = d.str("weightUnit"); energyUnit = d.str("energyUnit"); createdAt = d.date("createdAt")
        goalWeightKg = d.optNum("goalWeightKg"); highDays = d.str("highDays"); highDayExtra = d.num("highDayExtra")
        fastDays = d.str("fastDays"); fastKcal = d["fastKcal"] == nil ? 600 : d.num("fastKcal")
        expManualKcal = d.num("expManualKcal"); expStartDay = d.str("expStartDay")
        bmrEquation = d["bmrEquation"] == nil ? "mifflin" : d.str("bmrEquation"); expStaticKcal = d.num("expStaticKcal")
        expAlgorithm = d.str("expAlgorithm"); stepInformed = d.bool("stepInformed"); predictiveGoal = d.bool("predictiveGoal")
        nutrientGoals = d.str("nutrientGoals"); weeklyBudget = d.bool("weeklyBudget")
    }
    static func blank() -> Self { Self(sex: .male, birthDate: Date(), heightCm: 0, activity: .moderate, weightUnit: .kg, energyUnit: .kcal) }
}

extension Program: Syncable {
    static var syncType: String { "program" }
    func encode() -> [String: Any] {
        ["startDay": startDay, "goal": goal, "ratePercent": ratePercent, "dietStyle": dietStyle, "proteinLevel": proteinLevel, "mode": mode,
         "startWeightKg": startWeightKg, "startExpenditure": startExpenditure, "isActive": isActive, "checkInWeekday": checkInWeekday,
         "lastCheckIn": n(lastCheckIn)]
    }
    func decode(_ d: [String: Any]) {
        startDay = d.str("startDay"); goal = d.str("goal"); ratePercent = d.num("ratePercent"); dietStyle = d.str("dietStyle")
        proteinLevel = d.str("proteinLevel"); mode = d.str("mode"); startWeightKg = d.num("startWeightKg")
        startExpenditure = d.num("startExpenditure"); isActive = d.bool("isActive"); checkInWeekday = d.int("checkInWeekday")
        lastCheckIn = d.optStr("lastCheckIn")
    }
    static func blank() -> Self { Self(goal: .maintain, ratePercent: 0, diet: .balanced, protein: .moderate, startWeightKg: 0, startExpenditure: 0) }
}

extension TargetSet: Syncable {
    static var syncType: String { "targets" }
    func encode() -> [String: Any] {
        ["fromDay": fromDay, "kcal": kcal, "protein": protein, "fat": fat, "carbs": carbs, "expenditure": expenditure, "reason": reason,
         "createdAt": t(createdAt)]
    }
    func decode(_ d: [String: Any]) {
        fromDay = d.str("fromDay"); kcal = d.num("kcal"); protein = d.num("protein"); fat = d.num("fat"); carbs = d.num("carbs")
        expenditure = d.num("expenditure"); reason = d.str("reason"); createdAt = d.date("createdAt")
    }
    static func blank() -> Self { Self(targets: Targets(kcal: 0, protein: 0, fat: 0, carbs: 0), expenditure: 0, reason: "") }
}

extension WeightEntry: Syncable {
    static var syncType: String { "weight" }
    var naturalID: String { "w:\(day)" }                      // one weigh-in per day, wherever it was entered
    func encode() -> [String: Any] { ["day": day, "kg": kg, "bodyFatPercent": n(bodyFatPercent), "createdAt": t(createdAt)] }
    func decode(_ d: [String: Any]) { day = d.str("day"); kg = d.num("kg"); bodyFatPercent = d.optNum("bodyFatPercent"); createdAt = d.date("createdAt") }
    static func blank() -> Self { Self(day: "", kg: 0) }
}

extension Food: Syncable {
    static var syncType: String { "food" }
    var naturalID: String { key }
    func encode() -> [String: Any] {
        ["key": key, "name": name, "brand": n(brand), "barcode": n(barcode), "source": source, "per100": encodeJSON(per100),
         "servings": encodeJSON(servings), "isLiquid": isLiquid, "isFavorite": isFavorite, "useCount": useCount, "lastUsed": t(lastUsed),
         "lastAmount": n(lastAmount), "lastUnit": n(lastUnit), "recipeServings": n(recipeServings), "createdAt": t(createdAt)]
    }
    func decode(_ d: [String: Any]) {
        key = d.str("key"); name = d.str("name"); brand = d.optStr("brand"); barcode = d.optStr("barcode"); source = d.str("source")
        per100 = d.nutrients("per100"); servings = d.servings("servings"); isLiquid = d.bool("isLiquid"); isFavorite = d.bool("isFavorite")
        useCount = d.int("useCount"); lastUsed = d.optDate("lastUsed"); lastAmount = d.optNum("lastAmount"); lastUnit = d.optStr("lastUnit")
        recipeServings = d.optNum("recipeServings"); createdAt = d.date("createdAt")
    }
    static func blank() -> Self { Self(key: UUID().uuidString, name: "", source: "custom", per100: .zero) }
}

extension RecipeIngredient: Syncable {
    static var syncType: String { "ingredient" }
    func encode() -> [String: Any] {
        ["recipeKey": recipeKey, "foodKey": n(foodKey), "name": name, "grams": grams, "per100": encodeJSON(per100), "order": order]
    }
    func decode(_ d: [String: Any]) {
        recipeKey = d.str("recipeKey"); foodKey = d.optStr("foodKey"); name = d.str("name"); grams = d.num("grams")
        per100 = d.nutrients("per100"); order = d.int("order")
    }
    static func blank() -> Self { Self(recipeKey: "", foodKey: nil, name: "", grams: 0, per100: .zero, order: 0) }
}

extension FoodEntry: Syncable {
    static var syncType: String { "entry" }
    func encode() -> [String: Any] {
        ["day": day, "time": t(time), "name": name, "brand": n(brand), "foodKey": n(foodKey), "amount": amount, "unit": unit,
         "grams": grams, "nutrients": encodeJSON(nutrients), "createdAt": t(createdAt)]
    }
    func decode(_ d: [String: Any]) {
        day = d.str("day"); time = d.date("time"); name = d.str("name"); brand = d.optStr("brand"); foodKey = d.optStr("foodKey")
        amount = d.num("amount"); unit = d.str("unit"); grams = d.num("grams"); nutrients = d.nutrients("nutrients"); createdAt = d.date("createdAt")
    }
    static func blank() -> Self { Self(day: "", time: Date(), name: "", brand: nil, foodKey: nil, amount: 0, unit: "", grams: 0, nutrients: .zero) }
}

extension Exercise: Syncable {
    static var syncType: String { "exercise" }
    var naturalID: String { key }                             // built-ins match across devices
    func encode() -> [String: Any] {
        ["key": key, "name": name, "muscle": muscle, "secondary": secondary, "equipment": equipment, "isCustom": isCustom,
         "notes": n(notes), "createdAt": t(createdAt)]
    }
    func decode(_ d: [String: Any]) {
        key = d.str("key"); name = d.str("name"); muscle = d.str("muscle"); secondary = d["secondary"] as? [String] ?? []
        equipment = d.str("equipment"); isCustom = d.bool("isCustom"); notes = d.optStr("notes"); createdAt = d.date("createdAt")
    }
    static func blank() -> Self { Self(key: UUID().uuidString, name: "", muscle: .fullBody, equipment: .other, isCustom: true) }
}

extension Routine: Syncable {
    static var syncType: String { "routine" }
    var naturalID: String { key }
    func encode() -> [String: Any] { ["key": key, "name": name, "order": order, "createdAt": t(createdAt)] }
    func decode(_ d: [String: Any]) { key = d.str("key"); name = d.str("name"); order = d.int("order"); createdAt = d.date("createdAt") }
    static func blank() -> Self { Self(name: "", order: 0) }
}

extension RoutineExercise: Syncable {
    static var syncType: String { "routineExercise" }
    func encode() -> [String: Any] {
        ["routineKey": routineKey, "exerciseKey": exerciseKey, "order": order, "sets": sets, "repLow": repLow, "repHigh": repHigh,
         "restSeconds": restSeconds]
    }
    func decode(_ d: [String: Any]) {
        routineKey = d.str("routineKey"); exerciseKey = d.str("exerciseKey"); order = d.int("order"); sets = d.int("sets")
        repLow = d.int("repLow"); repHigh = d.int("repHigh"); restSeconds = d.int("restSeconds")
    }
    static func blank() -> Self { Self(routineKey: "", exerciseKey: "", order: 0) }
}

extension Workout: Syncable {
    static var syncType: String { "workout" }
    var naturalID: String { key }
    func encode() -> [String: Any] {
        ["key": key, "name": name, "start": t(start), "end": t(end), "routineKey": n(routineKey), "notes": n(notes)]
    }
    func decode(_ d: [String: Any]) {
        key = d.str("key"); name = d.str("name"); start = d.date("start"); end = d.optDate("end"); routineKey = d.optStr("routineKey")
        notes = d.optStr("notes")
    }
    static func blank() -> Self { Self(name: "") }
}

extension WorkoutSet: Syncable {
    static var syncType: String { "set" }
    func encode() -> [String: Any] {
        ["workoutKey": workoutKey, "exerciseKey": exerciseKey, "exerciseOrder": exerciseOrder, "setOrder": setOrder, "kind": kind,
         "kg": kg, "reps": reps, "rir": n(rir), "done": done, "restSeconds": restSeconds, "day": day]
    }
    func decode(_ d: [String: Any]) {
        workoutKey = d.str("workoutKey"); exerciseKey = d.str("exerciseKey"); exerciseOrder = d.int("exerciseOrder")
        setOrder = d.int("setOrder"); kind = d.str("kind"); kg = d.num("kg"); reps = d.int("reps"); rir = d.optNum("rir")
        done = d.bool("done"); restSeconds = d.int("restSeconds"); day = d.str("day")
    }
    static func blank() -> Self { Self(workoutKey: "", exerciseKey: "", exerciseOrder: 0, setOrder: 0, day: "") }
}

extension SavedMeal: Syncable {
    static var syncType: String { "savedMeal" }
    func encode() -> [String: Any] {
        ["name": name, "items": encodeJSON(items), "useCount": useCount, "lastUsed": t(lastUsed), "createdAt": t(createdAt)]
    }
    func decode(_ d: [String: Any]) {
        name = d.str("name"); items = decodeJSON(d["items"]) ?? []; useCount = d.int("useCount")
        lastUsed = d.optDate("lastUsed"); createdAt = d.date("createdAt")
    }
    static func blank() -> Self { Self(name: "", items: []) }
}

extension DayNote: Syncable {
    static var syncType: String { "dayNote" }
    var naturalID: String { "note:\(day)" }                    // one per day
    func encode() -> [String: Any] { ["day": day, "text": text, "partial": partial] }
    func decode(_ d: [String: Any]) { day = d.str("day"); text = d.str("text"); partial = d.bool("partial") }
    static func blank() -> Self { Self(day: "") }
}
