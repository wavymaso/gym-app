import Foundation
import SwiftData

// Gym data. Linked by keys rather than relationships, like the food side, so
// deleting a routine or an exercise never takes your workout history with it.

@Model final class Exercise {
    var syncID: String = ""                   // the same on the Mac and the iPhone (Sync.swift)
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    @Attribute(.unique) var key: String       // builtin:<slug> | custom:<id>
    var name: String
    var muscle: String                        // Muscle.rawValue
    var secondary: [String]
    var equipment: String                     // Equipment.rawValue
    var isCustom: Bool
    var notes: String?
    var createdAt: Date

    init(key: String, name: String, muscle: Muscle, secondary: [Muscle] = [], equipment: Equipment, isCustom: Bool) {
        self.key = key; self.name = name; self.muscle = muscle.rawValue; self.secondary = secondary.map(\.rawValue)
        self.equipment = equipment.rawValue; self.isCustom = isCustom; self.createdAt = Date()
    }

    var muscleValue: Muscle { Muscle(rawValue: muscle) ?? .fullBody }
    var secondaryValues: [Muscle] { secondary.compactMap(Muscle.init(rawValue:)) }
    var equipmentValue: Equipment { Equipment(rawValue: equipment) ?? .other }
}

@Model final class Routine {
    var syncID: String = ""                   // the same on the Mac and the iPhone (Sync.swift)
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    @Attribute(.unique) var key: String
    var name: String
    var order: Int
    var createdAt: Date

    init(name: String, order: Int) {
        self.key = UUID().uuidString; self.name = name; self.order = order; self.createdAt = Date()
    }
}

@Model final class RoutineExercise {
    var syncID: String = ""                   // the same on the Mac and the iPhone (Sync.swift)
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var routineKey: String
    var exerciseKey: String
    var order: Int
    var sets: Int
    var repLow: Int
    var repHigh: Int
    var restSeconds: Int

    init(routineKey: String, exerciseKey: String, order: Int, sets: Int = 3, repLow: Int = 8, repHigh: Int = 12, restSeconds: Int = 120) {
        self.routineKey = routineKey; self.exerciseKey = exerciseKey; self.order = order; self.sets = sets
        self.repLow = repLow; self.repHigh = repHigh; self.restSeconds = restSeconds
    }
}

@Model final class Workout {
    var syncID: String = ""                   // the same on the Mac and the iPhone (Sync.swift)
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    @Attribute(.unique) var key: String
    var name: String
    var start: Date
    var end: Date?                            // nil while you're training
    var routineKey: String?
    var notes: String?
    var exerciseNotes: String = ""            // JSON {exerciseKey: note}

    var notesByExercise: [String: String] {
        get { (try? JSONDecoder().decode([String: String].self, from: Data(exerciseNotes.utf8))) ?? [:] }
        set { exerciseNotes = (try? JSONEncoder().encode(newValue)).map { String(decoding: $0, as: UTF8.self) } ?? "" }
    }

    init(name: String, routineKey: String? = nil, start: Date = Date()) {
        self.key = UUID().uuidString; self.name = name; self.start = start; self.routineKey = routineKey
    }

    var day: String { dayKey(start) }
    var duration: Int { Int((end ?? Date()).timeIntervalSince(start)) }
}

@Model final class WorkoutSet {
    var syncID: String = ""                   // the same on the Mac and the iPhone (Sync.swift)
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var workoutKey: String
    var exerciseKey: String
    var exerciseOrder: Int                    // position of the exercise in the workout
    var setOrder: Int
    var kind: String                          // SetKind.rawValue
    var kg: Double
    var reps: Int
    var rir: Double?                          // reps in reserve, if you track it
    var done: Bool
    var restSeconds: Int
    var day: String
    var group: Int = 0                        // > 0: in a superset with the other exercises sharing the number
    var side: String = ""                     // "L" / "R" when tracking each side

