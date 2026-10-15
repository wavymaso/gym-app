import Foundation

// The weekly check-in: from the engine's estimates and the week's data, decide whether targets change,
// by how much, and record everything that went into the decision so it can be explained and replayed.

enum ProgramStyle: String, Codable { case coached, collaborative, manual }

struct CheckInInput: Codable, Equatable {
    var day: String
    var phase: String
    var weeksInPhase: Int
    var targetRatePct: Double
    var trendKg: Double
    var trendSD: Double
    var observedRateKgWeek: Double
    var expenditure: Double
    var expenditureSD: Double
    var loggedDays: Int                // of the last 7
    var weighIns: Int                  // of the last 7
    var waterEventLast3Days: Bool
    var daysOfData: Int
    var avgIntake: Double?
    var currentTargets: MacroTargets
    var style: String
    var flags: [String] = []           // training and recovery signals
}

struct CheckInRecord: Codable, Equatable {
    var engineVersion = "2.0"
    var input: CheckInInput
    var raw: MacroTargets?             // what the numbers alone say
    var output: MacroTargets           // what the engine decides
    var action: String                 // applied | proposed | reported | no change
    var reasons: [EngineReason]
    var evidence: [String] { Array(Set(reasons.flatMap(\.evidence))).sorted() }
    var changed: Bool { output != input.currentTargets }
}

enum EngineCheckIn {
    static func decide(_ i: CheckInInput, person: Person, body: BodyComposition) -> CheckInRecord {
        var reasons: [EngineReason] = []
        let style = ProgramStyle(rawValue: i.style) ?? .coached
        let phase = Phase(rawValue: i.phase) ?? .maintain
        func keep(_ why: EngineReason) -> CheckInRecord {
            CheckInRecord(input: i, raw: nil, output: i.currentTargets, action: "no change", reasons: reasons + [why])
        }
        // Not enough data yet, or a week too patchy to trust.
        if i.daysOfData < Int(Evidence.value("checkin.minDays")) {
            return keep(.init(rule: "new user", detail: "Fewer than two weeks of data: targets stay on the formula estimate.", evidence: ["checkin.minDays"]))
        }
        if i.loggedDays < Int(Evidence.value("checkin.minLogged")) || i.weighIns < 3 || i.waterEventLast3Days {
            let why = i.loggedDays < 4 ? "only \(i.loggedDays) of 7 days logged" : i.weighIns < 3 ? "only \(i.weighIns) weigh-ins this week" : "a water event in the last three days"
            return keep(.init(rule: "low confidence", detail: "No change: \(why). Next week's check-in will use better data.", evidence: ["checkin.minLogged"]))
        }
        let r = EngineTargets.make(phase: phase, ratePercent: i.targetRatePct, expenditure: i.expenditure, weight: i.trendKg, body: body, person: person)
        reasons += r.reasons
        let raw = r.targets
        let d = raw.kcal - i.currentTargets.kcal
        // Deadband: within noise, nothing changes.
        let deadband = Evidence.value("checkin.deadband.kcal")
        if abs(d) <= deadband {
            return CheckInRecord(input: i, raw: raw, output: i.currentTargets, action: "no change",
                                 reasons: reasons + [.init(rule: "deadband", detail: "Within ±\(Int(deadband)) kcal of the current target: no change.", evidence: ["checkin.deadband.kcal"])])
        }
        // Step toward the raw target, more when the estimate is sure; capped; asymmetric on a bulk.
        let confidence = max(0, min(1, 1 - i.expenditureSD / 350))
        var step = d * (0.35 + 0.35 * confidence)
        let up = Evidence.value("checkin.cap.up.kcal")
        let down = phase == .bulk ? 75.0 : Evidence.value("checkin.cap.down.kcal")
        // A cut going faster than planned is corrected at full strength.
        let target = -i.targetRatePct / 100 * i.trendKg
        if phase == .cut, i.observedRateKgWeek < target - 0.25 * abs(target), d > 0 { step = d }
        let capped = max(-down, min(up, step))
        if capped != step { reasons.append(.init(rule: "weekly cap", detail: "Change limited to \(capped > 0 ? "+" : "")\(Int(capped)) kcal this week.", evidence: [d > 0 ? "checkin.cap.up.kcal" : "checkin.cap.down.kcal"])) }
        // Safety: eating far below the floor for the week → never cut further.
        var kcal = ((i.currentTargets.kcal + capped) / 10).rounded() * 10
        if let a = i.avgIntake, a < r.floor * 0.9, kcal < i.currentTargets.kcal {
            kcal = i.currentTargets.kcal
            reasons.append(.init(rule: "low intake", detail: "You've been eating well under the floor, so the engine won't lower targets.", evidence: [r.floorIsFallback ? "floor.fallback" : "floor.ea.kcalPerKgFFM"]))
        }
        kcal = max(kcal, r.floor)
        // Macros in the raw target's proportions at the new calories (protein held).
        let rest = max(0, kcal - raw.protein * 4)
        let fatShare = raw.fat * 9 / max(raw.fat * 9 + raw.carbs * 4, 1)
        let fatFloor = max(40, Evidence.value("fat.min.gPerKg") * i.trendKg)
        let fat = max(rest * fatShare / 9, min(fatFloor, rest / 9))
        let out = MacroTargets(kcal: kcal, protein: raw.protein, fat: fat.rounded(), carbs: max(0, (rest - fat * 9) / 4).rounded())
        let action = style == .coached ? "applied" : style == .collaborative ? "proposed" : "reported"
        return CheckInRecord(input: i, raw: raw, output: style == .manual ? i.currentTargets : out, action: action, reasons: reasons)
    }
}
