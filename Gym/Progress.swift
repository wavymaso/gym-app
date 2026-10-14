import Foundation
import SwiftData

// Your logged data, shaped for the trend and expenditure maths (Trend.swift).

extension ModelContext {
    var weightValues: [DayValue] {
        ((try? fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.day)]))) ?? []).map { DayValue(day: $0.day, value: $0.kg) }
    }

    /// kcal per finished day (before today), for days with anything logged. Days with nothing
    /// logged are left out, not counted as zero, and today is left out because it isn't over yet.
    func dailyIntake() -> [String: Double] {
        let today = dayKey()
        let partial = partialDays                               // marked "partially logged": treated as not logged
        var out: [String: Double] = [:]
        for e in (try? fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.day < today }))) ?? [] where !partial.contains(e.day) {
            out[e.day, default: 0] += e.nutrients.kcal
        }
        return out
    }

    /// When the app started estimating, and from what: your first program and the setup estimate,
    /// unless you set your own start date or starting estimate (Settings → Expenditure).
    var expenditureStart: (day: String, kcal: Double)? {
        guard let first = try? fetch(FetchDescriptor<Program>(sortBy: [SortDescriptor(\.startDay)])).first else { return nil }
        let p = try? fetch(FetchDescriptor<Profile>()).first
        let day = (p?.expStartDay).flatMap { $0.isEmpty ? nil : $0 } ?? first.startDay
        if let manual = p?.expManualKcal, manual > 0 { return (day, manual) }
        if day != first.startDay, let p {
            // A later start: the formula again, at the weight you were then.
            let w = weightValues.last { $0.day <= day }?.value ?? weightValues.first?.value ?? first.startWeightKg
            let bf = ((try? fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.day, order: .reverse)]))) ?? []).compactMap(\.bodyFatPercent).first
            return (day, startingExpenditure(sex: p.sexValue, weightKg: w, heightCm: p.heightCm, age: age(born: p.birthDate),
                                             activity: p.activityValue, equation: BMREquation(rawValue: p.bmrEquation) ?? .mifflin, bodyFat: bf))
        }
        return (day, first.startExpenditure)
    }

    /// The expenditure modifiers: day-by-day nudges for changing step counts and goal changes.
    func expenditureNudges(from start: String, to end: String) -> [String: Double] {
        guard let p = try? fetch(FetchDescriptor<Profile>()).first, p.stepInformed || p.predictiveGoal else { return [:] }
        var out: [String: Double] = [:]
        if p.stepInformed {
            // Half the energy of a change in your 7-day step average, straight away (the data confirms the rest).
            let acts = (try? fetch(FetchDescriptor<DailyActivity>(predicate: #Predicate { $0.day >= start }))) ?? []
            let steps = Dictionary(acts.map { ($0.day, Double($0.steps)) }, uniquingKeysWith: { a, _ in a })
            let kg = weightValues.last?.value ?? 75
            let perStep = 0.0005 * kg                               // ≈ 0,04 kcal a step at 80 kg
            func avg7(_ d: String) -> Double? {
                let v = (0..<7).compactMap { steps[addDays(d, -$0)] }
                return v.count >= 5 ? v.reduce(0, +) / Double(v.count) : nil
            }
            for d in days(from: start, through: end) {
                if let a = avg7(d), let b = avg7(addDays(d, -1)) { out[d, default: 0] += 0.5 * (a - b) * perStep }
            }
        }
        if p.predictiveGoal {
            // When your intake target changes, about a fifth of the change shows up in expenditure
            // over the next two weeks (more food, more movement and digestion; less, the reverse).
            let sets = (try? fetch(FetchDescriptor<TargetSet>(sortBy: [SortDescriptor(\.fromDay)]))) ?? []
            for (prev, next) in zip(sets, sets.dropFirst()) where next.reason == "goal" && next.fromDay >= start {          // goal changes only (not check-ins or imports)
                let delta = (next.kcal - prev.kcal) * 0.2
                for k in 0..<14 { out[addDays(next.fromDay, k), default: 0] += delta / 14 }
            }
        }
        return out
    }

    /// Daily expenditure estimates from the start through `day`.
    func expenditureEstimates(through day: String = dayKey()) -> [ExpenditurePoint] {
        // Several screens ask on every redraw; work it out once per change to your data.
        let key = "\(ObjectIdentifier(container).hashValue)|\(dataVersion)|\(day)"
        if let hit = expenditureCache[key] { return hit }
        guard let s = expenditureStart, s.day <= day else { return [] }
        let p = try? fetch(FetchDescriptor<Profile>()).first
        var r: [ExpenditurePoint]
        let algorithm = ExpenditureAlgorithm(rawValue: p?.expAlgorithm ?? "") ?? .joint
        if algorithm == .joint {
            r = jointExpenditure(start: s.day, end: day, initial: s.kcal, intake: dailyIntake(), weights: weightValues,
                                 nudges: expenditureNudges(from: s.day, to: day))
        } else {
            r = expenditureSeries(start: s.day, end: day, initial: s.kcal, intake: dailyIntake(), weights: weightValues, settings: algorithm.v1Settings)
        }
        // Static: your own fixed number from now on (the dynamic estimate carries on underneath).
        if let fixed = p?.expStaticKcal, fixed > 0 {
            r = r.map { ExpenditurePoint(day: $0.day, kcal: fixed, paused: false, confidence: 1) }
        }
        expenditureCache = [key: r]
        return r
    }

    /// Log (or replace) the weight for a day.
    func logWeight(_ kg: Double, on day: String = dayKey()) {
        if let w = try? fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.day == day })).first {
            w.kg = kg
        } else {
            insert(WeightEntry(day: day, kg: kg))
        }
        commit()
    }
}