    init(workoutKey: String, exerciseKey: String, exerciseOrder: Int, setOrder: Int, kind: SetKind = .normal, kg: Double = 0,
         reps: Int = 0, restSeconds: Int = 120, day: String) {
        self.workoutKey = workoutKey; self.exerciseKey = exerciseKey; self.exerciseOrder = exerciseOrder; self.setOrder = setOrder
        self.kind = kind.rawValue; self.kg = kg; self.reps = reps; self.done = false; self.restSeconds = restSeconds; self.day = day
    }

    var kindValue: SetKind { SetKind(rawValue: kind) ?? .normal }
    var lift: LiftSet { LiftSet(day: day, kg: kg, reps: reps, kind: kindValue) }
}

extension ModelContext {
    func exercise(_ key: String) -> Exercise? {
        try? fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.key == key })).first
    }

    var activeWorkout: Workout? {
        try? fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.end == nil })).first
    }

    func sets(of workoutKey: String) -> [WorkoutSet] {
        (try? fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.workoutKey == workoutKey },
                                                sortBy: [SortDescriptor(\.exerciseOrder), SortDescriptor(\.setOrder)]))) ?? []
    }

    /// Every completed set of an exercise, oldest first (only from finished workouts, plus done sets of the current one).
    func history(of exerciseKey: String, excluding workoutKey: String? = nil) -> [WorkoutSet] {
        let all = (try? fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.exerciseKey == exerciseKey && $0.done },
                                                          sortBy: [SortDescriptor(\.day), SortDescriptor(\.setOrder)]))) ?? []
        return all.filter { $0.workoutKey != workoutKey }
    }

    /// The sets you did last time for this exercise ("previous" column).
    func previousSets(of exerciseKey: String, before workoutKey: String) -> [WorkoutSet] {
        let h = history(of: exerciseKey, excluding: workoutKey)
        guard let last = h.last?.workoutKey else { return [] }
        return h.filter { $0.workoutKey == last }
    }

    /// Start a workout, from a routine (its exercises and set counts, last time's weights filled in) or empty.
    @discardableResult
    func startWorkout(routine: Routine?) -> Workout {
        let w = Workout(name: routine?.name ?? "Workout", routineKey: routine?.key)
        insert(w)
        if let r = routine {
            let rk = r.key
            let items = (try? fetch(FetchDescriptor<RoutineExercise>(predicate: #Predicate { $0.routineKey == rk }, sortBy: [SortDescriptor(\.order)]))) ?? []
            for (i, item) in items.enumerated() {
                addExercise(item.exerciseKey, to: w, order: i, sets: item.sets, rest: item.restSeconds, reps: item.repLow, repHigh: item.repHigh)
            }
        }
        commit()
        return w
    }

    func addExercise(_ exerciseKey: String, to w: Workout, order: Int, sets n: Int = 3, rest: Int = 120, reps: Int = 0, repHigh: Int = 0) {
        let prev = previousSets(of: exerciseKey, before: w.key).filter { $0.kindValue.counts }
        // Auto-progression: last time's sets moved on by the double-progression rule.
        let (lo, hi) = reps > 0 ? (reps, max(reps, repHigh)) : (8, 12)
        let target = nextTarget(previous: prev.map(\.lift), repLow: lo, repHigh: hi, step: weightStep(exercise(exerciseKey)?.equipmentValue ?? .other))
        for i in 0..<n {
            let p = prev.indices.contains(i) ? prev[i] : prev.last
            let kg = target?.kg ?? p?.kg ?? 0
            let r = target.map { $0.reps.indices.contains(i) ? $0.reps[i] : ($0.reps.last ?? lo) } ?? p?.reps ?? reps
            insert(WorkoutSet(workoutKey: w.key, exerciseKey: exerciseKey, exerciseOrder: order, setOrder: i, kg: kg,
                              reps: r, restSeconds: rest, day: w.day))
        }
    }

    /// The rep range for an exercise in this workout: its routine's, or 8–12.
    func repRange(_ exerciseKey: String, routineKey: String?) -> (Int, Int) {
        guard let rk = routineKey,
              let item = try? fetch(FetchDescriptor<RoutineExercise>(predicate: #Predicate { $0.routineKey == rk && $0.exerciseKey == exerciseKey })).first,
              item.repLow > 0 else { return (8, 12) }
        return (item.repLow, max(item.repLow, item.repHigh))
    }

    /// Warm-up sets before the first working set (ramped, rounded to loadable weights).
    func addWarmUps(exerciseKey: String, order: Int, to w: Workout) {
        let rows = sets(of: w.key).filter { $0.exerciseOrder == order }
        guard let first = rows.filter({ $0.kindValue.counts }).min(by: { $0.setOrder < $1.setOrder }), first.kg > 0 else { return }
        let eq = exercise(exerciseKey)?.equipmentValue ?? .other
        let bar = eq == .barbell ? (UserDefaults.standard.object(forKey: "barKg") as? Double ?? 20) : 0
        let ramp = warmUps(working: first.kg, bar: bar, step: max(weightStep(eq), 1))
        let start = (rows.map(\.setOrder).min() ?? 0) - ramp.count
        for (i, s) in ramp.enumerated() {
            insert(WorkoutSet(workoutKey: w.key, exerciseKey: exerciseKey, exerciseOrder: order, setOrder: start + i, kind: .warmup,
                              kg: s.kg, reps: s.reps, restSeconds: 60, day: w.day))
        }
        commit()
    }

    /// Swap an exercise for another (sets not yet done), with that exercise's own last weights.
    func swap(order: Int, in w: Workout, to newKey: String) {
        let rows = sets(of: w.key).filter { $0.exerciseOrder == order && !$0.done }
        let prev = previousSets(of: newKey, before: w.key).filter { $0.kindValue.counts }
        for (i, s) in rows.sorted(by: { $0.setOrder < $1.setOrder }).enumerated() {
            s.exerciseKey = newKey
            if let p = prev.indices.contains(i) ? prev[i] : prev.last { s.kg = p.kg; s.reps = p.reps } else { s.kg = 0 }
        }
        commit()
    }

    /// Exercises that work the same main muscle, the same equipment first.
    func alternatives(to key: String) -> [Exercise] {
        guard let e = exercise(key) else { return [] }
        let m = e.muscle
        let all = (try? fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.muscle == m }))) ?? []
        return all.filter { $0.key != key }.sorted { ($0.equipment == e.equipment ? 0 : 1, $0.name) < ($1.equipment == e.equipment ? 0 : 1, $1.name) }
    }

    /// Finish: keep only the sets you ticked.
    func finish(_ w: Workout) {
        w.end = Date()
        for s in sets(of: w.key) where !s.done { delete(s) }
        commit()
    }

    func discard(_ w: Workout) {
        for s in sets(of: w.key) { delete(s) }
        delete(w)
        commit()
    }

    /// The built-in exercise library, added once.
    func seedExercises() {
        // Add whatever's missing (the library grows with updates; built-ins match across devices by key).
        let have = Set(((try? fetch(FetchDescriptor<Exercise>(predicate: #Predicate { !$0.isCustom }))) ?? []).map(\.key))
        var added = 0
        for (slug, name, muscle, secondary, equipment) in exerciseLibrary + exerciseLibraryMore where !have.contains("builtin:\(slug)") {
            insert(Exercise(key: "builtin:\(slug)", name: name, muscle: muscle, secondary: secondary, equipment: equipment, isCustom: false))
            added += 1
        }
        if added > 0 { commit() }
    }
}

let exerciseLibrary: [(String, String, Muscle, [Muscle], Equipment)] = [
    ("bench-press", "Bench press", .chest, [.triceps, .shoulders], .barbell),
    ("incline-bench-press", "Incline bench press", .chest, [.shoulders, .triceps], .barbell),
    ("db-bench-press", "Dumbbell bench press", .chest, [.triceps, .shoulders], .dumbbell),
    ("incline-db-press", "Incline dumbbell press", .chest, [.shoulders, .triceps], .dumbbell),
    ("chest-fly-machine", "Chest fly (machine)", .chest, [], .machine),
    ("cable-fly", "Cable fly", .chest, [], .cable),
    ("chest-press-machine", "Chest press (machine)", .chest, [.triceps], .machine),
    ("push-up", "Push-up", .chest, [.triceps, .shoulders], .bodyweight),
    ("dip", "Dip", .chest, [.triceps], .bodyweight),
    ("deadlift", "Deadlift", .back, [.hamstrings, .glutes, .forearms], .barbell),
    ("pull-up", "Pull-up", .back, [.biceps], .bodyweight),
    ("chin-up", "Chin-up", .back, [.biceps], .bodyweight),
    ("lat-pulldown", "Lat pulldown", .back, [.biceps], .cable),
    ("barbell-row", "Barbell row", .back, [.biceps], .barbell),
    ("db-row", "Dumbbell row", .back, [.biceps], .dumbbell),
    ("seated-cable-row", "Seated cable row", .back, [.biceps], .cable),
    ("machine-row", "Row (machine)", .back, [.biceps], .machine),
    ("t-bar-row", "T-bar row", .back, [.biceps], .barbell),
    ("back-extension", "Back extension", .back, [.glutes, .hamstrings], .bodyweight),
    ("overhead-press", "Overhead press", .shoulders, [.triceps], .barbell),
    ("db-shoulder-press", "Dumbbell shoulder press", .shoulders, [.triceps], .dumbbell),
    ("shoulder-press-machine", "Shoulder press (machine)", .shoulders, [.triceps], .machine),
    ("lateral-raise", "Lateral raise", .shoulders, [], .dumbbell),
    ("cable-lateral-raise", "Cable lateral raise", .shoulders, [], .cable),
    ("rear-delt-fly", "Rear delt fly", .shoulders, [.back], .dumbbell),
    ("face-pull", "Face pull", .shoulders, [.back], .cable),
    ("barbell-curl", "Barbell curl", .biceps, [.forearms], .barbell),
    ("db-curl", "Dumbbell curl", .biceps, [.forearms], .dumbbell),
    ("hammer-curl", "Hammer curl", .biceps, [.forearms], .dumbbell),
    ("preacher-curl", "Preacher curl", .biceps, [], .machine),
    ("cable-curl", "Cable curl", .biceps, [], .cable),
    ("triceps-pushdown", "Triceps pushdown", .triceps, [], .cable),
    ("overhead-triceps-extension", "Overhead triceps extension", .triceps, [], .cable),
    ("skull-crusher", "Skull crusher", .triceps, [], .barbell),
    ("close-grip-bench", "Close-grip bench press", .triceps, [.chest], .barbell),
    ("squat", "Squat", .quads, [.glutes, .hamstrings], .barbell),
    ("front-squat", "Front squat", .quads, [.glutes], .barbell),
    ("leg-press", "Leg press", .quads, [.glutes], .machine),
    ("hack-squat", "Hack squat", .quads, [.glutes], .machine),
    ("leg-extension", "Leg extension", .quads, [], .machine),
    ("bulgarian-split-squat", "Bulgarian split squat", .quads, [.glutes], .dumbbell),
    ("lunge", "Walking lunge", .quads, [.glutes], .dumbbell),
    ("goblet-squat", "Goblet squat", .quads, [.glutes], .dumbbell),
    ("romanian-deadlift", "Romanian deadlift", .hamstrings, [.glutes, .back], .barbell),
    ("lying-leg-curl", "Lying leg curl", .hamstrings, [], .machine),
    ("seated-leg-curl", "Seated leg curl", .hamstrings, [], .machine),
    ("hip-thrust", "Hip thrust", .glutes, [.hamstrings], .barbell),
    ("glute-kickback", "Cable glute kickback", .glutes, [], .cable),
    ("hip-abduction", "Hip abduction (machine)", .glutes, [], .machine),
    ("standing-calf-raise", "Standing calf raise", .calves, [], .machine),
    ("seated-calf-raise", "Seated calf raise", .calves, [], .machine),
    ("crunch", "Crunch", .abs, [], .bodyweight),
    ("cable-crunch", "Cable crunch", .abs, [], .cable),
    ("hanging-leg-raise", "Hanging leg raise", .abs, [], .bodyweight),
    ("plank", "Plank (seconds as reps)", .abs, [], .bodyweight),
    ("ab-wheel", "Ab wheel", .abs, [], .other),
    ("wrist-curl", "Wrist curl", .forearms, [], .dumbbell),
    ("farmers-walk", "Farmer's walk", .fullBody, [.forearms], .dumbbell),
    ("kettlebell-swing", "Kettlebell swing", .fullBody, [.glutes, .hamstrings], .kettlebell),
    ("power-clean", "Power clean", .fullBody, [.back, .quads], .barbell),
    ("treadmill", "Treadmill (minutes as reps)", .cardio, [], .machine),
    ("bike", "Bike (minutes as reps)", .cardio, [], .machine),
]

extension ModelContext {
    /// Put an exercise in a superset with the next one (joining its group if it has one).
    func supersetWithNext(order: Int, in w: Workout) {
        let all = sets(of: w.key)
        let orders = Set(all.map(\.exerciseOrder)).sorted()
        guard let i = orders.firstIndex(of: order), i + 1 < orders.count else { return }
        let next = orders[i + 1]
        let g = all.first { $0.exerciseOrder == order && $0.group > 0 }?.group
            ?? all.first { $0.exerciseOrder == next && $0.group > 0 }?.group
            ?? ((all.map(\.group).max() ?? 0) + 1)
        for s in all where s.exerciseOrder == order || s.exerciseOrder == next { s.group = g }
        commit()
    }

    func leaveSuperset(order: Int, in w: Workout) {
        for s in sets(of: w.key) where s.exerciseOrder == order { s.group = 0 }
        commit()
    }

    /// Track each side: every set not yet done becomes a left and a right set.
    func trackSides(order: Int, in w: Workout) {
        let rows = sets(of: w.key).filter { $0.exerciseOrder == order }.sorted { $0.setOrder < $1.setOrder }
        guard !rows.contains(where: { !$0.side.isEmpty }) else { return }
        var next = 0
        for s in rows {
            if s.done { s.setOrder = next; next += 1; continue }
            s.side = "L"; s.setOrder = next
            let r = WorkoutSet(workoutKey: s.workoutKey, exerciseKey: s.exerciseKey, exerciseOrder: s.exerciseOrder, setOrder: next + 1,
                               kind: s.kindValue, kg: s.kg, reps: s.reps, restSeconds: s.restSeconds, day: s.day)
            r.side = "R"; r.group = s.group
            insert(r); next += 2
        }
        commit()
    }

    /// Last time's note on an exercise, if any.
    func lastNote(for exerciseKey: String, before workoutKey: String) -> String? {
        let ws = (try? fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.end != nil }, sortBy: [SortDescriptor(\.start, order: .reverse)]))) ?? []
        return ws.first { $0.key != workoutKey && !($0.notesByExercise[exerciseKey] ?? "").isEmpty }?.notesByExercise[exerciseKey]
    }
}

/// More of what bodybuilders actually do: machines, cables, unilateral and isolation work.
let exerciseLibraryMore: [(String, String, Muscle, [Muscle], Equipment)] = [
    // Chest
    ("decline-bench-press", "Decline bench press", .chest, [.triceps], .barbell),
    ("incline-chest-press-machine", "Incline chest press (machine)", .chest, [.shoulders, .triceps], .machine),
    ("smith-incline-press", "Smith machine incline press", .chest, [.shoulders, .triceps], .machine),
    ("smith-bench-press", "Smith machine bench press", .chest, [.triceps, .shoulders], .machine),
    ("pec-deck", "Pec deck", .chest, [], .machine),
    ("low-to-high-cable-fly", "Low-to-high cable fly", .chest, [.shoulders], .cable),
    ("high-to-low-cable-fly", "High-to-low cable fly", .chest, [], .cable),
    ("db-fly", "Dumbbell fly", .chest, [], .dumbbell),
    ("incline-db-fly", "Incline dumbbell fly", .chest, [.shoulders], .dumbbell),
    ("weighted-dip", "Weighted dip", .chest, [.triceps], .other),
    ("hammer-strength-press", "Hammer Strength chest press", .chest, [.triceps], .machine),
    ("deficit-push-up", "Deficit push-up", .chest, [.triceps], .bodyweight),
    // Back
    ("weighted-pull-up", "Weighted pull-up", .back, [.biceps], .other),
    ("neutral-grip-pulldown", "Neutral-grip pulldown", .back, [.biceps], .cable),
    ("single-arm-pulldown", "Single-arm cable pulldown", .back, [.biceps], .cable),
    ("straight-arm-pulldown", "Straight-arm pulldown", .back, [], .cable),
    ("chest-supported-row", "Chest-supported row", .back, [.biceps], .dumbbell),
    ("pendlay-row", "Pendlay row", .back, [.biceps], .barbell),
    ("seal-row", "Seal row", .back, [.biceps], .barbell),
    ("meadows-row", "Meadows row", .back, [.biceps], .barbell),
    ("single-arm-cable-row", "Single-arm cable row", .back, [.biceps], .cable),
    ("hammer-strength-row", "Hammer Strength row", .back, [.biceps], .machine),
    ("high-row-machine", "High row (machine)", .back, [.biceps], .machine),
    ("rack-pull", "Rack pull", .back, [.glutes, .forearms], .barbell),
    ("pullover-machine", "Pullover (machine)", .back, [.chest], .machine),
    ("db-pullover", "Dumbbell pullover", .back, [.chest], .dumbbell),
    ("barbell-shrug", "Barbell shrug", .back, [.forearms], .barbell),
    ("db-shrug", "Dumbbell shrug", .back, [.forearms], .dumbbell),
    ("assisted-pull-up", "Assisted pull-up (machine)", .back, [.biceps], .machine),
    ("inverted-row", "Inverted row", .back, [.biceps], .bodyweight),
    // Shoulders
    ("seated-db-press", "Seated dumbbell press", .shoulders, [.triceps], .dumbbell),
    ("arnold-press", "Arnold press", .shoulders, [.triceps], .dumbbell),
    ("smith-shoulder-press", "Smith machine shoulder press", .shoulders, [.triceps], .machine),
    ("push-press", "Push press", .shoulders, [.triceps, .quads], .barbell),
    ("lateral-raise-machine", "Lateral raise (machine)", .shoulders, [], .machine),
    ("lean-away-lateral-raise", "Lean-away lateral raise", .shoulders, [], .dumbbell),
    ("y-raise", "Cable Y-raise", .shoulders, [], .cable),
    ("rear-delt-machine", "Reverse pec deck", .shoulders, [.back], .machine),
    ("cable-rear-delt-fly", "Cable rear delt fly", .shoulders, [.back], .cable),
    ("front-raise", "Front raise", .shoulders, [], .dumbbell),
    ("upright-row", "Upright row", .shoulders, [.back], .barbell),
    ("cable-upright-row", "Cable upright row", .shoulders, [.back], .cable),
    // Biceps
    ("ez-bar-curl", "EZ-bar curl", .biceps, [.forearms], .barbell),
    ("incline-db-curl", "Incline dumbbell curl", .biceps, [], .dumbbell),
    ("bayesian-curl", "Bayesian cable curl", .biceps, [], .cable),
    ("spider-curl", "Spider curl", .biceps, [], .dumbbell),
    ("concentration-curl", "Concentration curl", .biceps, [], .dumbbell),
    ("preacher-curl-machine", "Preacher curl (machine)", .biceps, [], .machine),
    ("cable-hammer-curl", "Rope hammer curl", .biceps, [.forearms], .cable),
    ("reverse-curl", "Reverse curl", .forearms, [.biceps], .barbell),
    // Triceps
    ("rope-pushdown", "Rope pushdown", .triceps, [], .cable),
    ("single-arm-pushdown", "Single-arm pushdown", .triceps, [], .cable),
    ("cable-overhead-extension", "Cable overhead extension", .triceps, [], .cable),
    ("db-overhead-extension", "Dumbbell overhead extension", .triceps, [], .dumbbell),
    ("jm-press", "JM press", .triceps, [.chest], .barbell),
    ("dip-machine", "Dip (machine)", .triceps, [.chest], .machine),
    ("triceps-extension-machine", "Triceps extension (machine)", .triceps, [], .machine),
    ("kickback", "Triceps kickback", .triceps, [], .dumbbell),
    // Quads
    ("smith-squat", "Smith machine squat", .quads, [.glutes], .machine),
    ("pendulum-squat", "Pendulum squat", .quads, [.glutes], .machine),
    ("belt-squat", "Belt squat", .quads, [.glutes], .machine),
    ("v-squat", "V-squat", .quads, [.glutes], .machine),
    ("high-bar-squat", "High-bar squat", .quads, [.glutes], .barbell),
    ("safety-bar-squat", "Safety bar squat", .quads, [.glutes, .back], .barbell),
    ("single-leg-press", "Single-leg press", .quads, [.glutes], .machine),
    ("single-leg-extension", "Single-leg extension", .quads, [], .machine),
    ("sissy-squat", "Sissy squat", .quads, [], .bodyweight),
    ("walking-lunge", "Walking lunge", .quads, [.glutes], .dumbbell),
    ("step-up", "Step-up", .quads, [.glutes], .dumbbell),
    ("reverse-lunge", "Reverse lunge", .quads, [.glutes], .dumbbell),
    // Hamstrings and glutes
    ("stiff-leg-deadlift", "Stiff-leg deadlift", .hamstrings, [.glutes, .back], .barbell),
    ("db-romanian-deadlift", "Dumbbell Romanian deadlift", .hamstrings, [.glutes], .dumbbell),
    ("single-leg-rdl", "Single-leg Romanian deadlift", .hamstrings, [.glutes], .dumbbell),
    ("nordic-curl", "Nordic curl", .hamstrings, [], .bodyweight),
    ("standing-leg-curl", "Standing leg curl", .hamstrings, [], .machine),
    ("glute-ham-raise", "Glute-ham raise", .hamstrings, [.glutes], .bodyweight),
    ("good-morning", "Good morning", .hamstrings, [.back, .glutes], .barbell),
    ("45-back-extension", "45° back extension", .glutes, [.hamstrings, .back], .bodyweight),
    ("hip-thrust-machine", "Hip thrust (machine)", .glutes, [.hamstrings], .machine),
    ("glute-bridge", "Glute bridge", .glutes, [.hamstrings], .barbell),
    ("cable-pull-through", "Cable pull-through", .glutes, [.hamstrings], .cable),
    ("hip-adduction", "Hip adduction", .quads, [], .machine),
    ("sumo-deadlift", "Sumo deadlift", .glutes, [.quads, .back], .barbell),
    // Calves
    ("leg-press-calf-raise", "Calf raise on leg press", .calves, [], .machine),
    ("smith-calf-raise", "Smith machine calf raise", .calves, [], .machine),
    ("single-leg-calf-raise", "Single-leg calf raise", .calves, [], .dumbbell),
    // Abs
    ("ab-crunch-machine", "Crunch (machine)", .abs, [], .machine),
    ("decline-crunch", "Decline crunch", .abs, [], .bodyweight),
    ("captains-chair-raise", "Captain's chair knee raise", .abs, [], .bodyweight),
    ("pallof-press", "Pallof press", .abs, [], .cable),
    ("cable-woodchop", "Cable woodchop", .abs, [], .cable),
    ("weighted-plank", "Weighted plank", .abs, [], .other),
    // Cardio
    ("stairmaster", "Stairmaster", .cardio, [], .machine),
    ("incline-walk", "Incline treadmill walk", .cardio, [], .machine),
    ("rowing-machine", "Rowing machine", .cardio, [.back], .machine),
    ("elliptical", "Elliptical", .cardio, [], .machine),
]
