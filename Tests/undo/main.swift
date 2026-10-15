import Foundation
import SwiftData
var fails = 0
func check(_ n: String, _ ok: Bool) { if !ok { fails += 1; print("FAIL", n) } }
let c = try! ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
let ctx = ModelContext(c)
func roundTrip<T: Syncable>(_ x: T, _ same: (T, T) -> Bool, _ name: String) {
    ctx.insert(x); ctx.commit()
    let d = x.encode(), id = x.syncID
    ctx.delete(x); ctx.commit()
    let n = T.blank(); n.decode(d); n.syncID = id; ctx.insert(n); ctx.commit()
    let back = (try? ctx.fetch(FetchDescriptor<T>()))?.first { $0.syncID == id }
    let ok = back.map { same(n, $0) } ?? false
    if !ok { print(name, "back:", back != nil, "orig:", d, "new:", back?.encode() ?? [:]) }
    check(name, ok)
}
let t = Date(timeIntervalSince1970: 1_760_000_000)
roundTrip(FoodEntry(day: "2026-10-15", time: t, name: "Oats", brand: "Hacendado", foodKey: "custom:oats", amount: 80, unit: "g", grams: 80,
                    nutrients: Nutrients(kcal: 300, protein: 10, fat: 5, carbs: 50, fiber: 8)),
          { $0.name == $1.name && $0.time == $1.time && $0.nutrients.kcal == 300 }, "food entry")
roundTrip(WeightEntry(day: "2026-10-15", kg: 110.8), { $0.kg == $1.kg && $0.day == $1.day }, "weigh-in")
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED")
