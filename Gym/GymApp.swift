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
        #if DEBUG
        .task {
            if UserDefaults.standard.bool(forKey: "demo") && profiles.isEmpty { addDemoProfile(ctx) }
            if let path = UserDefaults.standard.string(forKey: "snapshot") { await saveSnapshot(to: path) }   // -snapshot dashboard.png
        }
        #endif
    }
}

enum Page: String, CaseIterable, Identifiable {
    case dashboard, food, weight, strategy, workouts, exercises, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .food: return "Food log"
        case .weight: return "Weight"
        case .strategy: return "Strategy"
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
        case .workouts: return "dumbbell"
        case .exercises: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        }
    }
}

/// Sidebar on the Mac, tabs on the iPhone.
struct MainView: View {
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
                    ForEach([Page.dashboard, .food, .weight, .strategy]) { row($0) }
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
        case .settings: SettingsView()
        case .food: ComingSoon(page: s, phase: 2, text: "Log what you eat on a timeline: search foods, scan barcodes, quick add, recipes.")
        case .weight: ComingSoon(page: s, phase: 3, text: "Log your weight and see your trend, with the daily swings smoothed out.")
        case .workouts: ComingSoon(page: s, phase: 5, text: "Routines, logging sets, rest timer and your progress on every lift.")
        case .exercises: ComingSoon(page: s, phase: 5, text: "The exercise library, grouped by muscle, plus your own exercises.")
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
    guard let view = NSApp.windows.first(where: { $0.isVisible })?.contentView,
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
}
#endif
