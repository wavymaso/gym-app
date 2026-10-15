import Foundation
import SwiftData

// Your logged data, shaped for the trend and expenditure maths (Trend.swift).

extension ModelContext {
    var weightValues: [DayValue] {
        let key = "\(ObjectIdentifier(container).hashValue)|\(dataVersion)"
        if let hit = weightCache[key] { return hit }
        scaleOffsets = profile?.scaleOffsetMap ?? [:]
        let v = ((try? fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.day)]))) ?? []).map { DayValue(day: $0.day, value: $0.trendKg) }
        weightCache = [key: v]
        return v
    }

    /// kcal per finished day (before today), for days with anything logged. Days with nothing
    /// logged are left out, not counted as zero, and today is left out because it isn't over yet.
    func dailyIntake() -> [String: Double] {
        let key = "\(ObjectIdentifier(container).hashValue)|\(dataVersion)|\(dayKey())"
        if let hit = intakeCache[key] { return hit }
        let v = dailyIntakeUncached()
        intakeCache = [key: v]
        return v
    }

    private func dailyIntakeUncached() -> [String: Double] {
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

    /// Days the scale can jump from water rather than mass: refeeds, the start and end of a diet
    /// break, and days you tagged (salty meal, creatine, travel).
    func waterEvents(from start: String, to end: String) -> Set<String> {
        var out = Set(((try? fetch(FetchDescriptor<DayNote>(predicate: #Predicate { $0.waterEvent }))) ?? []).map(\.day))
        if let p = profile {
            if p.refeedWeekday > 0 {
                for d in days(from: max(start, p.refeedSince.isEmpty ? end : p.refeedSince), through: end)
                where Calendar(identifier: .gregorian).component(.weekday, from: date(fromKey: d)) == p.refeedWeekday { out.insert(addDays(d, 1)) }
            }
            if !p.dietBreakStart.isEmpty { out.insert(p.dietBreakStart); out.insert(addDays(p.dietBreakStart, 1)) }
            if !p.dietBreakEnd.isEmpty { out.insert(addDays(p.dietBreakEnd, 1)); out.insert(addDays(p.dietBreakEnd, 2)) }
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
        let algorithm = ExpenditureAlgorithm(rawValue: p?.expAlgorithm ?? "") ?? .classic
        if algorithm == .classic {
            r = classicExpenditure(start: s.day, end: day, initial: s.kcal, intake: dailyIntake(), weights: weightValues)
        } else if algorithm == .joint {
            var js = JointSettings()
            js.waterEvents = waterEvents(from: s.day, to: day)
            r = jointExpenditure(start: s.day, end: day, initial: s.kcal, intake: dailyIntake(), weights: weightValues,
                                 nudges: expenditureNudges(from: s.day, to: day), settings: js)
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
    func logWeight(_ kg: Double, on day: String = dayKey(), scale: String = "") {
        if let w = try? fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.day == day })).first {
            w.kg = kg; w.scale = scale
        } else {
            let w = WeightEntry(day: day, kg: kg); w.scale = scale
            insert(w)
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
    var confidence: Double = 1      // how sure the expenditure estimate is (0–1)
    var targetWeeklyKg: Double = 0  // the goal's rate

    /// One line: why the targets change (or don't).
    func why(_ unit: WeightUnit, _ energy: EnergyUnit) -> String {
        var parts: [String] = []
        if let w = weekChangeKg { parts.append("trend \(signed(unit, w))/wk vs goal \(signed(unit, targetWeeklyKg))") }
        parts.append("expenditure \(energy.format(expenditure)) (\(Int(confidence * 100))% sure)")
        if let r = raw, let p = proposed {
            let d = r.kcal - current.kcal, a = p.kcal - current.kcal
            if abs(d) <= 50 { parts.append("within ±50 kcal: no change") }
            else if abs(a - d) >= 10 { parts.append("the numbers say \(d > 0 ? "+" : "−")\(number(abs(energy.fromKcal(d)))), applying \(a >= 0 ? "+" : "−")\(number(abs(energy.fromKcal(a))))\(abs(a) >= 150 || (a <= -75 && d < 0) ? " (weekly cap)" : "")") }
            else { parts.append("\(a >= 0 ? "+" : "−")\(number(abs(energy.fromKcal(a)))) \(energy.rawValue)") }
        }
        return parts.joined(separator: " · ")
    }

    /// Real changes are slow: a big jump in expenditure is more likely a data problem. Confirm first.
    var needsConfirmation: Bool { abs(expenditure - previousExpenditure) > 250 }
    var previousExpenditure: Double = 0
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
        // The default floor is your BMR (at least 1200): right at both ends of a long cut, unlike a fixed number.
        let kg = trendSeries(weightValues, through: dayKey()).last?.trend ?? 75
        let floor = p.calorieFloorKcal > 0 ? p.calorieFloorKcal
            : max(1200, roundTo(bmr(sex: p.sexValue, weightKg: kg, heightCm: p.heightCm, age: age(born: p.birthDate),
                                    equation: lean != nil ? .katch : .mifflin, bodyFat: lean.map { (1 - $0 / kg) * 100 }), 10))
        return BodyInfo(leanKg: lean, heightCm: p.heightCm, training: TrainingType(rawValue: p.trainingType) ?? .resistance,
                        floorKcal: floor, guardrails: guardrails)
    }
}

/// A check-in's change, informed but not decided by the new numbers, so weekly coaching doesn't
/// chase water: within ±50 kcal nothing changes (noise); otherwise it moves 35–70% of the way
/// (more the surer the expenditure estimate is), at most 150 kcal, and on a bulk at most 75 kcal
/// down (slow to cut a bulk that may just be water). Protein only moves when it really changed;
/// carbs and fat take the rest, in the diet's proportions.
func smoothed(current: Targets, raw: Targets, minFat: Double?, goal: GoalType = .maintain, confidence: Double = 1) -> Targets {
    let d = raw.kcal - current.kcal
    let step = d * (0.35 + 0.35 * max(0, min(1, confidence)))
    let down = goal == .gain ? 75.0 : 150.0
    let kcal = abs(d) <= 50 ? current.kcal : roundTo(current.kcal + max(-down, min(150, step)), 10)
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
        let conf = expenditureEstimates(through: today).last?.confidence ?? 0
        let proposed: Targets? = raw.map { r in
            coached ? smoothed(current: current.targets, raw: r, minFat: max(40, 0.5 * trend), goal: p.goalValue, confidence: conf)
                    : rescaled(current.targets, toKcal: smoothed(current: current.targets, raw: r, minFat: nil, goal: p.goalValue, confidence: conf).kcal)
        }
        return CheckInSummary(day: today, expenditure: exp, trendKg: trend, weekChangeKg: weekAgo.map { trend - $0 },
                              avgIntake: logged.isEmpty ? nil : logged.reduce(0, +) / Double(logged.count),
                              trackedDays: logged.count, current: current.targets, proposed: proposed, raw: raw, confidence: conf,
                              targetWeeklyKg: weeklyChangeKg(goal: p.goalValue, ratePercent: p.ratePercent, weightKg: trend),
                              previousExpenditure: current.expenditure)
    }

    /// Apply (or skip) a check-in.
    func finishCheckIn(apply targets: Targets?, expenditure: Double) {
        if let targets {
            if activeProgram?.mode == "collaborative", let old = self.targets()?.targets.kcal { rescaleWeekPlan(from: old, to: targets.kcal) }
            insert(TargetSet(targets: targets, expenditure: expenditure, reason: "check-in"))
        }
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
private var weightCache: [String: [DayValue]] = [:]
private var intakeCache: [String: [String: Double]] = [:]
private var dayTargetCache: [String: Targets?] = [:]

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
        let key = "\(ObjectIdentifier(container).hashValue)|\(dataVersion)|\(dayKey())|\(day)"
        if let hit = dayTargetCache[key] { return hit }
        if dayTargetCache.count > 400 { dayTargetCache = [:] }
        let v = dayTargetsUncached(on: day)
        dayTargetCache[key] = v
        return v
    }

    private func dayTargetsUncached(on day: String) -> Targets? {
        guard let set = targets(on: day) else { return nil }
        let p = try? fetch(FetchDescriptor<Profile>()).first
        var t = p?.adjust(set.targets, on: day) ?? set.targets
        if let p {
            if p.inDietBreak(day) { return maintenance(set.targets, expenditure: set.expenditure) }
            // Your own day-by-day plan (collaborative or manual) replaces the distribution.
            if activeProgram?.mode != "coached",
               let own = p.weekPlan[Calendar(identifier: .gregorian).component(.weekday, from: date(fromKey: day))] { return own }
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
