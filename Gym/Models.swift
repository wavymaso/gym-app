import Foundation
import SwiftData

// Your data, kept on this device. Choices are stored as text (Sex.rawValue, ...)
// so the stored data never depends on how the app's enums are written.

/// You: what the starting estimate is worked out from, and your units.
@Model final class Profile {
    var syncID: String = ""                   // the same on the Mac and the iPhone (Sync.swift)
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var sex: String
    var birthDate: Date
    var heightCm: Double
    var activity: String
    var weightUnit: String
    var energyUnit: String
    var createdAt: Date
    var goalWeightKg: Double? = nil           // optional: where you'd like your trend weight to end up
    var highDays: String = ""                 // calorie distribution: Calendar weekdays ("2,4,6") that get more
    var highDayExtra: Double = 0              // kcal added on those days (taken evenly from the others)
    var fastDays: String = ""                 // weekdays with a fixed low target (fasting days)
    var fastKcal: Double = 600
    // Expenditure settings (FeatureSettings.swift)
    var expManualKcal: Double = 0             // > 0: your own starting estimate instead of the formula
    var expStartDay: String = ""              // "" = from your first program
    var bmrEquation: String = "mifflin"
    var expStaticKcal: Double = 0             // > 0: a fixed expenditure ("static" mode)
    var expAlgorithm: String = ""             // "" = the default (see ExpenditureAlgorithm)
    var stepInformed: Bool = false
    var predictiveGoal: Bool = false

    init(sex: Sex, birthDate: Date, heightCm: Double, activity: Activity, weightUnit: WeightUnit, energyUnit: EnergyUnit) {
        self.sex = sex.rawValue; self.birthDate = birthDate; self.heightCm = heightCm; self.activity = activity.rawValue
        self.weightUnit = weightUnit.rawValue; self.energyUnit = energyUnit.rawValue; self.createdAt = Date()
    }

    var sexValue: Sex { Sex(rawValue: sex) ?? .male }
    var activityValue: Activity { Activity(rawValue: activity) ?? .moderate }
    var weight: WeightUnit { WeightUnit(rawValue: weightUnit) ?? .kg }
    var energy: EnergyUnit { EnergyUnit(rawValue: energyUnit) ?? .kcal }
}

/// A goal you're following: lose, maintain or gain, how fast, and how calories are split.
/// Changing your goal starts a new program; old ones are kept for history.
@Model final class Program {
    var syncID: String = ""                   // the same on the Mac and the iPhone (Sync.swift)
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var startDay: String
    var goal: String
    var ratePercent: Double          // % of body weight per week
    var dietStyle: String
    var proteinLevel: String
    var mode: String                 // coached (weekly check-ins suggest targets) | manual
    var startWeightKg: Double
    var startExpenditure: Double
    var isActive: Bool
    var checkInWeekday: Int = 2      // Calendar weekday: 1 = Sunday, 2 = Monday ...
    var lastCheckIn: String? = nil   // the day of the last check-in (applied or skipped)

    init(goal: GoalType, ratePercent: Double, diet: DietStyle, protein: ProteinLevel, startWeightKg: Double, startExpenditure: Double) {
        self.startDay = dayKey(); self.goal = goal.rawValue; self.ratePercent = ratePercent; self.dietStyle = diet.rawValue
        self.proteinLevel = protein.rawValue; self.mode = "coached"; self.startWeightKg = startWeightKg
        self.startExpenditure = startExpenditure; self.isActive = true
    }

    var goalValue: GoalType { GoalType(rawValue: goal) ?? .maintain }
    var dietValue: DietStyle { DietStyle(rawValue: dietStyle) ?? .balanced }
    var proteinValue: ProteinLevel { ProteinLevel(rawValue: proteinLevel) ?? .moderate }
}

/// Daily targets from a given day on. A new set is added at setup, at each weekly
/// check-in, and when you change your goal, so past days keep the targets they had.
@Model final class TargetSet {
    var syncID: String = ""                   // the same on the Mac and the iPhone (Sync.swift)
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var fromDay: String
    var kcal: Double
    var protein: Double
    var fat: Double
    var carbs: Double
    var expenditure: Double          // the estimate the targets were based on
    var reason: String               // setup | goal | check-in | manual
    var createdAt: Date

    init(fromDay: String = dayKey(), targets: Targets, expenditure: Double, reason: String) {
        self.fromDay = fromDay; self.kcal = targets.kcal; self.protein = targets.protein; self.fat = targets.fat
        self.carbs = targets.carbs; self.expenditure = expenditure; self.reason = reason; self.createdAt = Date()
    }

    var targets: Targets { Targets(kcal: kcal, protein: protein, fat: fat, carbs: carbs) }
}

/// A scale weight on a day (one per day; logging again replaces it).
@Model final class WeightEntry {
    var syncID: String = ""                   // the same on the Mac and the iPhone (Sync.swift)
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    @Attribute(.unique) var day: String
    var kg: Double
    var bodyFatPercent: Double?
    var createdAt: Date

