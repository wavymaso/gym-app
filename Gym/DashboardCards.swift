import Charts
import SwiftData
import SwiftUI

/// The hero: a big calorie ring with what's left, and a ring per macro.
struct TodayRings: View {
    let eaten: Targets
    let target: Targets
    let energy: EnergyUnit

    var body: some View {
        rings.capType()
    }

    private var rings: some View {
        Card(title: "") {
            let layout = isPhone ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(spacing: 36))
            layout {
                calorieRing
                HStack(spacing: isPhone ? 0 : 28) {
                    ForEach([Macro.protein, .fat, .carbs], id: \.self) { m in
                        macroRing(m)
                        if isPhone && m != .carbs { Spacer(minLength: 0) }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, isPhone ? 0 : 8)
            .frame(maxWidth: .infinity)
        }
    }

    private var calorieRing: some View {
        let left = target.kcal - eaten.kcal
        return ZStack {
            Ring(progress: target.kcal > 0 ? eaten.kcal / target.kcal : 0, color: Macro.calories.color, lineWidth: 18)
            VStack(spacing: 0) {
                Text(number(energy.fromKcal(abs(left)))).font(.number(44)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                    .contentTransition(.numericText(value: left)).animation(Motion.snappy, value: left)
                Text("\(energy.rawValue) \(left >= 0 ? "left" : "over")").font(.subheadline.weight(.semibold))
                    .foregroundStyle(left >= 0 ? Color.secondary : palette.warn)
                Text("\(number(energy.fromKcal(eaten.kcal))) of \(energy.format(target.kcal))").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            }
            .padding(30)
        }
        .frame(width: isPhone ? 180 : 210, height: isPhone ? 180 : 210)
    }

    private func macroRing(_ m: Macro) -> some View {
        let e = m.value(eaten), t = m.value(target)
        return VStack(spacing: 8) {
            ZStack {
                Ring(progress: t > 0 ? e / t : 0, color: m.color, lineWidth: 9)
                VStack(spacing: -2) {
                    Text(number(e)).font(.number(18)).monospacedDigit()
                        .contentTransition(.numericText(value: e)).animation(Motion.snappy, value: e)
                    Text("/\(number(t))").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .frame(width: isPhone ? 72 : 92, height: isPhone ? 72 : 92)
            Text(m.label).font(.subheadline.weight(.semibold))
            Text(e <= t ? "\(number(t - e)) g left" : "\(number(e - t)) g over").font(.caption)
                .foregroundStyle(e <= t ? Color.secondary : palette.warn).monospacedDigit()
        }
    }
}

/// A big square button with an icon, for the dashboard.
struct QuickAction: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(color)
                    .frame(width: 40, height: 40).background(color.opacity(0.16), in: Circle())
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .modifier(CardSurface(cornerRadius: Radius.l))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "−0,4 kg/wk" in green when it's the way you want, orange when not, grey when it doesn't matter.
struct Delta: View {
    let text: String
    let good: Bool?
    var body: some View {
        let c: Color = good == nil ? .secondary : (good! ? palette.good : palette.warn)
        Text(text).font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(c)
            .padding(.horizontal, 8).padding(.vertical, 4).background(c.opacity(0.14), in: Capsule())
    }
}

/// The last seven days: calories against target, and averages.
struct WeekNutritionCard: View {
    let entries: [FoodEntry]
    let target: (String) -> Targets?
    let energy: EnergyUnit

    var body: some View {
        let days = (0..<7).map { addDays(dayKey(), $0 - 6) }
        let byDay = Dictionary(grouping: entries, by: \.day).mapValues { $0.reduce(Nutrients.zero) { $0 + $1.nutrients } }
        let logged = days.filter { byDay[$0] != nil && $0 != dayKey() }
        let avg = logged.isEmpty ? nil : logged.reduce(0) { $0 + (byDay[$1]?.kcal ?? 0) } / Double(logged.count)
        let avgP = logged.isEmpty ? nil : logged.reduce(0) { $0 + (byDay[$1]?.protein ?? 0) } / Double(logged.count)
        let onTarget = logged.filter { d in
            guard let t = target(d)?.kcal, t > 0, let k = byDay[d]?.kcal else { return false }
            return abs(k - t) / t <= 0.1
        }.count
        Card(title: "Last 7 days", systemImage: "chart.bar") {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days, id: \.self) { d in
                    let k = byDay[d]?.kcal ?? 0, t = target(d)?.kcal ?? 0
                    VStack(spacing: 5) {
                        GeometryReader { g in
                            let h = g.size.height, top = max(t * 1.25, k, 1)
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 5).fill(Color.raisedBackground)
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(d == dayKey() ? Macro.calories.color.opacity(0.5) : (t > 0 && abs(k - t) / t <= 0.1 ? Macro.calories.color : Macro.calories.color.opacity(0.75)))
                                    .frame(height: h * k / top)
                                if t > 0 {
                                    Rectangle().fill(.primary.opacity(0.5)).frame(height: 1.5).offset(y: -h * t / top)
                                }
                            }
                        }
                        .frame(height: 90)
                        Text(date(fromKey: d).formatted(.dateTime.weekday(.narrow).locale(appLocale)))
                            .font(.caption2.weight(d == dayKey() ? .bold : .regular)).foregroundStyle(d == dayKey() ? .primary : .secondary)
                    }
                }
            }
            HStack {
                stat("Average", avg.map { energy.format($0) } ?? "–")
                Spacer()
                stat("Protein", avgP.map { "\(number($0)) g" } ?? "–")
                Spacer()
                stat("On target", logged.isEmpty ? "–" : "\(onTarget)/\(logged.count)")
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.number(17, weight: .semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// This week's training and what's next.
struct TrainingCard: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.openPage) private var openPage
    @Query(filter: #Predicate<Workout> { $0.end != nil }, sort: \Workout.start, order: .reverse) private var finished: [Workout]
    @Query(sort: \Routine.order) private var routines: [Routine]
    @Query private var weekSets: [WorkoutSet]

    init() {
        let monday = dayKey(mondayThisWeek())
        _weekSets = Query(filter: #Predicate<WorkoutSet> { $0.day >= monday && $0.done })
    }

    var body: some View {
        let monday = dayKey(mondayThisWeek())
        let thisWeek = finished.filter { $0.day >= monday }
        let volume = weekSets.filter { $0.kindValue != .warmup }.reduce(0.0) { $0 + $1.kg * Double($1.reps) }
        let minutes = thisWeek.reduce(0) { $0 + $1.duration } / 60
        Card(title: "Training this week", systemImage: "dumbbell") {
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let d = addDays(monday, i)
                    let trained = thisWeek.contains { $0.day == d }
                    VStack(spacing: 4) {
                        Circle().fill(trained ? Macro.protein.color : Color.raisedBackground).frame(width: 26, height: 26)
                            .overlay { if trained { Image(systemName: "checkmark").font(.caption2.weight(.heavy)).foregroundStyle(palette.onData) } }
                            .overlay { if d == dayKey() && !trained { Circle().stroke(Macro.protein.color, lineWidth: 2) } }
                        Text(date(fromKey: d).formatted(.dateTime.weekday(.narrow).locale(appLocale))).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack {
                stat("Workouts", "\(thisWeek.count)")
                Spacer()
                stat("Time", minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min")
                Spacer()
                stat("Volume", volume >= 1000 ? "\(number(volume / 1000, digits: 1)) t" : "\(number(volume)) kg")
            }
            if let next = nextRoutine {
                Button {
                    ctx.startWorkout(routine: next); openPage(.workouts)
                } label: {
                    Label("Start \(next.name)", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent).controlSize(.large)
            } else if let last = finished.first {
                Text("Last: \(last.name), \(relative(last.day))").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    /// The routine after the one you did last (round and round), or the first.
    private var nextRoutine: Routine? {
        guard !routines.isEmpty else { return nil }
        guard let lastKey = finished.first(where: { $0.routineKey != nil })?.routineKey,
              let i = routines.firstIndex(where: { $0.key == lastKey }) else {
            if let last = finished.first, let byName = routines.firstIndex(where: { $0.name == last.name }) {
                return routines[(byName + 1) % routines.count]
            }
            return routines.first
        }
        return routines[(i + 1) % routines.count]
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.number(17, weight: .semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A small line with no axes, for the dashboard tiles.
struct Sparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        Chart(Array(values.enumerated()), id: \.offset) { p in
            LineMark(x: .value("Day", p.offset), y: .value("Value", p.element))
                .foregroundStyle(color).interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .chartYScale(domain: (lo - max(0.5, (hi - lo) * 0.15))...(hi + max(0.5, (hi - lo) * 0.15)))
        .indexTip(count: values.count, title: { i in i == values.count - 1 ? "Latest" : "\(values.count - 1 - i) days ago" }) { i in
            [TipRow(label: "Value", value: number(values[i], digits: values[i] < 200 ? 1 : 0), color: color)]
        }
        .frame(height: 44)
    }
}

/// Monday to Sunday: calories each day against that day's target, today outlined, and the week's totals.
struct WeekTargetsWidget: View {
    let entries: [FoodEntry]
    let target: (String) -> Targets?
    let energy: EnergyUnit

    var body: some View {
        let monday = dayKey(mondayThisWeek())
        let days = (0..<7).map { addDays(monday, $0) }
        let byDay = Dictionary(grouping: entries.filter { $0.day >= monday }, by: \.day).mapValues { $0.reduce(Nutrients.zero) { $0 + $1.nutrients } }
        let weekEaten = days.reduce(0.0) { $0 + (byDay[$1]?.kcal ?? 0) }
        let weekTarget = days.reduce(0.0) { $0 + (target($1)?.kcal ?? 0) }
        let today = byDay[dayKey()] ?? .zero, tt = target(dayKey())
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(days, id: \.self) { d in
                    let k = byDay[d]?.kcal ?? 0, t = target(d)?.kcal ?? 0
                    let top = max(days.compactMap { target($0)?.kcal }.max() ?? 1, 1) * 1.2
                    VStack(spacing: 5) {
                        GeometryReader { g in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 5).fill(Color.raisedBackground).frame(height: g.size.height * t / top)
                                RoundedRectangle(cornerRadius: 5).fill(k >= t * 0.98 && t > 0 ? Macro.calories.color : Macro.calories.color.opacity(0.7))
                                    .frame(height: g.size.height * min(k, top) / top)
                                Rectangle().fill(k >= t && t > 0 ? Color.primary : Color.primary.opacity(0.35)).frame(height: 2)
                                    .offset(y: -g.size.height * t / top + 1).opacity(t > 0 ? 1 : 0)
                            }
                            .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
                        }
                        .padding(3)
                        .overlay { if d == dayKey() { RoundedRectangle(cornerRadius: 7).stroke(palette.accent, lineWidth: 1.5) } }
                        Text(date(fromKey: d).formatted(.dateTime.weekday(.narrow).locale(appLocale)))
                            .font(.caption2.weight(d == dayKey() ? .bold : .regular)).foregroundStyle(d == dayKey() ? .primary : .secondary)
                    }
                }
            }
            .frame(height: 150)
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("This week").font(.caption).foregroundStyle(.secondary)
                    Text("\(number(energy.fromKcal(weekEaten))) / \(energy.format(weekTarget))").font(.number(15, weight: .semibold)).monospacedDigit()
                }
                Spacer()
                if let tt {
                    HStack(spacing: 10) {
                        mini("flame.fill", today.kcal, tt.kcal, Macro.calories.color)
                        mini("P", today.protein, tt.protein, Macro.protein.color)
                        mini("F", today.fat, tt.fat, Macro.fat.color)
                        mini("C", today.carbs, tt.carbs, Macro.carbs.color)
                    }
                }
            }
        }
    }

    private func mini(_ label: String, _ v: Double, _ t: Double, _ c: Color) -> some View {
        VStack(spacing: 0) {
            if label.count > 1 { Image(systemName: label).font(.caption2).foregroundStyle(c) } else { Text(label).font(.caption2.weight(.bold)).foregroundStyle(c) }
            Text(number(v)).font(.caption.weight(.bold)).monospacedDigit()
            Text(number(t)).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
