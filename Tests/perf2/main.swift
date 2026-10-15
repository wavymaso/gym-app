import Foundation
import SwiftData
let c = try! ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(url: URL(fileURLWithPath: CommandLine.arguments[1])))
let ctx = ModelContext(c)
func t(_ name: String, _ n: Int = 1, _ f: () -> Void) {
    let s = Date(); for _ in 0..<n { f() }
    print(name.padding(toLength: 28, withPad: " ", startingAt: 0), String(format: "%7.1f ms each", Date().timeIntervalSince(s) * 1000 / Double(n)))
}
t("weightValues", 5) { _ = ctx.weightValues }
let w = ctx.weightValues
t("trendSeries V1", 5) { _ = trendSeriesV1(w, through: dayKey()) }
t("trendSeries (default)", 5) { _ = trendSeries(w, through: dayKey()) }
t("dailyIntake", 5) { _ = ctx.dailyIntake() }
t("partialDays", 5) { _ = ctx.partialDays }
t("dayTargets x1", 20) { _ = ctx.dayTargets(on: dayKey()) }
t("dayTargets x7 (a week)", 5) { for i in 0..<7 { _ = ctx.dayTargets(on: addDays(dayKey(), -i)) } }
dataVersion += 1
t("expenditureEstimates cold", 1) { _ = ctx.expenditureEstimates() }
t("expenditureEstimates warm", 20) { _ = ctx.expenditureEstimates() }
t("entries(on:)", 20) { _ = ctx.entries(on: dayKey()) }
