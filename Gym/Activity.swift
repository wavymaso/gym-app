import Foundation
import SwiftData
#if os(iOS)
import HealthKit
#endif

// Water you drink, and steps / active energy from Apple Health (read on the iPhone,
// synced to the Mac). Display only: your expenditure already comes from weight and intake.

@Model final class WaterEntry {
    var syncID: String = ""                   // the same on the Mac and the iPhone (Sync.swift)
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var day: String
    var time: Date
    var ml: Double

    init(day: String, time: Date = Date(), ml: Double) { self.day = day; self.time = time; self.ml = ml }
}

/// One day's steps and active energy, as Apple Health counted them.
@Model final class DailyActivity {
    var syncID: String = ""
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var day: String
    var steps: Int
    var activeKcal: Double
    var sleepHours: Double = 0                 // the night before this day, from Apple Health

    init(day: String, steps: Int, activeKcal: Double) { self.day = day; self.steps = steps; self.activeKcal = activeKcal }
}

extension WaterEntry: Syncable {
    static var syncType: String { "water" }
    func encode() -> [String: Any] { ["day": day, "time": time.timeIntervalSince1970, "ml": ml] }
    func decode(_ d: [String: Any]) {
        day = d["day"] as? String ?? ""
        time = Date(timeIntervalSince1970: (d["time"] as? Double) ?? 0)
        ml = (d["ml"] as? Double) ?? Double((d["ml"] as? Int) ?? 0)
    }
    static func blank() -> Self { Self(day: "", ml: 0) }
}

extension DailyActivity: Syncable {
    static var syncType: String { "activity" }
    var naturalID: String { "a:\(day)" }                     // one per day
    func encode() -> [String: Any] { ["day": day, "steps": steps, "activeKcal": activeKcal, "sleepHours": sleepHours] }
    func decode(_ d: [String: Any]) {
        day = d["day"] as? String ?? ""
        steps = (d["steps"] as? Int) ?? Int((d["steps"] as? Double) ?? 0)
        activeKcal = (d["activeKcal"] as? Double) ?? Double((d["activeKcal"] as? Int) ?? 0)
        sleepHours = (d["sleepHours"] as? Double) ?? 0
    }
    static func blank() -> Self { Self(day: "", steps: 0, activeKcal: 0) }
}

extension ModelContext {
    func water(on day: String) -> [WaterEntry] {
        (try? fetch(FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.day == day }, sortBy: [SortDescriptor(\.time)]))) ?? []
    }

    func addWater(_ ml: Double, on day: String = dayKey()) {
        insert(WaterEntry(day: day, time: day == dayKey() ? Date() : defaultTime(for: day), ml: ml))
        commit()
    }

    /// Take back the last glass of the day.
    func undoWater(on day: String = dayKey()) {
        if let last = water(on: day).last { delete(last); commit() }
    }

    func activity(on day: String) -> DailyActivity? {
        try? fetch(FetchDescriptor<DailyActivity>(predicate: #Predicate { $0.day == day })).first
    }

    /// Save a day's steps and active energy (only if they changed, so sync stays quiet).
    func setActivity(day: String, steps: Int, activeKcal: Double) {
        if let a = activity(on: day) {
            guard a.steps != steps || abs(a.activeKcal - activeKcal) >= 1 else { return }
            a.steps = steps; a.activeKcal = activeKcal
        } else {
            insert(DailyActivity(day: day, steps: steps, activeKcal: activeKcal))
        }
        commit()
    }

    /// The water goal: your own (Settings), or 35 ml per kg of your latest weigh-in, to the nearest 100 ml.
    var waterGoalMl: Double {
        let own = UserDefaults.standard.double(forKey: "waterGoalMl")
        if own > 0 { return own }
        let kg = (try? fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.day, order: .reverse)])).first?.kg) ?? 75
        return ((kg * 35) / 100).rounded() * 100
    }
}

var stepGoal: Int {
    let g = UserDefaults.standard.integer(forKey: "stepGoal")
    return g > 0 ? g : 10_000
}

/// "3,9 L" or "750 ml".
func litres(_ ml: Double) -> String { ml >= 1000 ? "\(number(ml / 1000, digits: ml.truncatingRemainder(dividingBy: 1000) == 0 ? 0 : 1)) L" : "\(number(ml)) ml" }

#if os(iOS)
/// Steps and active energy from Apple Health, for the last few days.
enum HealthActivity {
    static let store = HealthWeights.store
    static let types: Set<HKObjectType> = [HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKCategoryType(.sleepAnalysis), HKObjectType.workoutType()]

