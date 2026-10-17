import Foundation

// Meal planner settings (synced on the profile as JSON).

struct PlannerSettings: Codable, Equatable {
    var meals = 4
    var wake = 7 * 60
    var sleep = 23 * 60
    var schedule: [Int: TrainingSlot] = [:]          // weekday → session (yours, once you edit it)
    var scheduleSet = false                          // false: the week inferred from your workouts
    var healthSessions: [String: TrainingSlot] = [:] // workouts from Apple Health (day → first session), last 6 weeks
    var staples: [Staple] = []                       // foods you eat regularly (manual, or confirmed suggestions)
    var dismissedStaples: [String] = []              // suggestions you said no to
    var stapleMinDays = 6                            // suggest a staple when logged on this many days…
    var stapleWindowDays = 28                        // …in this many days
    var roles: [String: FoodRole] = [:]              // your corrections to a food's role (main, side, condiment, treat)
    var weighAs: [String: WeightState] = [:]         // per food: you weigh it raw or cooked (default raw; sold-cooked foods cooked)
    var templates: [MealTemplate] = []               // your edited meal templates (empty: the defaults)
    var treatsEnabled = false                        // an evening snack with one treat a day
    var catalogRemoved: [String] = []                // simple foods you'd never buy (canonical ids)
    var inStock: [String] = []                       // tier 3 foods (and whey) you have: only these are planned
    var fibreFloorGrams: Double = 19                 // fixed fibre floor (g/day); 0: scale with calories (registry, 14 g per 1,000 kcal)
    var highDaysFollowTraining = true                // calorie distribution: training days = your training week
    var inferredWeek: [Int: TrainingSlot] = [:]      // last inferred from workouts (kept so targets can use it without a fetch)

    /// Your templates, or the defaults (a template you haven't edited follows the defaults).
    var mealTemplates: [MealTemplate] {
        MealTemplates.defaults.map { d in templates.first { $0.id == d.id } ?? d }
    }

    /// The day's fibre floor: your nutrient goal if set, else the fixed floor, else 14 g per 1,000 kcal.
    func fibreFloor(kcal: Double, custom: Double?) -> Double {
        if let custom { return custom }
        return fibreFloorGrams > 0 ? fibreFloorGrams : Evidence.value("fibre.per1000kcal") * kcal / 1000
    }

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

extension PlannerSettings {
    /// Tolerant: settings saved by an older version (missing fields) keep what they have and take the
    /// default for the rest, instead of resetting everything. A field that can't be read takes its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PlannerSettings()
        self = d
        meals = (try? c.decodeIfPresent(type(of: meals), forKey: .meals)) ?? d.meals
        wake = (try? c.decodeIfPresent(type(of: wake), forKey: .wake)) ?? d.wake
        sleep = (try? c.decodeIfPresent(type(of: sleep), forKey: .sleep)) ?? d.sleep
        schedule = (try? c.decodeIfPresent(type(of: schedule), forKey: .schedule)) ?? d.schedule
        scheduleSet = (try? c.decodeIfPresent(type(of: scheduleSet), forKey: .scheduleSet)) ?? d.scheduleSet
        healthSessions = (try? c.decodeIfPresent(type(of: healthSessions), forKey: .healthSessions)) ?? d.healthSessions
        staples = (try? c.decodeIfPresent(type(of: staples), forKey: .staples)) ?? d.staples
        dismissedStaples = (try? c.decodeIfPresent(type(of: dismissedStaples), forKey: .dismissedStaples)) ?? d.dismissedStaples
        stapleMinDays = (try? c.decodeIfPresent(type(of: stapleMinDays), forKey: .stapleMinDays)) ?? d.stapleMinDays
        stapleWindowDays = (try? c.decodeIfPresent(type(of: stapleWindowDays), forKey: .stapleWindowDays)) ?? d.stapleWindowDays
        roles = (try? c.decodeIfPresent(type(of: roles), forKey: .roles)) ?? d.roles
        weighAs = (try? c.decodeIfPresent(type(of: weighAs), forKey: .weighAs)) ?? d.weighAs
        fibreFloorGrams = (try? c.decodeIfPresent(type(of: fibreFloorGrams), forKey: .fibreFloorGrams)) ?? d.fibreFloorGrams
        highDaysFollowTraining = (try? c.decodeIfPresent(type(of: highDaysFollowTraining), forKey: .highDaysFollowTraining)) ?? d.highDaysFollowTraining
        inferredWeek = (try? c.decodeIfPresent(type(of: inferredWeek), forKey: .inferredWeek)) ?? d.inferredWeek
        overrides = (try? c.decodeIfPresent(type(of: overrides), forKey: .overrides)) ?? d.overrides
        fastedMorning = (try? c.decodeIfPresent(type(of: fastedMorning), forKey: .fastedMorning)) ?? d.fastedMorning
        preSleepProtein = (try? c.decodeIfPresent(type(of: preSleepProtein), forKey: .preSleepProtein)) ?? d.preSleepProtein
        exclusions = (try? c.decodeIfPresent(type(of: exclusions), forKey: .exclusions)) ?? d.exclusions
        variety = (try? c.decodeIfPresent(type(of: variety), forKey: .variety)) ?? d.variety
        locks = (try? c.decodeIfPresent(type(of: locks), forKey: .locks)) ?? d.locks
        iftar = (try? c.decodeIfPresent(type(of: iftar), forKey: .iftar)) ?? d.iftar
        suhoor = (try? c.decodeIfPresent(type(of: suhoor), forKey: .suhoor)) ?? d.suhoor
        trainingCarbBoost = (try? c.decodeIfPresent(type(of: trainingCarbBoost), forKey: .trainingCarbBoost)) ?? d.trainingCarbBoost
        dismissedCarbProposal = (try? c.decodeIfPresent(type(of: dismissedCarbProposal), forKey: .dismissedCarbProposal)) ?? d.dismissedCarbProposal
        templates = (try? c.decodeIfPresent(type(of: templates), forKey: .templates)) ?? d.templates
        treatsEnabled = (try? c.decodeIfPresent(type(of: treatsEnabled), forKey: .treatsEnabled)) ?? d.treatsEnabled
        catalogRemoved = (try? c.decodeIfPresent(type(of: catalogRemoved), forKey: .catalogRemoved)) ?? d.catalogRemoved
        inStock = (try? c.decodeIfPresent(type(of: inStock), forKey: .inStock)) ?? d.inStock
    }
}
