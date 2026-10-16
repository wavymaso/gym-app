import Foundation

// Meal planner settings (synced on the profile as JSON).

struct PlannerSettings: Codable, Equatable {
    var meals = 4
    var wake = 7 * 60
    var sleep = 23 * 60
    var schedule: [Int: TrainingSlot] = [:]          // weekday → session (yours, once you edit it)
    var scheduleSet = false                          // false: the week inferred from your workouts
    var healthSessions: [String: TrainingSlot] = [:] // workouts from Apple Health (day → first session), last 6 weeks
    var staples: [Staple] = []                       // cold start: foods you eat regularly
    var roles: [String: FoodRole] = [:]              // your corrections to a food's role (main, side, condiment, treat)
    var highDaysFollowTraining = true                // calorie distribution: training days = your training week
    var inferredWeek: [Int: TrainingSlot] = [:]      // last inferred from workouts (kept so targets can use it without a fetch)

    /// Your training weekdays for the calorie distribution (nil: not following, or no week yet).
    var trainingWeekdays: Set<Int>? {
        guard highDaysFollowTraining else { return nil }
        let w = week(inferredWeek)
        return w.isEmpty ? nil : Set(w.keys)
    }
    var overrides: [String: TrainingSlot] = [:]      // day → session (start < 0 = rest)
    var fastedMorning = false
    var preSleepProtein = false
    var exclusions: [String] = []                    // food keys
    var variety = 0.5
    var locks: [Int: [PlanItem]] = [:]               // slot → the meal you always want there
    var iftar = 19 * 60 + 30, suhoor = 28 * 60 + 30  // Ramadan window (suhoor after midnight)
    var trainingCarbBoost = false                    // accepted from the engine's proposal
    var dismissedCarbProposal = ""                   // day you said no (asked again after 2 weeks)

    /// Today's override, else your week (set by you, or inferred from your workouts).
    func training(on day: String, inferred: [Int: TrainingSlot]) -> TrainingSlot? {
        if let o = overrides[day] { return o.start < 0 ? nil : o }
        return week(inferred)[Calendar(identifier: .gregorian).component(.weekday, from: date(fromKey: day))]
    }
    func week(_ inferred: [Int: TrainingSlot]) -> [Int: TrainingSlot] { scheduleSet ? schedule : inferred }
}


extension Profile {
    var planner: PlannerSettings {
        get { (try? JSONDecoder().decode(PlannerSettings.self, from: Data(plannerJSON.utf8))) ?? PlannerSettings() }
        set { plannerJSON = String(decoding: (try? JSONEncoder().encode(newValue)) ?? Data(), as: UTF8.self) }
    }
}
