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
                                             WaterEntry.self, DailyActivity.self]

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