    static func requestAccess() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do { try await store.requestAuthorization(toShare: [], read: types); return true } catch { return false }
    }

    /// Today and the two days before (a late sync from a watch can change yesterday).
    @MainActor static func refresh(into ctx: ModelContext) async {
        guard UserDefaults.standard.bool(forKey: "healthSteps"), HKHealthStore.isHealthDataAvailable() else { return }
        if !UserDefaults.standard.bool(forKey: "healthSleepAsked") {      // sleep was added later: ask once
            UserDefaults.standard.set(true, forKey: "healthSleepAsked")
            _ = await requestAccess()
        }
        if !UserDefaults.standard.bool(forKey: "healthWorkoutsAsked") {   // workouts were added later: ask once
            UserDefaults.standard.set(true, forKey: "healthWorkoutsAsked")
            _ = await requestAccess()
        }
        if UserDefaults.standard.string(forKey: "healthWorkoutsDay") != dayKey() {
            UserDefaults.standard.set(dayKey(), forKey: "healthWorkoutsDay")
            await refreshWorkouts(into: ctx)
        }
        for back in 0..<3 {
            let day = addDays(dayKey(), -back)
            let start = date(fromKey: day), end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
            let steps = await sum(.stepCount, .count(), start, end)
            let kcal = await sum(.activeEnergyBurned, .kilocalorie(), start, end)
            if steps > 0 || kcal > 0 { ctx.setActivity(day: day, steps: Int(steps), activeKcal: kcal) }
            let sleep = await sleepHours(endingOn: start)
            if sleep > 0, let a = ctx.activity(on: day) ?? { ctx.setActivity(day: day, steps: 0, activeKcal: 0); return ctx.activity(on: day) }(),
               abs(a.sleepHours - sleep) >= 0.05 {
                a.sleepHours = sleep; ctx.commit()
            }
        }
    }

    /// Gym sessions from Apple Health in the last 6 weeks (first of each day), for the planner's usual
    /// training week. Walks and runs don't count.
    @MainActor private static func refreshWorkouts(into ctx: ModelContext) async {
        let from = Calendar.current.date(byAdding: .day, value: -43, to: Date())!
        let desc = HKSampleQueryDescriptor(predicates: [.workout(HKQuery.predicateForSamples(withStart: from, end: Date()))], sortDescriptors: [SortDescriptor(\.startDate)])
        let gym: Set<HKWorkoutActivityType> = [.traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining, .highIntensityIntervalTraining, .coreTraining, .mixedCardio]
        let cal = Calendar.current
        var out: [String: TrainingSlot] = [:]
        for w in (try? await desc.result(for: store)) ?? [] where gym.contains(w.workoutActivityType) && w.duration >= 15 * 60 {
            let d = dayKey(w.startDate)
            guard out[d] == nil else { continue }
            out[d] = TrainingSlot(start: cal.component(.hour, from: w.startDate) * 60 + cal.component(.minute, from: w.startDate), minutes: Int(w.duration / 60))
        }
        guard let p = ctx.profile, p.planner.healthSessions != out else { return }
        var s = p.planner; s.healthSessions = out; p.planner = s; ctx.commit()
        ctx.refreshTrainingWeek()
    }

    /// Hours asleep from 6 pm the evening before to noon (any stage of sleep, overlaps merged).
    private static func sleepHours(endingOn day: Date) async -> Double {
        let from = day.addingTimeInterval(-6 * 3600), to = day.addingTimeInterval(12 * 3600)
        let desc = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                                                        predicate: HKQuery.predicateForSamples(withStart: from, end: to))],
                                           sortDescriptors: [SortDescriptor(\.startDate)])
        let asleep = [HKCategoryValueSleepAnalysis.asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified].map(\.rawValue)
        let spans = ((try? await desc.result(for: store)) ?? []).filter { asleep.contains($0.value) }.map { ($0.startDate, $0.endDate) }
        var total = 0.0, end = Date.distantPast
        for (s, e) in spans where e > end { total += e.timeIntervalSince(max(s, end)); end = e }
        return total / 3600
    }

    private static func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ start: Date, _ end: Date) async -> Double {
        let type = HKQuantityType(id)
        let predicate = HKSamplePredicate.quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end))
        let query = HKStatisticsQueryDescriptor(predicate: predicate, options: .cumulativeSum)
        return (try? await query.result(for: store))?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }
}
#endif

import SwiftUI

/// Dashboard: water with quick adds, and steps from Apple Health.
struct ActivityCard: View {
    @Environment(\.modelContext) private var ctx
    @Query private var water: [WaterEntry]
    @Query private var activity: [DailyActivity]
    @AppStorage("healthSteps") private var stepsOn = false
    @State private var custom = false

