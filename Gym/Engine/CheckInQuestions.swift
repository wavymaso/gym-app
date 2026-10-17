import Foundation

// The weekly check-in questions (under 30 seconds): hunger, energy, sleep quality, training quality,
// stress and how hard the plan was to follow, each 1–5, plus an optional note. They never change targets
// by themselves: the rules below only make proposals you accept or decline. Each rule is in the evidence
// registry (checkin.q.*), graded honestly (mostly D: the thresholds are conventions, not tested).

struct CheckInAnswers: Codable, Equatable {
    var day: String
    var hunger = 3            // 1 not hungry … 5 very hungry
    var energy = 3            // 1 drained … 5 great
    var sleep = 3             // 1 poor … 5 great
    var training = 3          // 1 poor sessions … 5 great
    var stress = 3            // 1 calm … 5 very stressed
    var difficulty = 3        // how hard the plan was to follow: 1 easy … 5 very hard
    var hungriest: MealBand? = nil      // asked only when hunger is high
    var note = ""
    var decisions: [String: Bool] = [:] // proposal id → accepted (true) or declined (false)

    init(day: String) { self.day = day }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? c.decode(String.self, forKey: .day)) ?? ""
        func int(_ k: CodingKeys) -> Int { min(5, max(1, (try? c.decodeIfPresent(Int.self, forKey: k)) ?? 3)) }
        hunger = int(.hunger); energy = int(.energy); sleep = int(.sleep); training = int(.training); stress = int(.stress); difficulty = int(.difficulty)
        hungriest = try? c.decodeIfPresent(MealBand.self, forKey: .hungriest)
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        decisions = (try? c.decodeIfPresent([String: Bool].self, forKey: .decisions)) ?? [:]
    }
}

struct CheckInProposal: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case moveCalories, highVolume, carbsToTraining, dietBreak, maintenance }
    var kind: Kind
    var title: String
    var detail: String
    var evidence: [String]
    var id: String { kind.rawValue }
}

enum CheckInQuestions {
    static let questions: [(key: String, label: String, low: String, high: String)] = [
        ("hunger", "Hunger", "not hungry", "very hungry"),
        ("energy", "Energy", "drained", "great"),
        ("sleep", "Sleep quality", "poor", "great"),
        ("training", "Training quality", "poor", "great"),
        ("stress", "Stress", "calm", "very stressed"),
        ("difficulty", "Plan hard to follow", "easy", "very hard"),
    ]

    /// Proposals from this week's answers and the weeks before (`history`: earlier check-ins, oldest first).
    /// `adherence`: the share of planned meals eaten as planned this week (nil: no plan tracked).
    /// `carbShiftOn`: carbs already shifted to training days. `onCut`: in a fat-loss phase.
    static func proposals(_ a: CheckInAnswers, history: [CheckInAnswers], onCut: Bool, carbShiftOn: Bool, adherence: Double?, inBreak: Bool) -> [CheckInProposal] {
        var out: [CheckInProposal] = []
        let hungry = a.hunger >= Int(Evidence.value("checkin.q.hunger.high"))
        // Hard to follow: you said so, or under 60% of planned meals were eaten as planned.
        func struggling(_ x: CheckInAnswers, _ adh: Double?) -> Bool { x.difficulty >= 4 || (adh.map { $0 < 0.6 } ?? false) }
        // High hunger and a hard plan for 2+ weeks in a row (this week and the one before): a break.
        let weeks = Int(Evidence.value("checkin.q.dietBreak"))
        let recent = [a] + history.reversed().prefix(weeks - 1)
        if onCut, !inBreak, recent.count >= weeks, recent.allSatisfy({ $0.hunger >= 4 }), struggling(a, adherence), recent.dropFirst().allSatisfy({ struggling($0, nil) }) {
            out.append(.init(kind: .dietBreak, title: "Take a diet break",
                             detail: "Hunger has been high and the plan hard to follow for \(weeks) weeks in a row. A 1–2 week break at maintenance calories, then back to the cut. Breaks help adherence and hunger; they aren't a fat-loss trick.",
                             evidence: ["checkin.q.dietBreak", "dietBreak.benefit"]))
            out.append(.init(kind: .maintenance, title: "Or switch to a maintenance phase",
                             detail: "If the cut has run long, a maintenance phase for a few weeks before the next one.",
                             evidence: ["checkin.q.dietBreak"]))
        } else if hungry {
            if let band = a.hungriest {
                out.append(.init(kind: .moveCalories, title: "More of the day's calories at \(band.label.lowercased())",
                                 detail: "You're hungriest at \(band.label.lowercased()): the plan puts a bigger share of the same daily calories there (the day's total doesn't change).",
                                 evidence: ["checkin.q.hungerTiming"]))
            }
            out.append(.init(kind: .highVolume, title: "More high-volume foods",
                             detail: "Bigger portions of vegetables and fruit in the plan (low calories per gram), so meals are more filling for the same calories.",
                             evidence: ["checkin.q.highVolume"]))
        }
        // Training suffering on a cut: more of the week's carbs on training days (same weekly calories).
        if onCut, !carbShiftOn, a.training <= Int(Evidence.value("checkin.q.training.low")) {
            out.append(.init(kind: .carbsToTraining, title: "Shift carbs to training days",
                             detail: "Training quality was low. Training days get more of the week's carbs (fat toward its floor), rest days a little less; the week's calories are the same. The effect is modest outside long, high-volume sessions.",
                             evidence: ["checkin.q.trainingCarbs", "carbs.performance.nuance"]))
        }
        return out
    }
}
