import Foundation
import SwiftData

// Your logged data, shaped for the trend and expenditure maths (Trend.swift).

extension ModelContext {
    var weightValues: [DayValue] {
        ((try? fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.day)]))) ?? []).map { DayValue(day: $0.day, value: $0.kg) }
    }

    /// kcal per day, for days with anything logged. Days with nothing logged are left out, not zero.
    func dailyIntake() -> [String: Double] {
        var out: [String: Double] = [:]
        for e in (try? fetch(FetchDescriptor<FoodEntry>())) ?? [] { out[e.day, default: 0] += e.nutrients.kcal }
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