    init() {
        let today = dayKey()
        _water = Query(filter: #Predicate<WaterEntry> { $0.day == today })
        _activity = Query(filter: #Predicate<DailyActivity> { $0.day == today })
    }

    var body: some View {
        let drunk = water.reduce(0) { $0 + $1.ml }, goal = ctx.waterGoalMl
        let waterColor = Color.waterTone
        Card(title: "Water & activity", systemImage: "drop.fill") {
            HStack(alignment: .top, spacing: Space.l) {
                VStack(spacing: Space.m) {
                    ZStack {
                        Ring(progress: goal > 0 ? drunk / goal : 0, color: waterColor, lineWidth: 9)
                        VStack(spacing: -1) {
                            Text(litres(drunk)).font(.numberSmall).monospacedDigit().minimumScaleFactor(0.7)
                            Text("of \(litres(goal))").font(.fine).foregroundStyle(.secondary)
                        }
                        .padding(Space.m)
                    }
                    .frame(width: 92, height: 92)
                    HStack(spacing: Space.s) {
                        waterButton(250, waterColor)
                        waterButton(500, waterColor)
                    }
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: Space.m) {
                    let a = activity.first
                    ZStack {
                        Ring(progress: Double(a?.steps ?? 0) / Double(stepGoal), color: palette.good, lineWidth: 9)
                        VStack(spacing: -1) {
                            Text(a.map { number(Double($0.steps)) } ?? "–").font(.numberSmall).monospacedDigit().minimumScaleFactor(0.7)
                            Text("steps").font(.fine).foregroundStyle(.secondary)
                        }
                        .padding(Space.m)
                    }
                    .frame(width: 92, height: 92)
                    if let a {
                        Text("\(number(a.activeKcal)) active kcal").font(.label).foregroundStyle(.secondary)
                    } else {
                        Text(isPhone ? (stepsOn ? "No steps yet" : "Turn on in Settings") : "From your iPhone")
                            .font(.note).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $custom) { WaterAmountSheet() }
        .sensoryFeedback(.impact(weight: .light), trigger: water.count) { old, new in new > old }
    }

    private func waterButton(_ ml: Double, _ color: Color) -> some View {
        Button { animate { ctx.addWater(ml) } } label: {
            Text("+\(number(ml))").font(.label).monospacedDigit()
                .padding(.horizontal, Space.s).padding(.vertical, Space.s)
                .background(color.opacity(0.16), in: Capsule()).foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Other amount…") { custom = true }
            Button("Undo last", role: .destructive) { ctx.undoWater() }.disabled(water.isEmpty)
        }
    }
}

/// Any amount of water.
struct WaterAmountSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var ml = 330.0

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: $ml, in: 50...2000, step: 50) {
                    Text("\(number(ml)) ml").font(.numberMedium).monospacedDigit()
                }
                HStack {
                    ForEach([150.0, 330, 750, 1000], id: \.self) { v in
                        Button(litres(v)) { ml = v }.buttonStyle(.bordered)
                    }
                }
            }
            .themedForm()
            .navigationTitle("Add water")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { ctx.addWater(ml); dismiss() } }
            }
        }
        .appStyle()
        #if os(macOS)
        .frame(width: 380, height: 240)
        #else
        .presentationDetents([.medium])
        #endif
    }
}

/// Settings: water and step goals, and steps from Apple Health on the iPhone.
struct ActivitySection: View {
    @Environment(\.modelContext) private var ctx
    @AppStorage("waterGoalMl") private var waterGoal: Double = 0
    @AppStorage("stepGoal") private var steps: Int = 10_000
    @AppStorage("healthSteps") private var stepsOn = false
    @State private var message: String?

    var body: some View {
        Section {
            Toggle("Automatic water goal", isOn: Binding(get: { waterGoal == 0 }, set: { waterGoal = $0 ? 0 : ctx.waterGoalMl }))
            if waterGoal > 0 {
                Stepper(value: $waterGoal, in: 1000...6000, step: 100) { LabeledContent("Water goal", value: litres(waterGoal)) }
            } else {
                LabeledContent("Water goal", value: litres(ctx.waterGoalMl))
            }
            Stepper(value: $steps, in: 2000...30000, step: 500) { LabeledContent("Step goal", value: number(Double(steps))) }
            #if os(iOS)
            Toggle("Steps & active energy from Apple Health", isOn: $stepsOn)
                .onChange(of: stepsOn) { _, v in
                    guard v else { return }
                    Task {
                        if await HealthActivity.requestAccess() {
                            await HealthActivity.refresh(into: ctx)
                            message = nil
                        } else {
                            message = "Health access wasn't allowed. You can change it in the Health app → Sharing → Apps."
                        }
                    }
                }
            if let message { Text(message).font(.secondaryText).foregroundStyle(.secondary) }
            #endif
        } header: {
            Text("Water & activity")
        } footer: {
            Text("The automatic water goal is 35 ml per kg of body weight. Steps are shown for motivation only; your expenditure already comes from your weight and what you eat.")
        }
    }
}
