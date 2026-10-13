import SwiftData
import SwiftUI

@main
struct GymApp: App {
    let container: ModelContainer = {
        let schema = Schema(allModels)
        #if DEBUG
        // Testing only: -inMemory starts with no data (and saves nothing).
        let inMemory = UserDefaults.standard.bool(forKey: "inMemory")
        #else
        let inMemory = false
        #endif
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory))
    }()

    var body: some Scene {
        WindowGroup {
            Root()
                .environment(\.locale, appLocale)
                #if os(macOS)
                .frame(minWidth: 820, minHeight: 600)
                #endif
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif
    }
}

/// Setup on first launch, the app after that.
struct Root: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]

    var body: some View {
        Group {
            if profiles.isEmpty {
                SetupView()
            } else {
                MainView()
            }
        }
        .task {
            ctx.seedExercises()
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "demo") && profiles.isEmpty { addDemoProfile(ctx) }
            if let path = UserDefaults.standard.string(forKey: "snapshot") { await saveSnapshot(to: path) }   // -snapshot dashboard.png
            #endif
        }
    }
}

enum Page: String, CaseIterable, Identifiable {
    case dashboard, food, weight, insights, strategy, workouts, exercises, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .food: return "Food log"
        case .weight: return "Weight"
        case .strategy: return "Strategy"
        case .insights: return "Insights"
        case .workouts: return "Workouts"
        case .exercises: return "Exercises"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .food: return "fork.knife"
        case .weight: return "scalemass"
        case .strategy: return "target"
        case .insights: return "chart.line.uptrend.xyaxis"
        case .workouts: return "dumbbell"
        case .exercises: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        }
    }
}

/// Sidebar on the Mac, tabs on the iPhone.
struct MainView: View {
    @Environment(\.modelContext) private var ctx
    @State private var page: Page? = {
        #if DEBUG
        if let s = UserDefaults.standard.string(forKey: "page"), let v = Page(rawValue: s) { return v }   // -page strategy
        #endif
        return .dashboard
    }()

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(selection: $page) {
                Section("Nutrition") {
                    ForEach([Page.dashboard, .food, .weight, .insights, .strategy]) { row($0) }
                }
                Section("Training") {
                    ForEach([Page.workouts, .exercises]) { row($0) }
                }
                Section {
                    row(.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            NavigationStack { page(page ?? .dashboard) }
        }
        #else
        TabView(selection: Binding(get: { page ?? .dashboard }, set: { page = $0 })) {
            ForEach([Page.dashboard, .food, .strategy, .workouts, .settings]) { s in
                NavigationStack { page(s) }.tabItem { Label(s.label, systemImage: s.icon) }.tag(s)
            }
        }
        #endif
    }

    private func row(_ s: Page) -> some View { Label(s.label, systemImage: s.icon).tag(s) }

    @ViewBuilder private func page(_ s: Page) -> some View {
        switch s {
        case .dashboard: DashboardView()
        case .strategy: StrategyView()
        case .insights: InsightsView()
        case .settings: SettingsView()
        case .food: FoodLogView()
        case .weight: WeightView()
        case .workouts: WorkoutsView()
        case .exercises:
            #if DEBUG
            if let k = UserDefaults.standard.string(forKey: "exercise"), let e = ctx.exercise(k) { ExerciseDetail(exercise: e) } else { ExercisesView() }   // testing only
            #else
            ExercisesView()
            #endif
        }
    }
}

struct ComingSoon: View {
    let page: Page
    let phase: Int
    let text: String
    var body: some View {
        ContentUnavailableView {
            Label(page.label, systemImage: page.icon)
        } description: {
            Text(text + "\nComing in phase \(phase).")
        }
        .navigationTitle(page.label)
    }
}

#if DEBUG
/// Testing only: save a picture of the window, then quit (no screen-recording permission needed).
@MainActor func saveSnapshot(to path: String) async {
    try? await Task.sleep(nanoseconds: 2_500_000_000)
    #if os(macOS)
    let visible = NSApp.windows.filter(\.isVisible)
    guard let view = (visible.first(where: \.isSheet) ?? visible.first)?.contentView,
          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: rep)
    // Sandboxed: only the app's own temporary folder is writable (~/Library/Containers/com.wavymaso.gym/Data/tmp).
    let url = FileManager.default.temporaryDirectory.appendingPathComponent((path as NSString).lastPathComponent)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
    NSApp.terminate(nil)
    #endif
}

