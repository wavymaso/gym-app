import SwiftData
import SwiftUI

// MacroFactor's Edit Goal flow: an intro with the two steps, the goal (target weight on a ruler,
// rate on a slider with live budget and end date), then a review of what changes.

struct EditGoalFlow: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]
    @Query(sort: \WeightEntry.day) private var weights: [WeightEntry]
    @State private var step = UserDefaults.standard.integer(forKey: "goalStep")     // 0 intro, 1 goal, 2 review (testing: -goalStep 1)
    @State private var target: Double = 80         // kg
    @State private var rate: Double = 0.5          // % of body weight a week (always positive)
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 0: intro
                case 1: goalStep
                default: review
                }
            }
            .pageBackground()
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle(step == 0 ? "" : "Edit Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { if step == 0 { dismiss() } else { animate { step -= 1 } } } label: {
                        Image(systemName: step == 0 ? "xmark" : "chevron.left")
                    }
                }
            }
        }
        .appStyle()
        #if os(macOS)
        .frame(width: 520, height: 760)
        #endif
        .onAppear(perform: load)
    }

    // MARK: Numbers

    private var unit: WeightUnit { profiles.first?.weight ?? .kg }
    private var energy: EnergyUnit { profiles.first?.energy ?? .kcal }
    private var current: Double { trendSeries(weights.map { DayValue(day: $0.day, value: $0.trendKg) }, through: dayKey()).last?.trend ?? 80 }
    private var goal: GoalType { abs(target - current) < 0.5 ? .maintain : target < current ? .lose : .gain }
    private var expenditure: Double { ctx.expenditureEstimates().last?.kcal ?? ctx.targets()?.expenditure ?? 2500 }
    private var weeklyKg: Double { weeklyChangeKg(goal: goal, ratePercent: rate, weightKg: current) }

    private var budget: Targets {
        let g = ctx.activeProgram
        return makeTargets(expenditure: expenditure, weightKg: current, sex: profiles.first?.sexValue ?? .male, goal: goal,
                           ratePercent: goal == .maintain ? 0 : rate, diet: g?.dietValue ?? .balanced, protein: g?.proteinValue ?? .high,
                           body: ctx.bodyInfo(guardrails: (g?.mode ?? "coached") == "coached"))
    }

    private var endDate: Date? {
        goal == .maintain ? nil : goalDate(trendKg: current, goalKg: target, weeklyKg: weeklyKg)
    }

    private var rateName: String {
        switch goal {
        case .lose: return rate < 0.35 ? "Gentle" : rate <= 0.75 ? "Standard (Recommended)" : "Aggressive"
        case .gain: return rate <= 0.15 ? "Lean (Recommended)" : rate <= 0.3 ? "Moderate" : "Aggressive"
        case .maintain: return "Maintenance"
        }
    }

    private var rateRange: ClosedRange<Double> { goal == .gain ? 0.05...0.5 : 0.1...1.25 }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(colors: [palette.calories, palette.carbs.mix(with: palette.calories, by: 0.4)], startPoint: .top, endPoint: .bottom)
                Circle().fill(palette.fat.gradient).frame(width: 190).offset(y: -40)
                Image(systemName: "scalemass.fill").font(.system(size: 90)).foregroundStyle(.white.opacity(0.9)).offset(y: 70)
            }
            .frame(height: 340).clipped()
            VStack(alignment: .leading, spacing: 18) {
                Text("EDIT GOAL").font(.pageTitle(32))
                stepRow(1, "Edit goal", "Modify goal weight and rate of weight change", on: true)
                stepRow(2, "Set new program", "Targets from your current expenditure", on: false)
            }
            .padding(20)
            Spacer()
            primary("Edit Goal Parameters") { animate { step = 1 } }
        }
        .ignoresSafeArea(edges: .top)
    }

    private func stepRow(_ n: Int, _ title: String, _ detail: String, on: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)").font(.headline).frame(width: 36, height: 36)
                .background(on ? Color.primary : Color.raisedBackground, in: Circle())
                .foregroundStyle(on ? (palette.scheme == .dark ? Color.black : .white) : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(on ? .primary : .secondary)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Step 1

    private var goalStep: some View {
        VStack(spacing: 0) {
            progress(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(spacing: 10) {
                        tile(energy.format(budget.kcal), "initial daily budget", palette.good.opacity(0.18))
                        tile(endDate.map { $0.formatted(.dateTime.day().month(.abbreviated).year().locale(appLocale)) } ?? (goal == .maintain ? "Ongoing" : "–"),
                             "projected end date", Color.raisedBackground)
                    }
                    Text("What is your target weight?").font(.title3.weight(.bold))
                    VStack(spacing: 8) {
                        Text(unit.format(target, digits: 1)).font(.number(26, weight: .semibold)).monospacedDigit()
                        WeightRuler(kg: $target, unit: unit, current: current)
                    }
                    if goal != .maintain {
                        Text("What is your target goal rate?").font(.title3.weight(.bold))
                        VStack(spacing: 14) {
                            Text(rateName).font(.headline).padding(.horizontal, 14).padding(.vertical, 8)
                                .background(palette.good.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                            Slider(value: $rate, in: rateRange, step: 0.01).tint(palette.good)
                            if goal == .lose, (ctx.activeProgram?.mode ?? "coached") == "coached",
                               let floor = ctx.bodyInfo(guardrails: true)?.floorKcal, budget.kcal <= floor + 5 {
                                Label("At this rate the budget hits your calorie floor (\(energy.format(floor))), so it can't go lower. Pick a slower rate, or change the floor in Strategy.",
                                      systemImage: "shield.lefthalf.filled").font(.caption).foregroundStyle(palette.warn)
                            }
                            rateRow(perWeek: true)
                            rateRow(perWeek: false)
                        }
                    } else {
                        Text("Your target is your current weight: maintenance. Calories match your expenditure.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            primary("Next") { animate { step = 2 } }
        }
    }

    private func rateRow(perWeek: Bool) -> some View {
        let k = perWeek ? 1.0 : 30.0 / 7
        let sign = goal == .lose ? "−" : "+"
        return HStack(spacing: 10) {
            Text(sign).frame(width: 14)
            numField(Binding(get: { unit.fromKg(abs(weeklyKg) * k) },
                             set: { v in rate = min(max(unit.toKg(v) / k / current * 100, rateRange.lowerBound), rateRange.upperBound) }),
                     unit.rawValue)
            numField(Binding(get: { rate * k }, set: { v in rate = min(max(v / k, rateRange.lowerBound), rateRange.upperBound) }), "%")
            Text(perWeek ? "Per Week" : "Per Month").font(.subheadline).frame(width: 82, alignment: .leading)
        }
    }

    private func numField(_ value: Binding<Double>, _ suffix: String) -> some View {
        HStack {
            TextField("", value: value, format: .number.precision(.fractionLength(0...2)).locale(appLocale))
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .monospacedDigit()
            Text(suffix).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).frame(height: 46)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.2)))
    }

    private func tile(_ value: String, _ label: String, _ bg: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(bg, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Step 2

    private var review: some View {
        let p = profiles.first, g = ctx.activeProgram
        let oldGoal = p?.goalWeightKg
        let oldRate = g.map { $0.goalValue == .maintain ? 0 : $0.ratePercent } ?? 0
        return VStack(spacing: 0) {
            progress(1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Edits to your goal").font(.title2.bold())
                    card(goal == .lose ? "Weight Loss" : goal == .gain ? "Weight Gain" : "Maintenance",
                         "\(unit.format(current)) » \(unit.format(target))",
                         oldGoal.map { abs($0 - target) < 0.05 && g?.goalValue == goal ? "No Change" : "Was \(unit.format($0))" } ?? "New", highlight: true)
                    card("Goal Rate", goal == .maintain ? "0% BW per week" : "\(goal == .lose ? "−" : "+")\(number(rate, digits: 2))% BW per week",
                         abs(oldRate - (goal == .maintain ? 0 : rate)) < 0.005 && g?.goalValue == goal ? "No Change" : "Was \(number(oldRate, digits: 2))% a week")
                    card("Initial Daily Budget", energy.format(budget.kcal),
                         "Estimated from your current expenditure (\(energy.format(expenditure))). Your expenditure changes with your diet, activity and more; each week's check-in adjusts your plan to it.")
                    card("Estimated End Date", endDate.map { $0.formatted(.dateTime.day().month(.abbreviated).year().locale(appLocale)) } ?? "–",
                         "An optimistic estimate if your expenditure stayed perfectly stable and you hit every target. Plan for a few more weeks than this.")
                    card("Start Date", Date().formatted(.dateTime.day().month(.abbreviated).year().locale(appLocale)),
                         "A new program starts today from your current expenditure. The coaching algorithm doesn't reset.")
                }
                .padding(20)
            }
            primary("Done", save)
        }
    }

    private func card(_ title: String, _ value: String, _ note: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(value).font(.headline.weight(.regular)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(16)
            .background(highlight ? palette.good.opacity(0.18) : Color.raisedBackground)
            Text(note).font(.subheadline).foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(highlight ? palette.good.opacity(0.4) : palette.stroke))
    }

    // MARK: Shared

    private func progress(_ v: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.raisedBackground)
                Capsule().fill(Color.primary).frame(width: geo.size.width * v)
            }
        }
        .frame(height: 4).padding(.horizontal, 20).animation(Motion.snappy, value: v)
    }

    private func primary(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: 54) }
            .buttonStyle(PadButtonStyle(kind: .primary))
            .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        target = profiles.first?.goalWeightKg ?? current
        if let g = ctx.activeProgram, g.goalValue != .maintain { rate = g.ratePercent }
        else { rate = goal == .gain ? 0.25 : 0.5 }
    }

    private func save() {
        guard let p = profiles.first else { return }
        let g = ctx.activeProgram
        p.goalWeightKg = goal == .maintain ? nil : target
        ctx.startProgram(goal: goal, ratePercent: goal == .maintain ? 0 : rate, diet: g?.dietValue ?? .balanced, protein: g?.proteinValue ?? .high,
                         weightKg: current, expenditure: expenditure, sex: p.sexValue, reason: "goal")
        p.phaseEnd = goal == .maintain ? "" : "kg:\(target)"
        ctx.commit()
        dismiss()
    }
}

