import Foundation
import SwiftData

// Scales, phases and the coach in shadow. Pure logic; the screens are in PhasesViews.swift.

// MARK: - Scales

/// How each named scale reads against your main one (kg to add). Kept in sync with the profile.
var scaleOffsets: [String: Double] = [:]

extension WeightEntry {
    /// The weight as your main scale would have read it: what the trend and expenditure use.
    var trendKg: Double { kg + (scaleOffsets[scale] ?? 0) }
}

extension Profile {
    var scaleOffsetMap: [String: Double] {
        get {
            Dictionary(scales.split(separator: ";").compactMap { kv -> (String, Double)? in
                let p = kv.split(separator: "=", maxSplits: 1)
                guard p.count == 2, let v = Double(p[1]) else { return nil }
                return (String(p[0]), v)
            }, uniquingKeysWith: { a, _ in a })
        }
        set {
            scales = newValue.sorted { $0.key < $1.key }.map { "\($0.key)=\(String(format: "%.2f", $0.value))" }.joined(separator: ";")
            scaleOffsets = newValue
        }
    }
    var scaleNames: [String] { scaleOffsetMap.keys.sorted() }
}

extension ModelContext {
    /// Each other scale's offset from the main one: the median gap between its readings and the
    /// main scale's trend on those days (needs 3 readings within the main scale's history).
    func estimatedScaleOffsets() -> [String: Double] {
        let all = (try? fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.day)]))) ?? []
        let main = all.filter { $0.scale.isEmpty }
        guard main.count >= 5 else { return [:] }
        // The two-sided trend: no lag, so a falling or rising weight doesn't bias the offsets.
        let trend = Dictionary(robustTrend(trendSeriesV1(main.map { DayValue(day: $0.day, value: $0.kg) }, through: dayKey())).map { ($0.day, $0.trend) },
                               uniquingKeysWith: { a, _ in a })
        var out: [String: Double] = [:]
        for (name, rows) in Dictionary(grouping: all.filter { !$0.scale.isEmpty }, by: \.scale) {
            let gaps = rows.compactMap { r in trend[r.day].map { $0 - r.kg } }.sorted()
            if gaps.count >= 3 { out[name] = gaps[gaps.count / 2] }
        }
        return out
    }
}

// MARK: - Phases

/// One planned phase: a goal at a rate, until a date (weeks from its start) or a weight.
struct PhaseStep: Codable, Identifiable, Equatable {
    var id = UUID()
    var goal: String                  // GoalType
    var ratePercent: Double
    var weeks: Int = 0                // 0 = until the weight
    var untilKg: Double? = nil

    var goalValue: GoalType { GoalType(rawValue: goal) ?? .maintain }
    func describe(_ unit: WeightUnit) -> String {
        let what = goalValue == .maintain ? "Maintain" : "\(goalValue.label) \(number(ratePercent, digits: 2))%/wk"
        if let kg = untilKg { return "\(what) until \(unit.format(kg))" }
        return "\(what) for \(weeks) week\(weeks == 1 ? "" : "s")"
    }
}

extension Profile {
    var phases: [PhaseStep] {
        get { (try? JSONDecoder().decode([PhaseStep].self, from: Data(phaseQueue.utf8))) ?? [] }
        set { phaseQueue = (try? JSONEncoder().encode(newValue)).map { String(decoding: $0, as: UTF8.self) } ?? "" }
    }

    /// "until 1 Dec" / "until 100,0 kg" / nil.
    func phaseEndText(_ unit: WeightUnit) -> String? {
        if phaseEnd.hasPrefix("day:") { return "until \(date(fromKey: String(phaseEnd.dropFirst(4))).formatted(.dateTime.day().month(.abbreviated).locale(appLocale)))" }
        if phaseEnd.hasPrefix("kg:"), let kg = Double(phaseEnd.dropFirst(3)) { return "until \(unit.format(kg))" }
        return nil
    }
}

extension ModelContext {
    /// The current phase has reached its end (its date, or the trend reached its weight).
    var phaseDone: Bool {
        guard let p = profile, let g = activeProgram else { return false }
        if p.phaseEnd.hasPrefix("day:") { return dayKey() >= String(p.phaseEnd.dropFirst(4)) }
        if p.phaseEnd.hasPrefix("kg:"), let kg = Double(p.phaseEnd.dropFirst(3)), let t = trendSeries(weightValues, through: dayKey()).last?.trend {
            switch g.goalValue {
            case .lose: return t <= kg
            case .gain: return t >= kg
            case .maintain: return false
            }
        }
        return false
    }

