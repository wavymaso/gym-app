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
        let proposed = p.mode == "coached"
            ? makeTargets(expenditure: exp, weightKg: trend, sex: profile.sexValue, goal: p.goalValue, ratePercent: p.ratePercent,
                          diet: p.dietValue, protein: p.proteinValue)
            : nil
        return CheckInSummary(day: today, expenditure: exp, trendKg: trend, weekChangeKg: weekAgo.map { trend - $0 },
                              avgIntake: logged.isEmpty ? nil : logged.reduce(0, +) / Double(logged.count),
                              trackedDays: logged.count, current: current.targets, proposed: proposed)
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
