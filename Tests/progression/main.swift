// Double progression and warm-up ramps.
import Foundation
var fails = 0
func check(_ n: String, _ ok: Bool, _ got: Any = "") { print(ok ? "ok   \(n)" : "FAIL \(n) got \(got)"); if !ok { fails += 1 } }
func sets(_ kg: Double, _ reps: [Int]) -> [LiftSet] { reps.map { LiftSet(day: "2026-10-10", kg: kg, reps: $0) } }
let up = nextTarget(previous: sets(80, [10, 10, 10]), repLow: 8, repHigh: 10, step: 2.5)
check("all at top → +2,5 kg, back to 8", up?.kg == 82.5 && up?.reps == [8, 8, 8], up as Any)
let more = nextTarget(previous: sets(80, [10, 9, 8]), repLow: 8, repHigh: 10, step: 2.5)
check("not all at top → same weight, +1 rep (capped)", more?.kg == 80 && more?.reps == [10, 10, 9], more as Any)
let reset = nextTarget(previous: sets(100, [5, 6, 4]), repLow: 8, repHigh: 12, step: 2.5)
check("well short → reset ~10%", reset?.kg == 90 && reset?.reps == [8, 8, 8], reset as Any)
let warm = previous(with: [LiftSet(day: "", kg: 60, reps: 12, kind: .warmup)])
check("warm-ups ignored", warm == nil)
func previous(with s: [LiftSet]) -> Progression? { nextTarget(previous: s, repLow: 8, repHigh: 12, step: 2.5) }
let bw = nextTarget(previous: sets(0, [12, 12]), repLow: 8, repHigh: 12, step: 0)
check("bodyweight: reps only", bw?.kg == 0 && bw?.reps == [12, 12], bw as Any)
let w = warmUps(working: 100)
check("ramp 20×10, 50×5, 70×3, 85×1", w.map(\.kg) == [20, 50, 70, 85] && w.map(\.reps) == [10, 5, 3, 1], w.map(\.kg))
let light = warmUps(working: 30)
check("light weight: few warm-ups below it", light.allSatisfy { $0.kg < 30 } && !light.isEmpty, light.map(\.kg))
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
