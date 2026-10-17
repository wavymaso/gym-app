import Charts
import SwiftData
import SwiftUI

// The check-in's first page: is the plan working? Seven numbers about the week just finished, and
// what training and nutrition say together. Shown only on check-in day (it's part of the check-in).

/// Weekly working sets each muscle usually grows on (start of the range = enough to grow,
/// end = about the most most people recover from). Yours can differ: Settings on the Training page.
func volumeRange(_ m: Muscle) -> ClosedRange<Double> {
    if let own = (UserDefaults.standard.dictionary(forKey: "volumeRanges") as? [String: [Double]])?[m.rawValue], own.count == 2, own[0] <= own[1] {
        return own[0]...own[1]
    }
    switch m {
    case .chest: return 10...20
    case .back: return 10...22
    case .shoulders: return 8...22
    case .biceps: return 8...20
    case .triceps: return 6...18
    case .quads: return 8...18
    case .hamstrings: return 6...16
    case .glutes: return 4...16
    case .calves: return 8...16
    case .abs: return 0...16
    case .forearms: return 0...12
    default: return 0...20
    }
}

struct WeeklyReview: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @Query(sort: \WeightEntry.day) private var weights: [WeightEntry]

    var body: some View {
        let today = dayKey()
        let week = (1...7).map { addDays(today, -$0) }.reversed().map { $0 }
        let from = week.first!
        let entries = (try? ctx.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.day >= from && $0.day < today }))) ?? []
        let byDay = Dictionary(grouping: entries, by: \.day).mapValues { $0.reduce(Nutrients.zero) { $0 + $1.nutrients } }
        let partial = ctx.partialDays
        let full = week.filter { d in
            guard let n = byDay[d], !partial.contains(d) else { return false }
            return n.kcal >= (ctx.dayTargets(on: d)?.kcal ?? 0) * 0.6
        }
        let proteinHit = full.filter { d in (byDay[d]?.protein ?? 0) >= (ctx.dayTargets(on: d)?.protein ?? 1) * 0.9 }
        let unit = profiles.first?.weight ?? .kg
        let energy = profiles.first?.energy ?? .kcal
        let trend = trendSeries(weights.map { DayValue(day: $0.day, value: $0.trendKg) }, through: today)
        let rate = weeklyTrendChange(trend, days: 7)
        let program = ctx.activeProgram
        let trendKg = trend.last?.trend ?? 75
        let target = program.map { weeklyChangeKg(goal: $0.goalValue, ratePercent: $0.ratePercent, weightKg: trendKg) } ?? 0
        let exp = Array(ctx.expenditureEstimates().suffix(28))
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Your week").font(.sectionTitle)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m), GridItem(.flexible(), spacing: Space.m)], spacing: Space.m) {
                stat("Fully logged", "\(full.count)/7", "days", good: full.count >= 6)
                stat("Protein hit", "\(proteinHit.count)/\(max(full.count, 1))", "logged days", good: proteinHit.count >= max(full.count - 1, 1))
                stat("Rate", rate.map { signed(unit, $0) } ?? "–", "a week · goal \(signed(unit, target))",
                     good: rate.map { abs($0 - target) <= max(0.15, abs(target) * 0.5) })
                stat("Expenditure", exp.last.map { energy.format($0.kcal) } ?? "–",
                     exp.count > 7 ? "\(signedKcal(exp.last!.kcal - exp[exp.count - 8].kcal, energy)) this week" : "", good: nil)
            }
            if exp.count > 3 {
                Chart(Array(exp), id: \.day) { p in
                    let band = (1 - p.confidence) * 280 + 40
                    AreaMark(x: .value("Day", date(fromKey: p.day)), yStart: .value("lo", p.kcal - band), yEnd: .value("hi", p.kcal + band))
                        .foregroundStyle(Color.expenditureTone.opacity(0.2))
                    LineMark(x: .value("Day", date(fromKey: p.day)), y: .value("kcal", p.kcal)).foregroundStyle(Color.expenditureTone)
                }
                .chartYScale(domain: .automatic(includesZero: false)).chartXAxis(.hidden)
                .dayTip("Expenditure", days: exp.map(\.day)) { d in
                    exp.filter { $0.day == d }.map { TipRow(label: "Estimate", value: energy.format($0.kcal), color: Color.expenditureTone) }
                }
                .frame(height: 90)
                Text("Expenditure, last 4 weeks. The band is how unsure the estimate still is; it narrows as you log.")
                    .font(.note).foregroundStyle(.secondary)
            }
            musclesCard
            sleepCard
            StrengthRetentionCard(unit: unit)
            ForEach(flags(rate: rate, trendKg: trendKg, goal: program?.goalValue, target: target), id: \.self) { f in
                Label(f, systemImage: "lightbulb.fill").font(.secondaryText)
                    .padding(Space.m).frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.m))
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ note: String, good: Bool?) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(title).font(.label).foregroundStyle(.secondary)
                Spacer()
                if let good { Image(systemName: good ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(good ? palette.good : palette.warn) }
            }
            Text(value).font(.numberMedium).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(note).font(.fine).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.m).modifier(CardSurface(cornerRadius: Radius.m))
    }

    /// Working sets per muscle this past week against each muscle's range.
    private var musclesCard: some View {
        let today = dayKey(), from = addDays(today, -7)
        let sets = (try? ctx.fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.day >= from && $0.day < today && $0.done }))) ?? []
        let counts = setsPerMuscle(sets.compactMap { s in ctx.exercise(s.exerciseKey).map { ($0.muscleValue, $0.secondaryValues, s.kindValue) } })
        let rows = Muscle.allCases.filter { $0 != .cardio && $0 != .fullBody && ((counts[$0] ?? 0) > 0 || volumeRange($0).lowerBound > 0) }
        return Card(title: "Sets per muscle", systemImage: "chart.bar.fill") {
            ForEach(rows) { m in
                let n = counts[m] ?? 0, r = volumeRange(m)
                HStack(spacing: Space.m) {
                    Text(m.label).font(.label).frame(width: 82, alignment: .leading)
                    GeometryReader { g in
                        let w = g.size.width, top = max(r.upperBound + 4, n)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.raisedBackground)
                            Rectangle().fill(palette.good.opacity(0.18))
                                .frame(width: w * (r.upperBound - r.lowerBound) / top).offset(x: w * r.lowerBound / top)
                            Capsule().fill(n < r.lowerBound ? palette.warn : n > r.upperBound ? palette.protein : palette.good)
                                .frame(width: max(4, w * min(n, top) / top))
                        }
                    }
                    .frame(height: 8)
                    Text(number(n, digits: n == n.rounded() ? 0 : 1)).font(.label).monospacedDigit().frame(width: 30, alignment: .trailing)
                }
            }
            Text("Shaded: the range that grows each muscle for most people. Helper muscles count as half a set.").font(.note).foregroundStyle(.secondary)
        }
    }

    private var sleep: (now: Double?, before: Double?) {
        let today = dayKey(), from = addDays(today, -14)
        let rows = ((try? ctx.fetch(FetchDescriptor<DailyActivity>(predicate: #Predicate { $0.day >= from && $0.day <= today }))) ?? []).filter { $0.sleepHours > 1 }
        func avg(_ r: [DailyActivity]) -> Double? { r.count >= 3 ? r.map(\.sleepHours).reduce(0, +) / Double(r.count) : nil }
        let cut = addDays(today, -6)
        return (avg(rows.filter { $0.day >= cut }), avg(rows.filter { $0.day < cut }))
    }

    @ViewBuilder private var sleepCard: some View {
        let s = sleep
        if let now = s.now {
            HStack(spacing: Space.m) {
                Image(systemName: "bed.double.fill").font(.subsectionTitle).foregroundStyle(Color.calmTone)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Sleep \(number(now, digits: 1)) h a night").font(.cardTitle)
                    Text(s.before.map { "\($0 <= now ? "+" : "−")\(number(abs(now - $0), digits: 1)) h on the week before" } ?? "from Apple Health")
                        .font(.note).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: now >= 7 ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(now >= 7 ? palette.good : palette.warn)
            }
            .padding(Space.m).modifier(CardSurface(cornerRadius: Radius.m))
        }
    }

    /// What nutrition and training say together (no other app can: they're in one place here).
    private func flags(rate: Double?, trendKg: Double, goal: GoalType?, target: Double) -> [String] {
        guard let rate, let goal else { return [] }
        let from = addDays(dayKey(), -62)
        let sets = ((try? ctx.fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.day >= from && $0.done }))) ?? [])
            .filter { $0.kindValue.counts && $0.reps > 0 && $0.reps <= 10 && $0.kg > 0 }
        let top = Dictionary(grouping: sets, by: \.exerciseKey).sorted { $0.value.count > $1.value.count }.prefix(4)
        let changes: [Double] = top.compactMap { _, rows in
            let recent = rows.filter { $0.day >= addDays(dayKey(), -14) }.map(\.e1rm).max()
            let before = rows.filter { $0.day < addDays(dayKey(), -14) && $0.day >= addDays(dayKey(), -42) }.map(\.e1rm).max()
            guard let r = recent, let b = before, b > 0 else { return nil }
            return r / b - 1
        }
        let falling = changes.filter { $0 < -0.03 }.count, rising = changes.filter { $0 > 0.01 }.count
        var out: [String] = []
        let pctPerWeek = rate / trendKg * 100
        let slept = sleep.now
        if falling >= 2, let h = slept, h < 6.5 {
            out.append("\(falling) main lifts are down, and you've slept \(number(h, digits: 1)) h a night. That's likely the sleep, not the calories: fix sleep before changing the plan.")
        } else if goal == .lose, pctPerWeek < -0.75, falling >= 2 {
            out.append("You're losing \(number(abs(pctPerWeek), digits: 1))% a week and \(falling) main lifts are down. The deficit looks too aggressive for keeping muscle: consider a slower rate or a diet break.")
        }
        if goal == .gain, rate > target * 1.5, rising == 0, !changes.isEmpty {
            out.append("Gaining faster than planned while your lifts are flat: the extra is likely going to fat. A slightly smaller surplus would do the same for muscle.")
        }
        if goal == .lose, falling == 0, rising >= 2, pctPerWeek < -0.3 {
            out.append("Losing weight with your lifts going up: muscle is being kept. Keep it up.")
        }
        return out
    }
}

extension WorkoutSet {
    /// Estimated 1RM, honest: reps you had left count (RIR), and only sets of 1–10 reps count at all.
    var e1rm: Double {
        guard reps > 0, reps <= 10, kg > 0 else { return 0 }
        return estimatedOneRepMax(kg: kg, reps: reps + Int((rir ?? 0).rounded()))
    }
}
