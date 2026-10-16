import Foundation

// Targets from the engine's estimates: calories for the phase (within safety limits), then protein,
// fat and carbs, each from the registry. Every limit that bites is reported.

enum Phase: String, CaseIterable, Codable {
    case cut, bulk, maintain, recomp
    var label: String { rawValue.capitalized }
    /// Default rate from the registry (% of body weight a week; 0 for maintain/recomp).
    var defaultRate: Double {
        switch self {
        case .cut: return Evidence.value("rate.cut.pctPerWeek")
        case .bulk: return Evidence.value("rate.bulk.pctPerWeek")
        case .maintain, .recomp: return 0
        }
    }
}

struct Person: Equatable {
    var male: Bool
    var heightCm: Double
    var age: Int
    var trainingYears: Double = 3
    var returningFromBreak = false
}

struct MacroTargets: Equatable, Codable {
    var kcal: Double, protein: Double, fat: Double, carbs: Double
}

struct TargetResult: Equatable {
    var targets: MacroTargets
    var floor: Double
    var floorIsFallback: Bool                  // no body fat known: asks for a tape measurement
    var reasons: [EngineReason]
    var perMealProtein: Double                 // g, soft guide
}

enum EngineTargets {
    static func mifflin(_ p: Person, weight: Double) -> Double {
        10 * weight + 6.25 * p.heightCm - 5 * Double(p.age) + (p.male ? 5 : -161)
    }

    /// The calorie floor: 30 kcal per kg of fat-free mass when body fat is known; otherwise the resting
    /// estimate, never below 1 500.
    static func floor(_ p: Person, weight: Double, body: BodyComposition) -> (kcal: Double, fallback: Bool) {
        if let bf = body.bodyFatPercent {
            return (Evidence.value("floor.ea.kcalPerKgFFM") * weight * (1 - bf / 100), false)
        }
        return (max(mifflin(p, weight: weight), Evidence.value("floor.fallback")), true)
    }

    static func make(phase: Phase, ratePercent: Double, expenditure: Double, weight: Double, body: BodyComposition,
                     person: Person, proteinPerKg: Double = 2.0, fatShare: Double = 0.3) -> TargetResult {
        var reasons: [EngineReason] = []
        let fm = body.fatMass(weight: weight), lean = body.leanMass(weight: weight)
        let rho = EngineEnergy.density(fatMass: fm)
        // Calories for the phase.
        let sign: Double = phase == .cut ? -1 : phase == .bulk ? 1 : 0
        var kcal = expenditure + sign * ratePercent / 100 * weight * rho / 7
        reasons.append(.init(rule: "phase", detail: "\(phase.label) at \(ratePercent)%/week: \(Int((kcal - expenditure).rounded())) kcal/day from expenditure \(Int(expenditure)) (\(Int(rho)) kcal/kg at \(Int(fm)) kg fat)",
                             evidence: ["rate.\(phase == .bulk ? "bulk" : "cut").pctPerWeek", "energy.fat.kcalPerKg", "energy.lean.kcalPerKg"]))
        let maxDef = expenditure * Evidence.value("limit.deficit.pctExpenditure") / 100
        let maxSur = expenditure * Evidence.value("limit.surplus.pctExpenditure") / 100
        if kcal < expenditure - maxDef { kcal = expenditure - maxDef; reasons.append(.init(rule: "max deficit", detail: "capped at a 25% deficit", evidence: ["limit.deficit.pctExpenditure"])) }
        if kcal > expenditure + maxSur { kcal = expenditure + maxSur; reasons.append(.init(rule: "max surplus", detail: "capped at a 15% surplus", evidence: ["limit.surplus.pctExpenditure"])) }
        let fl = floor(person, weight: weight, body: body)
        if kcal < fl.kcal {
            kcal = fl.kcal
            reasons.append(.init(rule: "calorie floor", detail: fl.fallback ? "held at the floor (resting estimate, at least 1 500): add a tape measurement for a personal floor"
                                                                              : "held at 30 kcal per kg of fat-free mass", evidence: [fl.fallback ? "floor.fallback" : "floor.ea.kcalPerKgFFM"]))
        }
        kcal = (kcal / 10).rounded() * 10

        // Protein: higher on a cut (per kg lean mass, clamped to body weight), otherwise 1.6–2.2 g/kg.
        var protein: Double
        if phase == .cut || phase == .recomp {               // recomp: the higher, cut-level protein
            protein = Evidence.value("protein.cut.gPerKgLean") * lean
            let lo = 1.5 * weight, hi = Evidence.value("protein.clamp.gPerKgBody") * weight
            if protein < lo || protein > hi { reasons.append(.init(rule: "protein clamp", detail: "kept within 1.5–2.6 g/kg body weight", evidence: ["protein.clamp.gPerKgBody"])) }
            protein = min(max(protein, lo), hi)
        } else {
            let r = Evidence.entry("protein.daily.gPerKg")!.range
            protein = min(max(proteinPerKg, r.lowerBound), r.upperBound) * weight
        }
        protein = min(protein.rounded(), (kcal * 0.4 / 4).rounded(.down))

        // Fat: phase share, never under the floor. Carbs: the rest, with a training minimum.
        let fatFloor = max(40, Evidence.value("fat.min.gPerKg") * weight)
        let share = phase == .cut ? Evidence.value("fat.cut.pctCalories") / 100 : fatShare
        var fat = max(kcal * share / 9, fatFloor)
        var carbs = (kcal - protein * 4 - fat * 9) / 4
        let carbMin = Evidence.value("carbs.min.gPerKg") * weight
        if carbs < carbMin, fat > fatFloor {
            let give = min(fat - fatFloor, (carbMin - carbs) * 4 / 9)
            fat -= give; carbs += give * 9 / 4
            reasons.append(.init(rule: "carb minimum", detail: "fat lowered towards its floor to keep carbs for training", evidence: ["carbs.min.gPerKg", "fat.min.gPerKg"]))
        }
        let t = MacroTargets(kcal: kcal, protein: protein, fat: fat.rounded(), carbs: max(0, carbs).rounded())
        return TargetResult(targets: t, floor: fl.kcal, floorIsFallback: fl.fallback, reasons: reasons,
                            perMealProtein: (Evidence.value("protein.perMeal.gPerKg") * weight).rounded())
    }

    /// Is a recomp sensible? Newer lifters, higher body fat, or a return from a break.
    static func recompAdvice(_ p: Person, body: BodyComposition) -> EngineReason {
        let bf = body.bodyFatPercent ?? body.assumedBodyFatPercent
        let higherFat = p.male ? bf >= 20 : bf >= 30
        let suitable = p.trainingYears < 1 || p.returningFromBreak || (higherFat && !body.isEstimated)
        return .init(rule: "recomp", detail: suitable
                     ? "A recomp is reasonable for you (\(p.trainingYears < 1 ? "newer lifter" : p.returningFromBreak ? "returning from a break" : "higher body fat"))."
                     : "A recomp works best for newer lifters, people with more body fat, or after a break; for you a cut or a slow bulk will usually progress faster.",
                     evidence: ["recomp.whenSuitable"])
    }

    /// When a phase ends: what comes next (a cut is followed by maintenance, not straight to a surplus).
    static func nextPhase(after p: Phase) -> (Phase, weeks: Int, why: String) {
        switch p {
        case .cut: return (.maintain, 4, "After a cut, a few weeks at maintenance before any surplus.")
        case .bulk: return (.maintain, 2, "A short maintenance before deciding on the next phase.")
        case .maintain, .recomp: return (.maintain, 0, "Carry on, or choose a cut or bulk.")
        }
    }
}