/// A horizontal ruler you drag to pick a weight (0,1 steps), coloured towards the goal.
struct WeightRuler: View {
    @Binding var kg: Double
    let unit: WeightUnit
    let current: Double
    @State private var start: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, perUnit: CGFloat = 20           // points per kg (or lb)
            let value = unit.fromKg(kg), cur = unit.fromKg(current)
            Canvas { c, size in
                let lo = Int((value - Double(w / 2 / perUnit)).rounded(.down)) - 1, hi = Int((value + Double(w / 2 / perUnit)).rounded(.up)) + 1
                // the stretch between now and the target
                let x0 = w / 2 + CGFloat(cur - value) * perUnit
                c.fill(Path(CGRect(x: min(x0, w / 2), y: 40, width: abs(x0 - w / 2), height: size.height - 40)), with: .color(palette.good.opacity(0.3)))
                for i in (lo * 2)...(hi * 2) {
                    let v = Double(i) / 2
                    let x = w / 2 + CGFloat(v - value) * perUnit
                    let major = i % 10 == 0
                    c.fill(Path(CGRect(x: x, y: major ? 40 : 52, width: 1, height: size.height - (major ? 40 : 52))), with: .color(.secondary.opacity(major ? 0.9 : 0.45)))
                    if major {
                        c.draw(Text("\(Int(v))").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: x, y: 26))
                    }
                }
                c.fill(Path(CGRect(x: w / 2 - 1, y: 18, width: 2.5, height: size.height - 18)), with: .color(palette.good))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture()
                .onChanged { g in
                    if start == nil { start = value }
                    let v = (start! - Double(g.translation.width / perUnit) * 1).rounded(toPlaces: 1)
                    kg = unit.toKg(min(max(v, 30), 400))
                }
                .onEnded { _ in start = nil })
        }
        .frame(height: 96)
        .sensoryFeedback(.selection, trigger: Int(unit.fromKg(kg) * 2))
    }
}

private extension Double {
    func rounded(toPlaces n: Int) -> Double { let m = pow(10, Double(n)); return (self * m).rounded() / m }
}
