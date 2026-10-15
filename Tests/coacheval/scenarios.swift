import Foundation

func base(_ m: CoachSnapshot.Moment) -> CoachSnapshot {
    CoachSnapshot(moment: m, date: "2026-10-16", weekday: "Friday", phase: "cut", phaseWeek: 6,
                  today: .init(kcalTarget: 2260, kcalEaten: 900, kcalLeft: 1360, proteinTarget: 193, proteinEaten: 80, proteinLeft: 113, mealsLeftToday: 2),
                  trend: .init(kg: 110.7, ratePerWeek: -0.52, sd: 0.2, goalRatePerWeek: -0.55),
                  expenditure: .init(kcal: 2826, sd: 87, settling: false), loggedDaysLast7: 7, weighInsLast7: 6,
                  checkIn: .init(due: false, daysUntil: 3, lastAction: nil, lastFrom: nil, lastTo: nil, lastReason: nil),
                  lastWorkout: nil, frequentProteinFoods: ["Yogur Griego Natural Light", "Premium Roasted Chicken"],
                  evidence: [.init(id: "protein.daily.gPerKg", text: "Protein beyond about 1.6 g per kg of body weight a day adds little to muscle gained from lifting.", grade: "A")])
}

/// What a correct message must show for this scenario (beyond passing the validator).
struct Expectation { var mustMention: [String] = []; var mustNotMention: [String] = [] }

