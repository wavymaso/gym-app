import SwiftData
import SwiftUI

@main
struct GymApp: App {
    let container = Store.container                  // shared with Siri and Shortcuts (Intents.swift)

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
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

/// Applies the chosen theme; changing it redraws everything in the new colours.
struct ThemedRoot: View {
    @AppStorage("theme") private var theme: AppTheme = .midnight
    @AppStorage("styleLevel") private var style: StyleLevel = .standard
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let p = theme.palette(systemDark: systemScheme == .dark)
        palette = p
        return Root()
            .background { if p.glass { GlassBackdrop() } }
            .id(p.name + style.rawValue)
            .environment(\.locale, appLocale)
            .tint(p.accent)
            .preferredColorScheme(theme.scheme)
    }
}

/// Setup on first launch, the app after that.
struct Root: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var phase
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
            #if os(macOS)
            SyncServer.shared.context = ctx
            if SyncServer.shared.enabled { SyncServer.shared.start() }
            #else
            SyncClient.shared.context = ctx
            #endif
            ctx.seedExercises()
            #if os(iOS)
            if UserDefaults.standard.bool(forKey: "healthWeights") { _ = await HealthWeights.importNew(into: ctx) }
            #endif
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "demo") && profiles.isEmpty { addDemoProfile(ctx) }
            if let path = UserDefaults.standard.string(forKey: "snapshot") { await saveSnapshot(to: path) }   // -snapshot dashboard.png
            #endif
        }
        .onChange(of: phase, initial: true) { _, p in
            if p != .active, ctx.hasChanges { ctx.commit() }       // nothing typed is lost when the app goes away
            if p == .background || p == .inactive {
                Backup.daily(ctx)
                Task { await Reminders.reschedule(ctx) }
                WidgetData.write(ctx)
            }
            #if os(iOS)
            if p == .active {
                SyncClient.shared.context = ctx; SyncClient.shared.start()
                Task { await HealthActivity.refresh(into: ctx) }
            } else if p == .background { SyncClient.shared.pause() }
            #endif
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: .gymDidCommit)) { _ in
            SyncClient.shared.changed()
            WidgetData.changed(ctx)
        }
        #else
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            if ctx.hasChanges { ctx.commit() }
        }
        #endif
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

    @State private var quick: QuickSheet?
    #if os(iOS)
    @ObservedObject private var selection = FoodSelection.shared
    #endif
    @State private var plus = false
    @State private var weighing = false
    @AppStorage("whatsNewSeen") private var whatsNewSeen = 0
    @State private var whatsNew = false
    #if os(iOS)
    @State private var tab: PhoneTab = .dashboard
    @State private var morePath: [Page] = []
    #endif

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
            .safeAreaInset(edge: .bottom) { SidebarToday() }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            NavigationStack { page(page ?? .dashboard) }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { plus = true } label: { Label("Add", systemImage: "plus.circle.fill") }
                            .keyboardShortcut("k", modifiers: .command).help("Quick add (⌘K)")
                    }
                }
        }
        .environment(\.openPage, { page = $0 })
        .sheet(isPresented: $plus) { ShortcutsSheet(choose: { quick = $0 }, train: { page = .workouts }) }
        .sheet(item: $quick) { quickSheet($0) }
        .sheet(isPresented: $weighing) { WeighInSheet() }
        .sheet(isPresented: $whatsNew) { WhatsNewSheet() }
        .background {
            // Keyboard: ⌘1–⌘8 for the pages, ⌘⇧W to weigh in.
            ForEach(Array([Page.dashboard, .food, .weight, .insights, .strategy, .workouts, .exercises, .settings].enumerated()), id: \.offset) { i, p in
                Button("") { page = p }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command).opacity(0)
            }
            Button("") { weighing = true }.keyboardShortcut("w", modifiers: [.command, .shift]).opacity(0)
        }
        .onAppear { showWhatsNew(); handlePending() }
        .onReceive(NotificationCenter.default.publisher(for: .gymOpenAction)) { _ in handlePending() }
        #else
        TabView(selection: $tab) {
            NavigationStack { page(.dashboard) }.tag(PhoneTab.dashboard).toolbar(.hidden, for: .tabBar)
            NavigationStack { page(.food) }.tag(PhoneTab.food).toolbar(.hidden, for: .tabBar)
            NavigationStack { page(.strategy) }.tag(PhoneTab.strategy).toolbar(.hidden, for: .tabBar)
            NavigationStack { page(.workouts) }.tag(PhoneTab.training).toolbar(.hidden, for: .tabBar)
            NavigationStack(path: $morePath) {
                MorePage(path: $morePath).navigationDestination(for: Page.self) { page($0) }
            }
            .tag(PhoneTab.more).toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if tab == .food && !selection.ids.isEmpty {
                    SelectionBar()
                } else if tab == .dashboard || tab == .food || tab == .strategy {
                    FoodSearchBar(search: { quick = .food }, scan: { quick = .scan })
                }
                PhoneTabBar(tab: $tab) { plus = true }
            }
        }
        .environment(\.openPage, { open($0) })
        .sheet(isPresented: $plus) { ShortcutsSheet(choose: { quick = $0 }, train: { tab = .training }) }
        .sheet(item: $quick) { quickSheet($0) }
        .sheet(isPresented: $whatsNew) { WhatsNewSheet() }
        .onReceive(NotificationCenter.default.publisher(for: .gymOpenAction)) { _ in handlePending() }
        .onAppear {
            if let p = page, p != .dashboard { open(p) }
            showWhatsNew()
            handlePending()
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "plus") { plus = true }      // testing only
            if let q = UserDefaults.standard.string(forKey: "quick") { quick = QuickSheet(rawValue: q) }   // -quick photo
            #endif
        }
        #endif
    }

    /// Siri or a shortcut asked for something that needs the app open.
    private func handlePending() {
        switch PendingAction.take() {
        case "photo": quick = .photo
        case "train":
            #if os(iOS)
            tab = .training
            #else
            page = .workouts
            #endif
        default: break
        }
    }

    /// Once per update (not in testing runs).
    private func showWhatsNew() {
        guard whatsNewSeen < WhatsNewSheet.version, !UserDefaults.standard.bool(forKey: "inMemory") else { return }
        whatsNewSeen = WhatsNewSheet.version
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { whatsNew = true }
    }

    #if os(iOS)
    /// Go to a page: one of the tabs, or into More.
    private func open(_ p: Page) {
        switch p {
        case .dashboard: tab = .dashboard
        case .food: tab = .food
        case .workouts: tab = .training
        case .strategy: tab = .strategy
        case .settings: tab = .more; morePath = []
        default: tab = .more; morePath = [p]
        }
    }
    #endif

    private func row(_ s: Page) -> some View {
        Label { Text(s.label).font(.body.weight(.medium)) } icon: { PageIcon(page: s, size: 24) }.tag(s)
    }

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
    #if os(macOS)
    if UserDefaults.standard.bool(forKey: "tall"), let w = NSApp.windows.first(where: \.isVisible) {      // -tall YES: see more of long pages
        w.setFrame(NSRect(x: 0, y: 0, width: w.frame.width, height: 2600), display: true)
    }
    #endif
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
    let profile = Profile(sex: .male, birthDate: born, heightCm: 180, activity: .moderate, weightUnit: .kg, energyUnit: .kcal)
    profile.goalWeightKg = 75
    profile.highDays = "2,4,6"; profile.highDayExtra = 300          // Push / Pull / Legs days get more
    ctx.insert(profile)
    ctx.insert(WeightEntry(kg: 78.4))
    let exp = startingExpenditure(sex: .male, weightKg: 78.4, heightCm: 180, age: age(born: born), activity: .moderate)
    ctx.startProgram(goal: .lose, ratePercent: 0.5, diet: .balanced, protein: .high, weightKg: 78.4, expenditure: exp, sex: .male, reason: "setup")
    // A morning of food, so the log and dashboard have something to show.
    let oats = Food(key: "custom:demo-oats", name: "Copos de avena", brand: "Hacendado", source: "custom",
                    per100: Nutrients(kcal: 372, protein: 14, fat: 7, carbs: 59, fiber: 10,
                                                      micros: ["iron": 4.3, "magnesium": 138, "zinc": 3.6, "potassium": 362]),
                    servings: [Serving(name: "1 bowl", grams: 60)])
    let yogurt = Food(key: "off:20416690", name: "Yogur Griego Natural Light", brand: "Milbona", source: "off",
                      per100: Nutrients(kcal: 59, protein: 6, fat: 2, carbs: 4), servings: [Serving(name: "1 pot", grams: 125)])
    let chicken = Food(key: "usda:demo-chicken", name: "Chicken breast, roasted", source: "usda",
                       per100: Nutrients(kcal: 165, protein: 31, fat: 3.6, carbs: 0, satFat: 1, sodium: 74,
                                                  micros: ["potassium": 256, "b12": 0.34, "zinc": 1, "iron": 1, "cholesterol": 85]))
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
        ctx.supersetWithNext(order: 2, in: w)                    // lateral raises + triceps pushdowns
    }
    // Supplements, with a streak
    for (i, x) in supplementSuggestions.prefix(3).enumerated() {
        let s = Supplement(name: x.0, dose: x.1, emoji: x.2, timing: x.3, order: i); ctx.insert(s)
        for d in 0..<(i == 0 ? 12 : 3) where !(i == 1 && d == 0) { ctx.insert(SupplementTake(day: addDays(dayKey(), -d), supplementKey: s.key)) }
    }
    // Tape measurements: 6 weeks ago and this week
    ctx.saveMeasurements([.waist: 86.5, .chest: 101, .neck: 38.5, .armR: 36, .thighR: 58], day: addDays(dayKey(), -42))
    ctx.saveMeasurements([.waist: 83.8, .chest: 101.5, .neck: 38.2, .armR: 36.6, .thighR: 58.4], day: addDays(dayKey(), -2))
    ctx.commit()
}
#endif