    /// Start the next planned phase (or maintenance, the safe default after a cut or a bulk).
    func startNextPhase() {
        guard let p = profile, let g = activeProgram else { return }
        var queue = p.phases
        let next = queue.isEmpty ? PhaseStep(goal: GoalType.maintain.rawValue, ratePercent: 0, weeks: 4) : queue.removeFirst()
        p.phases = queue
        let trend = trendSeries(weightValues, through: dayKey()).last?.trend ?? latestWeight?.kg ?? 75
        let exp = expenditureEstimates().last?.kcal ?? targets()?.expenditure ?? 2500
        startProgram(goal: next.goalValue, ratePercent: next.ratePercent, diet: g.dietValue, protein: g.proteinValue,
                     weightKg: trend, expenditure: exp, sex: p.sexValue, reason: "goal")
        p.phaseEnd = next.untilKg.map { "kg:\($0)" } ?? (next.weeks > 0 ? "day:\(addDays(dayKey(), next.weeks * 7))" : "")
        commit()
    }
}

// MARK: - Shadow mode

/// A check-in the coach ran without changing anything: what it would have set.
struct ShadowEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var day: String
    var currentKcal: Double
    var proposedKcal: Double
    var rawKcal: Double
    var expenditure: Double
    var weekChangeKg: Double?
}

extension Profile {
    var shadowEntries: [ShadowEntry] {
        get { (try? JSONDecoder().decode([ShadowEntry].self, from: Data(shadowLog.utf8))) ?? [] }
        set { shadowLog = (try? JSONEncoder().encode(Array(newValue.suffix(52)))).map { String(decoding: $0, as: UTF8.self) } ?? "" }
    }
}

extension ModelContext {
    /// What the coach would have said at each of the last `weeks` check-in days, from the data as it
    /// stood then (targets in force, expenditure through that day, the trend that week).
    func replayCheckIns(weeks: Int = 12) -> [ShadowEntry] {
        guard let p = profile, let g = activeProgram else { return [] }
        var day = dayKey()
        while Calendar(identifier: .gregorian).component(.weekday, from: date(fromKey: day)) != g.checkInWeekday { day = addDays(day, -1) }
        let series = trendSeries(weightValues, through: dayKey())
        let trendBy = Dictionary(series.map { ($0.day, $0.trend) }, uniquingKeysWith: { a, _ in a })
        var out: [ShadowEntry] = []
        for k in 0..<weeks {
            let d = addDays(day, -7 * k)
            guard let set = targets(on: d), let exp = expenditureEstimates(through: d).last, let t = trendBy[d] else { continue }
            let raw = makeTargets(expenditure: exp.kcal, weightKg: t, sex: p.sexValue, goal: g.goalValue, ratePercent: g.ratePercent,
                                  diet: g.dietValue, protein: g.proteinValue, body: bodyInfo(guardrails: true))
            let proposed = smoothed(current: set.targets, raw: raw, minFat: max(40, 0.5 * t), goal: g.goalValue, confidence: exp.confidence)
            out.append(ShadowEntry(day: d, currentKcal: set.targets.kcal, proposedKcal: proposed.kcal, rawKcal: raw.kcal,
                                   expenditure: exp.kcal, weekChangeKg: trendBy[addDays(d, -7)].map { t - $0 }))
        }
        return out
    }
}

// MARK: - Your own plan per weekday (collaborative and manual programs)

extension Profile {
    /// Calendar weekday (1 = Sunday) → targets for that day.
    var weekPlan: [Int: Targets] {
        get {
            let raw = (try? JSONDecoder().decode([String: Targets].self, from: Data(dayPlan.utf8))) ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in Int(k).map { ($0, v) } })
        }
        set {
            dayPlan = newValue.isEmpty ? "" : (try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: newValue.map { (String($0.key), $0.value) })))
                .map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
    }
}

extension ModelContext {
    /// A check-in moved the calories (collaborative): every day keeps its share of the week and its
    /// own protein and carb/fat split.
    func rescaleWeekPlan(from oldKcal: Double, to newKcal: Double) {
        guard let p = profile, oldKcal > 0, !p.weekPlan.isEmpty else { return }
        p.weekPlan = p.weekPlan.mapValues { rescaled($0, toKcal: roundTo($0.kcal * newKcal / oldKcal, 10)) }
    }
}
