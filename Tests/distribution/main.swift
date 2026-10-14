// The weekly calorie distribution keeps the week's total and puts the extra where it belongs.
import Foundation
var fails = 0
func check(_ n: String, _ ok: Bool, _ got: Any = "") { print(ok ? "ok   \(n)" : "FAIL \(n) got \(got)"); if !ok { fails += 1 } }
let t = Targets(kcal: 2500, protein: 180, fat: 70, carbs: 285)
func week(_ high: Set<Int>, _ extra: Double, _ fast: Set<Int> = [], _ fk: Double = 600) -> [Targets] { (1...7).map { distribute(t, weekday: $0, high: high, extra: extra, fast: fast, fastKcal: fk) } }
let w1 = week([2, 4, 6], 300)
check("no change without settings", distribute(t, weekday: 2, high: [], extra: 0) == t)
check("week total kept (training days)", abs(w1.reduce(0) { $0 + $1.kcal } - 7 * 2500) < 0.01, w1.reduce(0) { $0 + $1.kcal })
check("training day is 300 above rest days", abs(w1[1].kcal - w1[0].kcal - 300) < 0.01, (w1[1].kcal, w1[0].kcal))
check("protein the same every day", Set(w1.map(\.protein)) == [180])
check("difference is carbs", abs((w1[1].carbs - w1[0].carbs) * 4 - 300) < 0.01)
let w2 = week([2, 4], 200, [1], 600)
check("fasting day at 600", abs(w2[0].kcal - 600) < 0.01, w2[0].kcal)
check("week total kept (with a fast)", abs(w2.reduce(0) { $0 + $1.kcal } - 7 * 2500) < 0.01, w2.reduce(0) { $0 + $1.kcal })
check("fast day macros scaled", abs(w2[0].protein - 180 * 600 / 2500) < 0.01)
let w3 = week([2], 3000)
check("never negative", w3.allSatisfy { $0.carbs >= 0 && $0.fat >= 0 }, w3.map(\.carbs))
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