/// Testing only (-demo): a filled-in profile, so setup can be skipped.
func addDemoProfile(_ ctx: ModelContext) {
    let born = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2003, month: 5, day: 10))!
    ctx.insert(Profile(sex: .male, birthDate: born, heightCm: 180, activity: .moderate, weightUnit: .kg, energyUnit: .kcal))
    ctx.insert(WeightEntry(kg: 78.4))
    let exp = startingExpenditure(sex: .male, weightKg: 78.4, heightCm: 180, age: age(born: born), activity: .moderate)
    ctx.startProgram(goal: .lose, ratePercent: 0.5, diet: .balanced, protein: .high, weightKg: 78.4, expenditure: exp, sex: .male, reason: "setup")
    // A morning of food, so the log and dashboard have something to show.
    let oats = Food(key: "custom:demo-oats", name: "Copos de avena", brand: "Hacendado", source: "custom",
                    per100: Nutrients(kcal: 372, protein: 14, fat: 7, carbs: 59, fiber: 10), servings: [Serving(name: "1 bowl", grams: 60)])
    let yogurt = Food(key: "off:20416690", name: "Yogur Griego Natural Light", brand: "Milbona", source: "off",
                      per100: Nutrients(kcal: 59, protein: 6, fat: 2, carbs: 4), servings: [Serving(name: "1 pot", grams: 125)])
    let chicken = Food(key: "usda:demo-chicken", name: "Chicken breast, roasted", source: "usda",
                       per100: Nutrients(kcal: 165, protein: 31, fat: 3.6, carbs: 0))
    [oats, yogurt, chicken].forEach(ctx.insert)
    let cal = Calendar.current
    func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: Date())! }
    ctx.log(oats, amount: 1, unit: "1 bowl", day: dayKey(), time: at(8, 15))
    ctx.log(yogurt, amount: 1, unit: "1 pot", day: dayKey(), time: at(8, 20))
    ctx.log(chicken, amount: 180, unit: "g", day: dayKey(), time: at(14, 0))
    ctx.insert(FoodEntry(day: dayKey(), time: at(17, 30), name: "Café con leche", brand: nil, foodKey: nil, amount: 1, unit: "",
                         grams: 0, nutrients: Nutrients(kcal: 80, protein: 4, fat: 4, carbs: 6)))
    yogurt.isFavorite = true
    // Five weeks of history: really burns ~2950 (the formula said 2790), eats ~2450, so loses ~0,45 kg a week.
    let start = addDays(dayKey(), -35)
    ctx.activeProgram?.startDay = start
    for t in (try? ctx.fetch(FetchDescriptor<TargetSet>())) ?? [] { t.fromDay = start }
    var mass = 80.6, seed: UInt64 = 42
    func noise() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) - 0.5 }
    for i in 0..<35 {
        let day = addDays(start, i)
        let ate = 2450 + noise() * 700
        mass += (ate - 2950) / kcalPerKg
        if i % 9 != 4 {
            ctx.insert(FoodEntry(day: day, time: date(fromKey: day).addingTimeInterval(13 * 3600), name: "Day's food", brand: nil, foodKey: nil,
                                 amount: 1, unit: "", grams: 0, nutrients: Nutrients(kcal: ate, protein: 170, fat: 75, carbs: ate / 4 - 170 - 170)))
        }
        if i % 6 != 2 { ctx.logWeight(mass + noise() * 1.4, on: day) }
    }
    ctx.logWeight(mass - 0.2)
    // Training: Push / Pull / Legs, three times a week for four weeks, adding weight as it goes.
    ctx.seedExercises()
    let plan: [(String, [(String, Double, Int)])] = [
        ("Push", [("bench-press", 70, 8), ("overhead-press", 42.5, 8), ("lateral-raise", 10, 12), ("triceps-pushdown", 25, 12)]),
        ("Pull", [("deadlift", 110, 5), ("lat-pulldown", 55, 10), ("barbell-row", 60, 8), ("db-curl", 12, 10)]),
        ("Legs", [("squat", 90, 6), ("romanian-deadlift", 80, 8), ("leg-extension", 45, 12), ("standing-calf-raise", 60, 12)]),
    ]
    for (i, (name, items)) in plan.enumerated() {
        let r = Routine(name: name, order: i); ctx.insert(r)
        for (j, it) in items.enumerated() {
            ctx.insert(RoutineExercise(routineKey: r.key, exerciseKey: "builtin:\(it.0)", order: j, sets: 3, repLow: it.2, repHigh: it.2 + 2, restSeconds: j == 0 ? 180 : 90))
        }
    }
    for week in 0..<4 {
        for (i, (name, items)) in plan.enumerated() {
            let start = date(fromKey: addDays(dayKey(), -26 + week * 7 + i * 2)).addingTimeInterval(18 * 3600)
            let w = Workout(name: name, start: start); w.end = start.addingTimeInterval(3600 + Double(i) * 300); ctx.insert(w)
            for (j, it) in items.enumerated() {
                let kg = it.1 + Double(week) * (j == 0 ? 2.5 : 1.25)
                ctx.insert(WorkoutSet(workoutKey: w.key, exerciseKey: "builtin:\(it.0)", exerciseOrder: j, setOrder: 0, kind: .warmup,
                                      kg: (kg * 0.5).rounded(), reps: 10, day: w.day))
                for k in 1...3 {
                    let s = WorkoutSet(workoutKey: w.key, exerciseKey: "builtin:\(it.0)", exerciseOrder: j, setOrder: k, kg: kg,
                                       reps: it.2 - (k - 1) + (week % 2), day: w.day)
                    s.done = true; ctx.insert(s)
                }
                for s in ctx.sets(of: w.key) { s.done = true }
            }
        }
    }
    if UserDefaults.standard.bool(forKey: "activeWorkout") {
        let push = try? ctx.fetch(FetchDescriptor<Routine>(predicate: #Predicate { $0.name == "Push" })).first
        let w = ctx.startWorkout(routine: push)
        let first = ctx.sets(of: w.key).prefix(2)
        first.forEach { $0.done = true; $0.kg += 2.5 }
    }
    try? ctx.save()
}
#endif
