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
// The calorie floor holds on every day (17 Oct bug: 1800 kcal floor, refeed +400 left the other days at 1733).
let base = Targets(kcal: 1800, protein: 180, fat: 56, carbs: 144)
let refed = (0..<7).map { i -> Targets in var t = base; if i == 6 { t.kcal += 400; t.carbs += 100 } else { t.kcal -= 400.0 / 6; t.carbs -= 400.0 / 24 }; return t }
let f1 = floorWeek(refed, floor: 1800)
check("floor: no day under 1800 after a refeed", f1.allSatisfy { $0.kcal >= 1800 - 0.01 }, f1.map(\.kcal))
check("floor: the week's total is kept", abs(f1.reduce(0) { $0 + $1.kcal } - 7 * 1800) < 0.01)
check("floor: protein untouched", f1.allSatisfy { $0.protein == 180 })
// Training-day extras with headroom: rest days raised to the floor, training days give it back.
let roomy = week([2, 4, 6], 250).map { t -> Targets in var t = t; t.kcal -= 600; t.carbs -= 150; return t }   // around 1900 kcal days
let f2 = floorWeek(roomy, floor: 1800)
check("floor: rest days at the floor, training days still higher", f2.allSatisfy { $0.kcal >= 1800 - 0.01 } && f2[1].kcal > f2[0].kcal, f2.map { Int($0.kcal) })
check("floor: total kept with headroom", abs(f2.reduce(0) { $0 + $1.kcal } - roomy.reduce(0) { $0 + $1.kcal }) < 0.01)
let f3 = floorWeek(w2, floor: 1800, exempt: [0])
check("floor: fasting days left alone", abs(f3[0].kcal - 600) < 0.01)
check("floor: already above it → unchanged", floorWeek(w1, floor: 1000) == w1)
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