// MARK: - Weekly check-in: how the week went, your updated expenditure, and new
// targets for the week ahead (coached), or just the summary (manual targets).

struct CheckInSummary {
    let day: String
    let expenditure: Double
    let trendKg: Double
    let weekChangeKg: Double?
    let avgIntake: Double?
    let trackedDays: Int
    let current: Targets
    let proposed: Targets?          // nil in manual mode
    var raw: Targets? = nil         // what the numbers alone say, before smoothing
}

extension ModelContext {
    /// Lean mass (from a recent body-fat reading or tape measurements), height, training and floor.
    func bodyInfo(guardrails: Bool) -> BodyInfo? {
        guard let p = profile else { return nil }
        var lean: Double?
        let since = addDays(dayKey(), -90)
        if let w = ((try? fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.day >= since && $0.bodyFatPercent != nil },
                                                            sortBy: [SortDescriptor(\.day, order: .reverse)]))) ?? []).first,
           let bf = w.bodyFatPercent, bf > 3, bf < 60 {
            lean = w.kg * (1 - bf / 100)
        } else {
            let tape = (try? fetch(FetchDescriptor<Measurement>(predicate: #Predicate { $0.day >= since }, sortBy: [SortDescriptor(\.day)]))) ?? []
            func last(_ s: BodySite) -> Double? { tape.last { $0.site == s.rawValue }?.cm }
            if let bf = navyBodyFat(sex: p.sexValue, heightCm: p.heightCm, waist: last(.waist), neck: last(.neck), hips: last(.hips)),
               let kg = trendSeries(weightValues, through: dayKey()).last?.trend {
                lean = kg * (1 - bf / 100)
            }
        }
        return BodyInfo(leanKg: lean, heightCm: p.heightCm, training: TrainingType(rawValue: p.trainingType) ?? .resistance,
                        floorKcal: p.calorieFloorKcal > 0 ? p.calorieFloorKcal : nil, guardrails: guardrails)
    }
}

/// A check-in's change, informed but not decided by the new numbers: small changes go straight
/// through, bigger ones move 60% of the way (at most 200 kcal a week). Protein only moves when it
/// really changed; carbs and fat take the rest, in the diet's proportions.
func smoothed(current: Targets, raw: Targets, minFat: Double?) -> Targets {
    let d = raw.kcal - current.kcal
    let kcal = abs(d) <= 50 ? raw.kcal : roundTo(current.kcal + max(-200, min(200, d * 0.6)), 10)
    let protein = abs(raw.protein - current.protein) < 10 ? current.protein : raw.protein
    let rest = max(0, kcal - protein * 4)
    let fatShare = raw.fat * 9 / max(raw.fat * 9 + raw.carbs * 4, 1)
    var fat = rest * fatShare / 9
    if let m = minFat, fat < m { fat = min(m, rest / 9) }
    let carbs = max(0, (rest - fat * 9) / 4)
    return Targets(kcal: kcal, protein: protein, fat: fat.rounded(), carbs: carbs.rounded())
}

/// Collaborative: the new calories, keeping your own protein and your carb/fat split.
func rescaled(_ mine: Targets, toKcal kcal: Double) -> Targets {
    let rest = max(0, kcal - mine.protein * 4)
    let fatShare = mine.fat * 9 / max(mine.fat * 9 + mine.carbs * 4, 1)
    return Targets(kcal: kcal, protein: mine.protein, fat: (rest * fatShare / 9).rounded(), carbs: (rest * (1 - fatShare) / 4).rounded())
}

extension ModelContext {
    /// The check-in day that's waiting, if any: the latest check-in weekday not yet done.
    var dueCheckIn: String? {
        guard let p = activeProgram else { return nil }
        var d = dayKey()
        for _ in 0..<7 {
            if Calendar(identifier: .gregorian).component(.weekday, from: date(fromKey: d)) == p.checkInWeekday { break }
            d = addDays(d, -1)
        }
        // Not on the day the program started, and not twice for the same day.
        guard d > p.startDay, d > (p.lastCheckIn ?? "") else { return nil }
        return d
    }

    func checkInSummary() -> CheckInSummary? {
        guard let p = activeProgram, let profile, let current = targets() else { return nil }
        let today = dayKey()
        let exp = expenditureEstimates(through: today).last?.kcal ?? current.expenditure
        let series = trendSeries(weightValues, through: today)
        guard let trend = series.last?.trend else { return nil }
        let week = days(from: addDays(today, -7), through: addDays(today, -1))      // the last 7 finished days
        let intake = dailyIntake()
        let logged = week.compactMap { intake[$0] }
        let weekAgo = series.count > 7 ? series[series.count - 8].trend : nil
        let coached = p.mode == "coached"
        let raw: Targets? = p.mode == "manual" ? nil
            : makeTargets(expenditure: exp, weightKg: trend, sex: profile.sexValue, goal: p.goalValue, ratePercent: p.ratePercent,
                          diet: p.dietValue, protein: p.proteinValue, body: bodyInfo(guardrails: coached))
        let proposed: Targets? = raw.map { r in
            coached ? smoothed(current: current.targets, raw: r, minFat: max(40, 0.5 * trend))
                    : rescaled(current.targets, toKcal: smoothed(current: current.targets, raw: r, minFat: nil).kcal)
        }
        return CheckInSummary(day: today, expenditure: exp, trendKg: trend, weekChangeKg: weekAgo.map { trend - $0 },
                              avgIntake: logged.isEmpty ? nil : logged.reduce(0, +) / Double(logged.count),
                              trackedDays: logged.count, current: current.targets, proposed: proposed, raw: raw)
    }

    /// Apply (or skip) a check-in.
    func finishCheckIn(apply targets: Targets?, expenditure: Double) {
        if let targets { insert(TargetSet(targets: targets, expenditure: expenditure, reason: "check-in")) }
        activeProgram?.lastCheckIn = dayKey()
        commit()
    }
}

/// What the dashboard and weight page say about expenditure.
struct ExpenditureSummary {
    let current: Double
    let start: Double
    let confidence: Double
    let paused: Bool
    let series: [ExpenditurePoint]

    init?(_ series: [ExpenditurePoint]) {
        guard let last = series.last, let first = series.first else { return nil }
        current = last.kcal; start = first.kcal; confidence = last.confidence; paused = last.paused; self.series = series
    }

    var status: String {
        if paused && confidence < 0.05 {
            return "Starting estimate. It begins adapting once you've logged food on most days and weighed in a few times."
        }
        if paused { return "On hold: log food on at least 4 of the last 7 days (and keep weighing in) to keep it updating." }
        if confidence < 0.6 { return "Learning from your data (\(Int(confidence * 100))% so far). Keep logging food and weight." }
        return "From your own intake and weight trend."
    }
}

/// Goes up whenever saved data changes (commit or sync), so caches know to start again.
var dataVersion = 0
private var expenditureCache: [String: [ExpenditurePoint]] = [:]

/// When your trend reaches your goal weight at the current weekly rate (nil if it's moving the other way or too slowly).
func goalDate(trendKg: Double, goalKg: Double, weeklyKg: Double) -> Date? {
    let gap = goalKg - trendKg
    guard abs(gap) >= 0.1, abs(weeklyKg) >= 0.03, gap.sign == weeklyKg.sign else { return nil }
    let weeks = gap / weeklyKg
    guard weeks < 260 else { return nil }                       // more than five years: not a useful date
    return Calendar.current.date(byAdding: .day, value: Int((weeks * 7).rounded()), to: Date())
}

extension ModelContext {
    /// A day's targets: the program's, after the weekly distribution and, if you've turned it on,
    /// the weekly budget: what you ate under (or over) target earlier in the week is spread over
    /// the days left, at most ±20% a day. Protein stays put; the difference is mostly carbs.
    func dayTargets(on day: String) -> Targets? {
        guard let set = targets(on: day) else { return nil }
        let p = try? fetch(FetchDescriptor<Profile>()).first
        var t = p?.adjust(set.targets, on: day) ?? set.targets
        if let p {
            if p.inDietBreak(day) { return maintenance(set.targets, expenditure: set.expenditure) }
            t = p.refeed(t, on: day)
        }
        guard p?.weeklyBudget == true else { return t }
        let n = dayNumber(day), monday = dayKey(number: n - ((n + 3) % 7 + 7) % 7)
        let sunday = addDays(monday, 6)
        let before = min(day, dayKey())
        guard monday < before else { return t }
        let partial = partialDays
        let eaten = Dictionary(grouping: (try? fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.day >= monday && $0.day < before }))) ?? [],
                               by: \.day).mapValues { $0.reduce(0) { $0 + $1.nutrients.kcal } }
        var carry = 0.0
        for d in days(from: monday, through: addDays(before, -1)) {
            guard let k = eaten[d], !partial.contains(d), let base = targets(on: d) else { continue }   // unlogged days don't count
            carry += (p?.adjust(base.targets, on: d) ?? base.targets).kcal - k
        }
        let left = Double(daysBetween(day, sunday) + 1)
        let shift = max(-0.2 * t.kcal, min(0.2 * t.kcal, carry / left))
        t.kcal += shift
        t.carbs = max(0, t.carbs + shift * 0.6 / 4)
        t.fat = max(0, t.fat + shift * 0.4 / 9)
        return t
    }
}
