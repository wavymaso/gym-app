import AppIntents
import SwiftData
import SwiftUI

// Siri, Shortcuts, Spotlight and the Action button: the quick things without opening the app
// (log water, weigh in, quick add, calories left), and shortcuts into it (photo log, train).

/// The one database, shared by the app and its intents.
enum Store {
    @MainActor static let container: ModelContainer = {
        let schema = Schema(allModels)
        #if DEBUG
        let inMemory = UserDefaults.standard.bool(forKey: "inMemory")      // testing only: -inMemory
        #else
        let inMemory = false
        #endif
        let c = try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory))
        c.mainContext.autosaveEnabled = false        // every save goes through commit(), which stamps changes for sync
        c.mainContext.backfillSyncIDs()              // records from before sync existed
        return c
    }()
}

extension Notification.Name {
    static let gymOpenAction = Notification.Name("gymOpenAction")
}

/// What an intent asked the app to open (read when the app comes to the front).
enum PendingAction {
    static let key = "pendingAction"
    static func set(_ s: String) {
        UserDefaults.standard.set(s, forKey: key)
        NotificationCenter.default.post(name: .gymOpenAction, object: nil)
    }
    static func take() -> String? {
        defer { UserDefaults.standard.removeObject(forKey: key) }
        return UserDefaults.standard.string(forKey: key)
    }
}

struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log water"
    static let description = IntentDescription("Add a glass of water to today.")

    @Parameter(title: "Amount (ml)", default: 250, inclusiveRange: (50, 2000)) var ml: Int

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = Store.container.mainContext
        ctx.addWater(Double(ml))
        let total = ctx.water(on: dayKey()).reduce(0) { $0 + $1.ml }
        WidgetData.write(ctx)
        return .result(dialog: "Added \(ml) ml. \(number(total)) of \(number(ctx.waterGoalMl)) ml today.")
    }
}

struct LogWeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Log weight"
    static let description = IntentDescription("Record today's weigh-in, in your weight unit.")

    @Parameter(title: "Weight") var weight: Double

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = Store.container.mainContext
        let unit = (try? ctx.fetch(FetchDescriptor<Profile>()).first?.weight) ?? .kg
        let kg = unit.toKg(weight)
        guard kg > 25, kg < 350 else { return .result(dialog: "That doesn't look like a weight. Nothing logged.") }
        ctx.logWeight(kg)
        WidgetData.write(ctx)
        let trend = trendSeries(((try? ctx.fetch(FetchDescriptor<WeightEntry>())) ?? []).map { DayValue(day: $0.day, value: $0.kg) },
                                through: dayKey()).last?.trend
        return .result(dialog: "Logged \(unit.format(kg)).\(trend.map { " Trend: \(unit.format($0))." } ?? "")")
    }
}

struct QuickAddIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick add calories"
    static let description = IntentDescription("Log calories (and protein if you know it) without choosing a food.")

    @Parameter(title: "Calories") var kcal: Int
    @Parameter(title: "Protein (g)") var protein: Int?
    @Parameter(title: "Name") var name: String?

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = Store.container.mainContext
        let p = Double(protein ?? 0)
        ctx.insert(FoodEntry(day: dayKey(), time: Date(), name: name?.isEmpty == false ? name! : "Quick add", brand: nil, foodKey: nil,
                             amount: 1, unit: "", grams: 0, nutrients: Nutrients(kcal: Double(kcal), protein: p, fat: 0, carbs: 0)))
        ctx.commit()
        WidgetData.write(ctx)
        return .result(dialog: "Added \(kcal) kcal. \(CaloriesLeftIntent.left(ctx))")
    }
}

struct CaloriesLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Calories left today"
    static let description = IntentDescription("How much is left of today's calories and macros.")

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let ctx = Store.container.mainContext
        let left = Self.remaining(ctx)
        return .result(value: Int(left?.kcal ?? 0), dialog: "\(Self.left(ctx))")
    }

    @MainActor static func remaining(_ ctx: ModelContext) -> Targets? {
        guard let t = ctx.dayTargets(on: dayKey()) else { return nil }
        let eaten = ctx.entries(on: dayKey()).reduce(Nutrients.zero) { $0 + $1.nutrients }
        return Targets(kcal: t.kcal - eaten.kcal, protein: t.protein - eaten.protein, fat: t.fat - eaten.fat, carbs: t.carbs - eaten.carbs)
    }

    @MainActor static func left(_ ctx: ModelContext) -> String {
        guard let r = remaining(ctx) else { return "Set up your targets in Gym first." }
        let kcal = r.kcal >= 0 ? "\(number(r.kcal)) kcal left" : "\(number(-r.kcal)) kcal over"
        return "\(kcal) today: protein \(number(max(0, r.protein))) g, fat \(number(max(0, r.fat))) g, carbs \(number(max(0, r.carbs))) g to go."
    }
}

struct PhotoLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a meal with a photo"
    static let description = IntentDescription("Open Gym's camera to log what's on your plate.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        PendingAction.set("photo")
        return .result()
    }
}

struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a workout"
    static let description = IntentDescription("Open Gym on today's workout.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        PendingAction.set("train")
        return .result()
    }
}

struct GymShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogWaterIntent(), phrases: ["Log water in \(.applicationName)", "Add a glass of water in \(.applicationName)"],
                    shortTitle: "Log water", systemImageName: "drop.fill")
        AppShortcut(intent: CaloriesLeftIntent(), phrases: ["How many calories do I have left in \(.applicationName)",
                                                            "Calories left in \(.applicationName)"],
                    shortTitle: "Calories left", systemImageName: "flame")
        AppShortcut(intent: LogWeightIntent(), phrases: ["Log my weight in \(.applicationName)", "Weigh in with \(.applicationName)"],
                    shortTitle: "Log weight", systemImageName: "scalemass")
        AppShortcut(intent: QuickAddIntent(), phrases: ["Quick add calories in \(.applicationName)"],
                    shortTitle: "Quick add", systemImageName: "bolt.fill")
        AppShortcut(intent: PhotoLogIntent(), phrases: ["Log a meal photo in \(.applicationName)", "Snap my meal in \(.applicationName)"],
                    shortTitle: "Photo log", systemImageName: "camera.fill")
        AppShortcut(intent: StartWorkoutIntent(), phrases: ["Start a workout in \(.applicationName)", "Train with \(.applicationName)"],
                    shortTitle: "Start workout", systemImageName: "dumbbell.fill")
    }
}
