import Foundation

// Phase 4: the AI coach's whole world. It receives this snapshot (JSON) and nothing else: no photos,
// no raw logs. It may only state numbers that appear here and cite registry entries listed here.

struct CoachSnapshot: Codable, Equatable {
    enum Moment: String, Codable, CaseIterable { case morning, nudge, postWorkout, checkIn, event }

    struct Today: Codable, Equatable {
        var kcalTarget: Int, kcalEaten: Int, kcalLeft: Int
        var proteinTarget: Int, proteinEaten: Int, proteinLeft: Int
        var mealsLeftToday: Int                    // typical meals still to come at this hour
        var special: [String] = []                 // "training day", "refeed day", "fasting day", "diet break"
    }
    struct Trend: Codable, Equatable { var kg: Double; var ratePerWeek: Double; var sd: Double; var goalRatePerWeek: Double }
    struct Expenditure: Codable, Equatable { var kcal: Int; var sd: Int; var settling: Bool }
    struct CheckIn: Codable, Equatable {
        var due: Bool
        var daysUntil: Int
        var lastAction: String?                    // applied | proposed | reported | no change
        var lastFrom: Int?, lastTo: Int?
        var lastReason: String?                    // the engine's own words
    }
    struct Workout: Codable, Equatable { var name: String; var sets: Int; var prs: Int; var volumeChangePct: Int? }
    struct EvidenceRef: Codable, Equatable { var id: String; var text: String; var grade: String }

    var moment: Moment
    var date: String
    var weekday: String
    var phase: String                              // cut, bulk, maintain, recomp
    var phaseWeek: Int
    var today: Today
    var trend: Trend
    var expenditure: Expenditure
    var loggedDaysLast7: Int
    var weighInsLast7: Int
    var checkIn: CheckIn
    var lastWorkout: Workout?
    var flags: [String] = []                       // engine flags, in its own words
    var waterEvent: String? = nil                  // recent: refeed, travel… the engine has accounted for it
    var frequentProteinFoods: [String] = []        // names from your own logs
    var safety: Safety = Safety()
    var evidence: [EvidenceRef] = []

    struct Safety: Codable, Equatable {
        var veryLowIntakeDays: Int = 0             // last 14 days with intake far below the floor
        var distressInNotes = false
        var stepBack: Bool { veryLowIntakeDays >= 4 || distressInNotes }
    }

    /// Every number the coach may state, at the precision it may state it.
    var allowedNumbers: [Double] {
        var n: [Double] = [7, 14]                  // days in a week, two weeks
        let t = today
        n += [t.kcalTarget, t.kcalEaten, abs(t.kcalLeft), t.proteinTarget, t.proteinEaten, abs(t.proteinLeft), t.mealsLeftToday].map(Double.init)
        n += [trend.kg, abs(trend.ratePerWeek), trend.sd, abs(trend.goalRatePerWeek)]
        n += [Double(expenditure.kcal), Double(expenditure.sd), Double(loggedDaysLast7), Double(weighInsLast7), Double(phaseWeek)]
        n += [Double(checkIn.daysUntil)] + [checkIn.lastFrom, checkIn.lastTo].compactMap { $0.map(Double.init) }
        if let f = checkIn.lastFrom, let to = checkIn.lastTo { n.append(Double(abs(to - f))) }
        if let w = lastWorkout { n += [Double(w.sets), Double(w.prs)] + (w.volumeChangePct.map { [Double(abs($0))] } ?? []) }
        // Numbers quoted inside the engine's own reasons and flags.
        for s in [checkIn.lastReason ?? ""] + flags + evidence.map(\.text) { n += CoachValidator.numbers(in: s) }
        return n
    }

    func json() -> String {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return String(decoding: (try? e.encode(self)) ?? Data(), as: UTF8.self)
    }
}

/// What the coach writes: structured, rendered by the app.
struct CoachMessage: Codable, Equatable {
    var headline: String
    var body: String
    var action: Action? = nil
    var evidence: [String] = []
    var source: String = "template"               // template | local | gemini

    struct Action: Codable, Equatable {
        enum Kind: String, Codable { case openCheckIn, openProposal, logFood, startWorkout, weighIn, none }
        var kind: Kind
        var label: String
    }
}
