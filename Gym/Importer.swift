import Foundation
import SwiftData

// Applying an import (ImportParse.swift reads the files). Importing the same file
// twice changes nothing: days you've logged, weigh-ins you have and workouts already
// there are left alone.

struct ImportResult: Equatable {
    var weights = 0
    var foodDays = 0
    var foods = 0
    var totalDays = 0
    var workouts = 0
    var sets = 0
    var newExercises = 0
    var targetChanges = 0
    var historyStart: String?
}

extension ModelContext {
    func applyImport(_ c: ImportContents) -> ImportResult {
        var r = ImportResult()
        let ownDays = Set(((try? fetch(FetchDescriptor<FoodEntry>())) ?? []).map(\.day))
        let weighed = Set(((try? fetch(FetchDescriptor<WeightEntry>())) ?? []).map(\.day))

        // Weigh-ins
        for d in c.days {
            guard let kg = d.weightKg, !weighed.contains(d.day) else { continue }
            insert(WeightEntry(day: d.day, kg: kg, bodyFatPercent: d.bodyFat))
            r.weights += 1
        }

        // Food: item by item where there's a food log, else the day's total.
        let foodsByDay = Dictionary(grouping: c.foods, by: \.day)
        for (day, items) in foodsByDay where !ownDays.contains(day) {
            for (i, f) in items.enumerated() {
                let t = f.time ?? date(fromKey: day).addingTimeInterval(TimeInterval(8 * 3600 + i * 60))
                insert(FoodEntry(day: day, time: t, name: f.name, brand: nil, foodKey: "import", amount: 1,
                                 unit: f.amountText.isEmpty ? "Imported" : f.amountText, grams: 0, nutrients: f.nutrients))
                r.foods += 1
            }
            r.foodDays += 1
        }
        for d in c.days where foodsByDay[d.day] == nil && !ownDays.contains(d.day) {
            guard let n = d.nutrients else { continue }
            insert(FoodEntry(day: d.day, time: date(fromKey: d.day).addingTimeInterval(13 * 3600), name: "Day total (imported)", brand: nil,
                             foodKey: "import", amount: 1, unit: "Imported total", grams: 0, nutrients: n))
            r.totalDays += 1
        }

        // History before the app: targets as they changed, and the expenditure to start estimating from.
        if let first = try? fetch(FetchDescriptor<Program>(sortBy: [SortDescriptor(\.startDay)])).first {
            let earlier = c.days.filter { $0.day < first.startDay }
            var last: Targets?
            for d in earlier {
                guard let t = d.targets, t != last else { continue }
                insert(TargetSet(fromDay: d.day, targets: t, expenditure: d.expenditure ?? first.startExpenditure, reason: "import"))
                last = t; r.targetChanges += 1
            }
            let starts = (earlier.filter { $0.nutrients != nil || $0.weightKg != nil }.map(\.day) + c.foods.map(\.day).filter { $0 < first.startDay }).sorted()
            if let start = starts.first {
                first.startDay = start
                if let e = earlier.first(where: { $0.expenditure != nil })?.expenditure { first.startExpenditure = e }
                r.historyStart = start
            }
        }

        // Workouts, grouped by day and name; exercises matched to the library by name.
        let library = (try? fetch(FetchDescriptor<Exercise>())) ?? []
        var byName = Dictionary(library.map { (FoodAPI.fold($0.name), $0.key) }, uniquingKeysWith: { a, _ in a })
        let existing = Set(((try? fetch(FetchDescriptor<Workout>())) ?? []).map { "\($0.day)|\($0.name)" })
        let groups = Dictionary(grouping: c.sets) { "\($0.day)|\($0.workout)" }
        for (key, sets) in groups.sorted(by: { $0.key < $1.key }) where !existing.contains(key) {
            let first = sets[0]
            let start = sets.compactMap(\.time).min() ?? date(fromKey: first.day).addingTimeInterval(18 * 3600)
            let w = Workout(name: first.workout, start: start)
            w.end = max(sets.compactMap(\.time).max() ?? start, start.addingTimeInterval(3600))
            insert(w)
            var order: [String: Int] = [:]
            var setIndex: [String: Int] = [:]
            for s in sets {
                let folded = FoodAPI.fold(s.exercise)
                let exKey = byName[folded] ?? {
                    let e = Exercise(key: "custom:\(UUID().uuidString)", name: s.exercise, muscle: .fullBody, equipment: .other, isCustom: true)
                    insert(e); byName[folded] = e.key; r.newExercises += 1
                    return e.key
                }()
                if order[exKey] == nil { order[exKey] = order.count }
                let n = setIndex[exKey, default: 0]; setIndex[exKey] = n + 1
                let ws = WorkoutSet(workoutKey: w.key, exerciseKey: exKey, exerciseOrder: order[exKey]!, setOrder: n, kg: s.kg, reps: s.reps, day: w.day)
                ws.rir = s.rir; ws.done = true
                insert(ws); r.sets += 1
            }
            r.workouts += 1
        }
        commit()
        return r
    }
}
