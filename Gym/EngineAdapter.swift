import Foundation
import SwiftData

// Between the app's data and the Coaching Engine (Gym/Engine). The engine runs in shadow mode: its
// decisions are stored and shown next to the live ones, but only the live ones change your targets.

/// A stored engine decision (synced), so any past check-in can be opened and explained.
@Model final class DecisionRecord {
    var syncID: String = ""
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var day: String
    var kind: String                  // "checkin"
    var json: String                  // CheckInRecord
    var live: Bool                    // false: shadow (shown, not applied)
    init(day: String, kind: String, json: String, live: Bool) { self.day = day; self.kind = kind; self.json = json; self.live = live }

    var record: CheckInRecord? { try? JSONDecoder().decode(CheckInRecord.self, from: Data(json.utf8)) }
}

/// What the engine sees right now: its trend, expenditure and the inputs behind them.
struct EngineSnapshot {
    var days: [EngineDay]
    var trend: [TrendPoint]
    var expenditure: [ExpenditureEstimate]
    var body: BodyComposition
    var person: Person
}

extension ModelContext {
    var enginePerson: Person? {
        guard let p = profile else { return nil }
        let first = ((try? fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.start)]))) ?? []).first?.start
        let years = first.map { Date().timeIntervalSince($0) / (365.25 * 86400) } ?? 3
        return Person(male: p.sexValue == .male, heightCm: p.heightCm, age: age(born: p.birthDate), trainingYears: years)
    }

    var engineBody: BodyComposition {
        let kg = weightValues.last?.value ?? 75
        guard let lean = bodyInfo(guardrails: true)?.leanKg, kg > lean else { return BodyComposition() }
        return BodyComposition(bodyFatPercent: (1 - lean / kg) * 100)
    }

    /// Every day from the first weigh-in to today: weigh-ins (scale-corrected), intake (logged, complete
    /// days only), water events and steps.
    func engineDays(through end: String = dayKey()) -> [EngineDay] {
        let weights = weightValues
        guard let first = weights.first?.day else { return [] }
        let wmap = Dictionary(grouping: weights, by: \.day).mapValues { $0.map(\.value) }
        let intake = dailyIntake()
        let notes = Set(((try? fetch(FetchDescriptor<DayNote>(predicate: #Predicate { $0.waterEvent }))) ?? []).map(\.day))
        var events: [String: Set<WaterEvent>] = [:]
        for d in notes { events[d, default: []].insert(.tagged) }
        if let p = profile {
            for d in waterEvents(from: first, to: end) where !notes.contains(d) {
                events[d, default: []].insert(d == p.dietBreakStart || d == addDays(p.dietBreakStart, 1) ? .dietBreakStart
                                              : (d == addDays(p.dietBreakEnd, 1) || d == addDays(p.dietBreakEnd, 2)) ? .dietBreakEnd : .refeed)
            }
        }
        let acts = Dictionary(((try? fetch(FetchDescriptor<DailyActivity>())) ?? []).map { ($0.day, Double($0.steps)) }, uniquingKeysWith: { a, _ in a })
        return days(from: first, through: end).map { d in
            EngineDay(key: d, weighIns: wmap[d] ?? [], intake: intake[d], events: events[d] ?? [], steps: acts[d])
        }
    }

    func engineSnapshot() -> EngineSnapshot? {
        guard let person = enginePerson else { return nil }
        let ds = engineDays()
        guard !ds.isEmpty else { return nil }
        let body = engineBody
        let trend = EngineTrend.run(ds)
        let kg = trend.last?.trend ?? 75
        let prior = expenditureStart?.kcal ?? EngineTargets.mifflin(person, weight: kg) * 1.55
        return EngineSnapshot(days: ds, trend: trend, expenditure: EngineEnergy.run(ds, trend: trend, prior: prior, body: body), body: body, person: person)
    }

    /// What the engine would decide at a check-in today.
    func engineCheckIn() -> CheckInRecord? {
        guard let s = engineSnapshot(), let g = activeProgram, let current = targets(), let t = s.trend.last, let e = s.expenditure.last else { return nil }
        let today = dayKey()
        let week = s.days.suffix(8).dropLast()                    // the last 7 finished days
        let logged = week.compactMap(\.intake)
        let phase: Phase = g.goalValue == .lose ? .cut : g.goalValue == .gain ? .bulk : .maintain
        let weeks = daysBetween(g.startDay, today) / 7
        // Training signals (main lifts, e1RM from 3–10 reps).
        let sets = ((try? fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.done }))) ?? [])
            .map { LiftSession(day: $0.day, exercise: $0.exerciseKey, kg: $0.kg, reps: $0.reps, rir: $0.rir) }
        let weekly = EngineSignals.weekly(sets, weekOf: { daysBetween(g.startDay, $0) / 7 })
        let sleep = ((try? fetch(FetchDescriptor<DailyActivity>())) ?? []).filter { $0.day > addDays(today, -8) && $0.sleepHours > 1 }.map(\.sleepHours)
        let flags = EngineSignals.flags(weekly: weekly, thisWeek: weeks, phase: phase, observedRate: t.ratePerWeek,
                                        targetRate: weeklyChangeKg(goal: g.goalValue, ratePercent: g.ratePercent, weightKg: t.trend),
                                        weeksInPhase: weeks, adherence: Double(logged.count) / 7,
                                        sleepHours: sleep.isEmpty ? nil : sleep.reduce(0, +) / Double(sleep.count))
        let input = CheckInInput(day: today, phase: phase.rawValue, weeksInPhase: weeks, targetRatePct: g.ratePercent, trendKg: t.trend, trendSD: t.sd,
                                 observedRateKgWeek: t.ratePerWeek, expenditure: e.kcal, expenditureSD: e.sd,
                                 loggedDays: logged.count, weighIns: week.filter { !$0.weighIns.isEmpty }.count,
                                 waterEventLast3Days: s.days.suffix(3).contains { !$0.events.isEmpty }, daysOfData: s.days.count,
                                 avgIntake: logged.isEmpty ? nil : logged.reduce(0, +) / Double(logged.count),
                                 currentTargets: MacroTargets(kcal: current.kcal, protein: current.protein, fat: current.fat, carbs: current.carbs),
                                 style: g.mode, flags: flags.map(\.detail))
        var r = EngineCheckIn.decide(input, person: s.person, body: s.body)
        r.reasons += flags
        return r
    }

    /// Store today's shadow decision (once per day).
    func saveShadowCheckIn() {
        guard let r = engineCheckIn(), let data = try? JSONEncoder().encode(r) else { return }
        let day = r.input.day
        for old in (try? fetch(FetchDescriptor<DecisionRecord>(predicate: #Predicate { $0.day == day && $0.kind == "checkin" }))) ?? [] { delete(old) }
        insert(DecisionRecord(day: day, kind: "checkin", json: String(decoding: data, as: UTF8.self), live: false))
        commit()
    }
}
