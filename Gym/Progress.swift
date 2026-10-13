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
        var out: [String: Double] = [:]
        for e in (try? fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.day < today }))) ?? [] {
            out[e.day, default: 0] += e.nutrients.kcal
        }
        return out
    }

    /// When the app started estimating, and from what: your first program and the setup estimate.
    var expenditureStart: (day: String, kcal: Double)? {
        guard let first = try? fetch(FetchDescriptor<Program>(sortBy: [SortDescriptor(\.startDay)])).first else { return nil }
        return (first.startDay, first.startExpenditure)
    }

    /// Daily expenditure estimates from the start through `day`.
    func expenditureEstimates(through day: String = dayKey()) -> [ExpenditurePoint] {
        guard let s = expenditureStart, s.day <= day else { return [] }
        return expenditureSeries(start: s.day, end: day, initial: s.kcal, intake: dailyIntake(), weights: weightValues)
    }

    /// Log (or replace) the weight for a day.
    func logWeight(_ kg: Double, on day: String = dayKey()) {
        if let w = try? fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.day == day })).first {
            w.kg = kg
        } else {
            insert(WeightEntry(day: day, kg: kg))
        }
        try? save()
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
        try? save()
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
