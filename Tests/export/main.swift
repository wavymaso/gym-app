// CSV export from a copy of a real store: one row per record, Spanish number format.
import Foundation
import SwiftData
setvbuf(stdout, nil, _IONBF, 0)
var fails = 0
func check(_ n: String, _ ok: Bool, _ got: Any = "") { print(ok ? "ok   \(n)" : "FAIL \(n) got \(got)"); if !ok { fails += 1 } }
MainActor.assumeIsolated {
    let c = try! ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(url: URL(fileURLWithPath: CommandLine.arguments[1])))
    let ctx = c.mainContext
    let food = Export.food.csv(ctx).split(separator: "\r\n")
    let entries = (try? ctx.fetchCount(FetchDescriptor<FoodEntry>())) ?? -1
    check("food rows = entries + header", food.count == entries + 1, (food.count, entries))
    print("  ", food.first ?? "", "\n  ", food.dropFirst().first ?? "")
    let w = Export.weights.csv(ctx).split(separator: "\r\n")
    check("weights rows", w.count == ((try? ctx.fetchCount(FetchDescriptor<WeightEntry>())) ?? -1) + 1, w.count)
    check("decimal commas, semicolons", food.dropFirst().first?.contains(";") == true && w.dropFirst().first?.contains(",") == true)
    _ = Export.workouts.csv(ctx); _ = Export.water.csv(ctx)
}
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
