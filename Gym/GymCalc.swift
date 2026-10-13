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