    init(day: String = dayKey(), kg: Double, bodyFatPercent: Double? = nil) {
        self.day = day; self.kg = kg; self.bodyFatPercent = bodyFatPercent; self.createdAt = Date()
    }
}

let allModels: [any PersistentModel.Type] = [Profile.self, Program.self, TargetSet.self, WeightEntry.self,
                                             Food.self, RecipeIngredient.self, FoodEntry.self,
                                             Exercise.self, Routine.self, RoutineExercise.self, Workout.self, WorkoutSet.self, Tombstone.self,
                                             WaterEntry.self, DailyActivity.self, SavedMeal.self, DayNote.self]

// MARK: - Looking things up

extension ModelContext {
    var profile: Profile? { try? fetch(FetchDescriptor<Profile>()).first }

    var activeProgram: Program? {
        try? fetch(FetchDescriptor<Program>(predicate: #Predicate { $0.isActive }, sortBy: [SortDescriptor(\.startDay, order: .reverse)])).first
    }

    /// The targets that apply on a day: the newest set starting on or before it.
    func targets(on day: String = dayKey()) -> TargetSet? {
        var d = FetchDescriptor<TargetSet>(predicate: #Predicate { $0.fromDay <= day },
                                           sortBy: [SortDescriptor(\.fromDay, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)])
        d.fetchLimit = 1
        return try? fetch(d).first
    }

    var latestWeight: WeightEntry? {
        var d = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.day, order: .reverse)])
        d.fetchLimit = 1
        return try? fetch(d).first
    }

    /// Start a new program (the old one is kept, inactive) with targets from today.
    func startProgram(goal: GoalType, ratePercent: Double, diet: DietStyle, protein: ProteinLevel,
                      weightKg: Double, expenditure: Double, sex: Sex, reason: String) {
        let old = (try? fetch(FetchDescriptor<Program>(predicate: #Predicate { $0.isActive }))) ?? []
        old.forEach { $0.isActive = false }
        let p = Program(goal: goal, ratePercent: ratePercent, diet: diet, protein: protein, startWeightKg: weightKg,
                        startExpenditure: expenditure)
        p.checkInWeekday = old.first?.checkInWeekday ?? 2      // keep your check-in day
        insert(p)
        let t = makeTargets(expenditure: expenditure, weightKg: weightKg, sex: sex, goal: goal, ratePercent: ratePercent,
                            diet: diet, protein: protein)
        insert(TargetSet(targets: t, expenditure: expenditure, reason: reason))
        commit()
    }
}

// MARK: - Calorie distribution (different days, the same week)

extension Profile {
    var highDaySet: Set<Int> { Set(highDays.split(separator: ",").compactMap { Int($0) }) }
    var fastDaySet: Set<Int> { Set(fastDays.split(separator: ",").compactMap { Int($0) }) }
    var hasDistribution: Bool { (!highDaySet.isEmpty && highDayExtra > 0) || !fastDaySet.isEmpty }

    /// A day's targets after the weekly distribution (Calendar weekday of `day`).
    func adjust(_ t: Targets, on day: String) -> Targets {
        distribute(t, weekday: Calendar(identifier: .gregorian).component(.weekday, from: date(fromKey: day)),
                   high: highDaySet, extra: highDayExtra, fast: fastDaySet, fastKcal: fastKcal)
    }
}

/// Keeps the week's calories the same as 7 × the daily target:
/// fasting days get `fastKcal` (all macros scaled down), training days get `extra` more than
/// the remaining days, which share what's left. Off fasting days protein stays put; the
/// difference is carbs first, then fat.
func distribute(_ t: Targets, weekday: Int, high: Set<Int>, extra: Double, fast: Set<Int> = [], fastKcal: Double = 600) -> Targets {
    let fastDays = fast.subtracting([]), highDays = high.subtracting(fast)
    guard !fastDays.isEmpty || (extra > 0 && !highDays.isEmpty), fastDays.count < 7 else { return t }
    if fastDays.contains(weekday) {
        let f = t.kcal > 0 ? min(1, fastKcal / t.kcal) : 1
        return Targets(kcal: t.kcal * f, protein: t.protein * f, fat: t.fat * f, carbs: t.carbs * f)
    }
    let others = 7 - fastDays.count
    let e = highDays.count < others ? extra : 0                  // every remaining day "high" = no difference
    let base = (7 * t.kcal - Double(fastDays.count) * min(fastKcal, t.kcal) - Double(highDays.count) * e) / Double(others)
    let delta = (highDays.contains(weekday) ? base + e : base) - t.kcal
    var out = t
    out.kcal += delta
    out.carbs += delta / 4
    if out.carbs < 0 {
        out.fat = max(0, out.fat + out.carbs * 4 / 9)
        out.carbs = 0
    }
    return out
}
