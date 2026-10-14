// Both expenditure engines on a copy of a real store: speed and recent values.  Run: ./run.sh <store copy>
import Foundation
import SwiftData
setvbuf(stdout, nil, _IONBF, 0)
MainActor.assumeIsolated {
    let c = try! ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(url: URL(fileURLWithPath: CommandLine.arguments[1])))
    let ctx = c.mainContext
    guard let s = ctx.expenditureStart else { print("no program"); return }
    let intake = ctx.dailyIntake(), weights = ctx.weightValues
    var t = Date()
    let v1 = expenditureSeries(start: s.day, end: dayKey(), initial: s.kcal, intake: intake, weights: weights)
    let t1 = Date().timeIntervalSince(t); t = Date()
    let v2 = jointExpenditure(start: s.day, end: dayKey(), initial: s.kcal, intake: intake, weights: weights)
    let t2 = Date().timeIntervalSince(t)
    print("start", s.day, "initial", Int(s.kcal), "days", v1.count, String(format: "  V1 %.0f ms  V2 %.0f ms", t1 * 1000, t2 * 1000))
    for k in stride(from: max(0, v1.count - 120), to: v1.count, by: 15) { print(v1[k].day, "V1", Int(v1[k].kcal), "V2", Int(v2[k].kcal)) }
    print("today", "V1", Int(v1.last!.kcal), "V2", Int(v2.last!.kcal))
}
