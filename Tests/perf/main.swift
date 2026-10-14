// Times the heavy calculations on a copy of a real store. Run: ./run.sh <path to default.store copy>
import Foundation
import SwiftData
setvbuf(stdout, nil, _IONBF, 0)
func time(_ name: String, _ n: Int = 5, _ f: () -> Any) {
    let t0 = Date(); var r: Any = 0
    for _ in 0..<n { r = f() }
    print(String(format: "%-28@ %7.1f ms", name as NSString, Date().timeIntervalSince(t0) * 1000 / Double(n)), type(of: r))
}
MainActor.assumeIsolated {
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    let c = try! ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(url: url))
    let ctx = c.mainContext
    print("entries", (try? ctx.fetchCount(FetchDescriptor<FoodEntry>())) ?? -1, "weights", (try? ctx.fetchCount(FetchDescriptor<WeightEntry>())) ?? -1)
    time("fetch all entries") { (try? ctx.fetch(FetchDescriptor<FoodEntry>()))?.count ?? 0 }
    time("dailyIntake") { ctx.dailyIntake().count }
    time("expenditureEstimates") { ctx.expenditureEstimates().count }
    time("trendSeries") { trendSeries(((try? ctx.fetch(FetchDescriptor<WeightEntry>())) ?? []).map { DayValue(day: $0.day, value: $0.kg) }, through: dayKey()).count }
    time("dueCheckIn") { ctx.dueCheckIn ?? "" }
}
