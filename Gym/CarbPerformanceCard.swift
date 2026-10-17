import SwiftUI
import SwiftData

extension ModelContext {
    /// Each finished workout with the carbs eaten in the 4 h before and the previous day, and its lifts.
    func carbPerformanceSessions() -> [CarbPerformance.Session] {
        let ws = ((try? fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.start)]))) ?? []).filter { $0.end != nil }
        return ws.map { w in
            let from = w.start.addingTimeInterval(-4 * 3600), to = w.start
            let pre = ((try? fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.time >= from && $0.time < to }))) ?? []).reduce(0) { $0 + $1.nutrients.carbs }
            let prevDay = entries(on: addDays(w.day, -1)).reduce(0) { $0 + $1.nutrients.carbs }
            var lifts: [String: (e1rm: Double, volume: Double)] = [:]
            for s in sets(of: w.key) where s.done && s.kind == SetKind.normal.rawValue && s.kg > 0 && s.reps > 0 {
                let e = estimatedOneRepMax(kg: s.kg, reps: s.reps)
                let cur = lifts[s.exerciseKey] ?? (0, 0)
                lifts[s.exerciseKey] = (max(cur.e1rm, e), cur.volume + s.kg * Double(s.reps))
            }
            return .init(day: w.day, preCarbs: pre, previousDayCarbs: prevDay, lifts: lifts)
        }
    }
}

/// Insights: carbs before training and how the session went (from 20 sessions; your own data, not proof).
struct CarbPerformanceCard: View {
    @Environment(\.modelContext) private var ctx
    @State private var insight: CarbPerformance.Insight?
    @State private var count = 0

    var body: some View {
        Card(title: "Carbs and your sessions", systemImage: "bolt.heart") {
            if let i = insight {
                Text(i.text).font(.secondaryText).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("After \(CarbPerformance.minimumSessions) logged sessions (you have \(count)), this compares how your key lifts went with the carbs you ate in the 4 hours before and the day before. It's your own data, not proof.")
                    .font(.secondaryText).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: dataVersion) {
            let s = ctx.carbPerformanceSessions()
            count = CarbPerformance.scores(s).count
            insight = CarbPerformance.analyse(s)
        }
    }
}
