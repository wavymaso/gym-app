import Foundation

// Lifting maths. Plain Swift, so it can be tested alone.

enum Muscle: String, CaseIterable, Identifiable {
    case chest, back, shoulders, biceps, triceps, forearms, quads, hamstrings, glutes, calves, abs, fullBody, cardio
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fullBody: return "Full body"
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

enum Equipment: String, CaseIterable, Identifiable {
    case barbell, dumbbell, machine, cable, bodyweight, kettlebell, band, other
    var id: String { rawValue }
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

enum SetKind: String, CaseIterable {
    case warmup, normal, drop, failure
    var short: String { ["W", "", "D", "F"][Self.allCases.firstIndex(of: self)!] }
    var label: String { ["Warm-up", "Normal", "Drop set", "To failure"][Self.allCases.firstIndex(of: self)!] }
    var counts: Bool { self != .warmup }            // warm-ups don't count for progress or volume
}

/// One set as the maths sees it.
struct LiftSet: Equatable {
    var day: String
    var kg: Double
    var reps: Int
    var kind: SetKind = .normal
}

/// Estimated one-rep max (Epley). A single is itself; past 12 reps the estimate gets unreliable, so it's capped there.
func estimatedOneRepMax(kg: Double, reps: Int) -> Double {
    guard reps > 0, kg > 0 else { return 0 }
    if reps == 1 { return kg }
    return kg * (1 + Double(min(reps, 12)) / 30)
}

func volume(_ sets: [LiftSet]) -> Double { sets.filter { $0.kind.counts }.reduce(0) { $0 + $1.kg * Double($1.reps) } }

struct Records: Equatable {
    var bestOneRepMax: (value: Double, set: LiftSet)?
    var heaviest: LiftSet?
    var mostReps: LiftSet?
    var bestSetVolume: LiftSet?

    static func == (a: Records, b: Records) -> Bool {
        a.bestOneRepMax?.value == b.bestOneRepMax?.value && a.heaviest == b.heaviest && a.mostReps == b.mostReps && a.bestSetVolume == b.bestSetVolume
    }
}

/// Personal records over all working sets (warm-ups excluded).
func records(_ sets: [LiftSet]) -> Records {
    let working = sets.filter { $0.kind.counts && $0.reps > 0 }
    var r = Records()
    for s in working {
        let e = estimatedOneRepMax(kg: s.kg, reps: s.reps)
        if e > (r.bestOneRepMax?.value ?? 0) { r.bestOneRepMax = (e, s) }
        if s.kg > (r.heaviest?.kg ?? -1) || (s.kg == r.heaviest?.kg && s.reps > r.heaviest!.reps) { r.heaviest = s }
        if s.reps > (r.mostReps?.reps ?? 0) || (s.reps == r.mostReps?.reps && s.kg > r.mostReps!.kg) { r.mostReps = s }
        if s.kg * Double(s.reps) > (r.bestSetVolume.map { $0.kg * Double($0.reps) } ?? 0) { r.bestSetVolume = s }
    }
    return r
}

/// Which records a new set beats (compared with everything before it).
func newRecords(_ set: LiftSet, before history: [LiftSet]) -> [String] {
    guard set.kind.counts, set.reps > 0, set.kg > 0 else { return [] }
    let old = records(history)
    guard old.heaviest != nil else { return [] }           // first time doing it: nothing to beat
    var out: [String] = []
    if estimatedOneRepMax(kg: set.kg, reps: set.reps) > (old.bestOneRepMax?.value ?? 0) + 0.01 { out.append("Est. 1RM") }
    if set.kg > (old.heaviest?.kg ?? 0) { out.append("Heaviest") }
    if set.kg * Double(set.reps) > (old.bestSetVolume.map { $0.kg * Double($0.reps) } ?? 0) + 0.01 { out.append("Best set") }
    return out
}

/// Best estimated 1RM per day, for the progress chart.
func oneRepMaxByDay(_ sets: [LiftSet]) -> [DayValueLift] {
    var best: [String: Double] = [:]
    for s in sets where s.kind.counts { best[s.day] = max(best[s.day] ?? 0, estimatedOneRepMax(kg: s.kg, reps: s.reps)) }
    return best.map { DayValueLift(day: $0.key, value: $0.value) }.sorted { $0.day < $1.day }
}

struct DayValueLift: Equatable {
    var day: String
    var value: Double
}

/// Working sets per muscle: 1 for the main muscle, ½ for each helper muscle.
func setsPerMuscle(_ sets: [(primary: Muscle, secondary: [Muscle], kind: SetKind)]) -> [Muscle: Double] {
    var out: [Muscle: Double] = [:]
    for s in sets where s.kind.counts {
        out[s.primary, default: 0] += 1
        for m in s.secondary { out[m, default: 0] += 0.5 }
    }
    return out
}

/// "1:05:12" or "42:07".
func clock(_ seconds: Int) -> String {
    let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

// MARK: - Auto-progression (double progression)

/// What to aim for next time on one exercise, and why.
struct Progression: Equatable {
    var kg: Double
    var reps: [Int]               // per working set
    var reason: String
}

/// The smallest step that's easy to load for this kind of equipment.
func weightStep(_ e: Equipment) -> Double {
    switch e {
    case .barbell: return 2.5
    case .dumbbell, .kettlebell: return 2
    case .machine, .cable: return 2.5
    default: return 0
    }
}

/// Double progression from last time's working sets:
/// - every set reached the top of the range → add a step, back to the bottom of the range
/// - most sets fell 2+ reps short of the bottom → drop ~10% (a reset)
/// - otherwise → same weight, one more rep on the sets still below the top
func nextTarget(previous: [LiftSet], repLow: Int, repHigh: Int, step: Double) -> Progression? {
    let working = previous.filter { $0.kind.counts && $0.reps > 0 }
    guard let top = working.map(\.kg).max(), top > 0 || step == 0 else { return nil }
    let atTop = working.filter { $0.kg >= top - 0.001 }
    let lo = max(1, repLow), hi = max(lo, repHigh)
    if atTop.allSatisfy({ $0.reps >= hi }) && step > 0 {
        return Progression(kg: top + step, reps: Array(repeating: lo, count: atTop.count),
                           reason: "All sets hit \(hi) reps last time: up \(trimmed(step)) kg")
    }
    if Double(atTop.filter { $0.reps <= lo - 2 }.count) > Double(atTop.count) / 2, step > 0 {
        let reset = max(step, ((top * 0.9) / step).rounded(.down) * step)
        return Progression(kg: reset, reps: Array(repeating: lo, count: atTop.count),
                           reason: "Short of \(lo) reps on most sets: reset to \(trimmed(reset)) kg and build back up")
    }
    return Progression(kg: top, reps: atTop.map { min(hi, max(lo, $0.reps + 1)) },
                       reason: "Same weight, one more rep (aim for \(lo)–\(hi))")
}

/// Ramp-up sets before the first working set: empty bar, then about 50%, 70% and 85%, rounded to loadable weights.
func warmUps(working kg: Double, bar: Double = 20, step: Double = 2.5) -> [(kg: Double, reps: Int)] {
    guard kg > bar + step else { return kg > 0 ? [(max(bar, (kg * 0.5 / step).rounded() * step), 8)] : [] }
    var out: [(Double, Int)] = [(bar, 10)]
    for (f, r) in [(0.5, 5), (0.7, 3), (0.85, 1)] {
        let w = (kg * f / step).rounded() * step
        if w > (out.last?.0 ?? 0) + 0.001 && w < kg - 0.001 { out.append((w, r)) }
    }
    return out
}