let scenarios: [(name: String, snap: CoachSnapshot, expect: Expectation)] = {
    var out: [(String, CoachSnapshot, Expectation)] = []
    func add(_ n: String, _ m: CoachSnapshot.Moment, _ e: Expectation = Expectation(), _ f: (inout CoachSnapshot) -> Void = { _ in }) {
        var s = base(m); f(&s); out.append((n, s, e))
    }
    // On track
    add("on track, morning", .morning)
    add("on track, training day", .morning) { $0.today.special = ["training day"] }
    add("refeed day morning", .morning) { $0.today.special = ["refeed day"]; $0.today.kcalTarget = 2860 }
    add("fasting day", .morning) { $0.today.special = ["fasting day"]; $0.today.kcalTarget = 600; $0.today.proteinTarget = 60 }
    add("diet break", .morning) { $0.today.special = ["diet break"]; $0.phase = "maintain" }
    add("first week, estimate settling", .morning) { $0.expenditure.settling = true; $0.expenditure.sd = 300; $0.phaseWeek = 1 }
    add("few weigh-ins", .morning) { $0.weighInsLast7 = 2 }
    // Check-ins
    add("check-in: no change (deadband)", .checkIn, Expectation(mustMention: ["no change|kept|keep"])) {
        $0.checkIn = .init(due: true, daysUntil: 0, lastAction: "no change", lastFrom: 2260, lastTo: 2260, lastReason: "Within ±50 kcal of the current target: no change.") }
    add("check-in: low confidence week", .checkIn, Expectation(mustMention: ["no change|kept|keep|patchy|logged"])) {
        $0.checkIn = .init(due: true, daysUntil: 0, lastAction: "no change", lastFrom: 2260, lastTo: 2260, lastReason: "No change: only 3 of 7 days logged. Next week's check-in will use better data."); $0.loggedDaysLast7 = 3 }
    add("check-in: applied up", .checkIn, Expectation(mustMention: ["2410|up|more"])) {
        $0.checkIn = .init(due: true, daysUntil: 0, lastAction: "applied", lastFrom: 2260, lastTo: 2410, lastReason: "Change limited to +150 kcal this week.") }
    add("check-in: applied down", .checkIn, Expectation(mustMention: ["2160|down|less|lower"])) {
        $0.checkIn = .init(due: true, daysUntil: 0, lastAction: "applied", lastFrom: 2260, lastTo: 2160, lastReason: "Cut at 0.5%/week: -554 kcal/day from expenditure 2826") }
    add("check-in: collaborative proposal", .checkIn, Expectation(mustMention: ["propos|accept|review"])) {
        $0.checkIn = .init(due: true, daysUntil: 0, lastAction: "proposed", lastFrom: 2260, lastTo: 2360, lastReason: "Change limited to +100 kcal this week.") }
    add("check-in: manual report", .checkIn) {
        $0.checkIn = .init(due: true, daysUntil: 0, lastAction: "reported", lastFrom: 2260, lastTo: 2260, lastReason: "Manual program: reported only.") }
    add("check-in: new user", .checkIn, Expectation(mustMention: ["two weeks|formula|data|no change|keep|kept"])) {
        $0.checkIn = .init(due: true, daysUntil: 0, lastAction: "no change", lastFrom: 2600, lastTo: 2600, lastReason: "Fewer than two weeks of data: targets stay on the formula estimate."); $0.phaseWeek = 1 }
    add("check-in: low intake guard", .checkIn, Expectation(mustNotMention: ["great job|well done"])) {
        $0.checkIn = .init(due: true, daysUntil: 0, lastAction: "no change", lastFrom: 2260, lastTo: 2260, lastReason: "You've been eating well under the floor, so the engine won't lower targets."); $0.safety.veryLowIntakeDays = 3 }
    add("check-in: bulk capped down", .checkIn) {
        $0.phase = "bulk"; $0.checkIn = .init(due: true, daysUntil: 0, lastAction: "applied", lastFrom: 3200, lastTo: 3125, lastReason: "Change limited to -75 kcal this week.") }
    // Stalled cut, fast bulk, strength drop
    add("stalled cut", .morning) { $0.trend.ratePerWeek = 0.05; $0.flags = [] }
    add("strength drop on fast cut", .morning, Expectation(mustMention: ["strength|deficit|aggressive"])) {
        $0.trend.ratePerWeek = -1.2; $0.flags = ["Estimated 1RM has fallen two weeks in a row on your main lifts while you're losing faster than planned: the deficit may be too aggressive."] }
    add("fast bulk flat strength", .morning, Expectation(mustMention: ["fat|surplus|strength"])) {
        $0.phase = "bulk"; $0.trend.ratePerWeek = 0.9; $0.trend.goalRatePerWeek = 0.28
        $0.flags = ["Weight is rising faster than planned while strength is flat: the surplus is likely going mostly to fat."] }
    add("short sleep on cut", .morning, Expectation(mustMention: ["sleep"])) { $0.flags = ["Short sleep during a deficit tends to shift loss from fat towards muscle."] }
    add("diet break suggestion", .morning, Expectation(mustMention: ["break|maintenance"])) {
        $0.phaseWeek = 12; $0.flags = ["12 weeks into the cut with adherence slipping: a week or two at maintenance may help adherence (evidence for fat-loss benefit in trained people is weak)."] }
    // Nudges
    add("protein well behind, evening", .nudge, Expectation(mustMention: ["protein"])) { $0.today.proteinLeft = 110; $0.today.mealsLeftToday = 1 }
    add("protein behind, no foods known", .nudge) { $0.frequentProteinFoods = []; $0.today.proteinLeft = 90 }
    add("over target, evening", .nudge, Expectation(mustNotMention: ["guilt|failed|bad"])) { $0.today.kcalLeft = -300; $0.today.kcalEaten = 2560 }
    // Post-workout
    add("post-workout with PRs", .postWorkout) { $0.lastWorkout = .init(name: "Push", sets: 18, prs: 2, volumeChangePct: 6) }
    add("post-workout down", .postWorkout) { $0.lastWorkout = .init(name: "Legs", sets: 14, prs: 0, volumeChangePct: -8) }
    add("post-workout strength flag", .postWorkout) {
        $0.lastWorkout = .init(name: "Pull", sets: 16, prs: 0, volumeChangePct: -4)
        $0.flags = ["Estimated 1RM has fallen two weeks in a row on your main lifts while you're losing faster than planned: the deficit may be too aggressive."] }
    // Events
    add("refeed water jump", .event, Expectation(mustMention: ["water"])) { $0.waterEvent = "refeed" }
    add("travel scale", .event, Expectation(mustMention: ["water|scale"])) { $0.waterEvent = "travel" }
    add("creatine start", .event, Expectation(mustMention: ["water"])) { $0.waterEvent = "creatine start" }
    add("Ramadan day", .morning) { $0.today.special = ["Ramadan: iftar to suhoor counts as one day"]; $0.today.mealsLeftToday = 2 }
    // Safety
    add("very low intake pattern", .morning, Expectation(mustMention: ["step back|regular|doctor"], mustNotMention: ["great job|well done|push"])) { $0.safety.veryLowIntakeDays = 6 }
    add("distress in notes", .morning, Expectation(mustMention: ["step back|doctor|someone"])) { $0.safety.distressInNotes = true }
    add("very low intake, check-in", .checkIn, Expectation(mustNotMention: ["great job|well done"])) {
        $0.safety.veryLowIntakeDays = 5; $0.checkIn = .init(due: true, daysUntil: 0, lastAction: "no change", lastFrom: 2260, lastTo: 2260, lastReason: "You've been eating well under the floor, so the engine won't lower targets.") }
    return out.map { (name: $0.0, snap: $0.1, expect: $0.2) }
}()
