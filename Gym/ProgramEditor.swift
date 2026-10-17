import SwiftData
import SwiftUI

/// MacroFactor's Edit Program (collaborative and manual): the week as columns, pick a day, set its
/// calories, protein (g per kg) and carb-to-fat split. With the lock closed, every day changes together.
struct ProgramEditor: View {
    let mode: String                               // collaborative | manual
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]
    @State private var plan: [Int: Targets] = [:]  // weekday → targets
    @State private var day = 2                     // Monday
    @State private var locked = true
    @State private var loaded = false
    @State private var refused: String?                 // why the last change wasn't allowed

    private let order = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                columns
                Divider()
                ScrollView { editor.padding(Space.xl) }
                Button { save() } label: { Text("Done").font(.cardTitle).frame(maxWidth: .infinity, minHeight: 54) }
                    .buttonStyle(PadButtonStyle(kind: .primary)).padding(.horizontal, Space.xl).padding(.vertical, Space.m)
            }
            .pageBackground()
            .navigationTitle(mode == "manual" ? "Edit Manual Program" : "Edit Collaborative Program")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
        }
        .appStyle()
        #if os(macOS)
        .frame(width: 560, height: 760)
        #endif
        .onAppear(perform: load)
    }

    private var kg: Double { trendSeries(ctx.weightValues, through: dayKey()).last?.trend ?? 80 }
    private var energy: EnergyUnit { profiles.first?.energy ?? .kcal }
    private var t: Targets { plan[day] ?? Targets(kcal: 2000, protein: 150, fat: 60, carbs: 200) }

    // MARK: The week

    private var columns: some View {
        VStack(spacing: Space.m) {
            HStack(spacing: Space.s) {
                ForEach(order, id: \.self) { d in
                    let x = plan[d] ?? t
                    let total = max(x.protein * 4 + x.fat * 9 + x.carbs * 4, 1)
                    VStack(spacing: Space.xs) {
                        Text(number(energy.fromKcal(x.kcal))).font(.label).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                            .padding(.vertical, Space.xs).frame(maxWidth: .infinity).background(palette.calories, in: Capsule()).foregroundStyle(palette.onAccent)
                        block("\(number(x.protein)) P", palette.protein, x.protein * 4 / total)
                        block("\(number(x.fat)) F", palette.fat, x.fat * 9 / total)
                        block("\(number(x.carbs)) C", palette.carbs, x.carbs * 4 / total)
                    }
                    .opacity(locked || d == day ? 1 : 0.55)
                }
            }
            .frame(height: 230)
            HStack(spacing: Space.s) {
                ForEach(order, id: \.self) { d in
                    Button { day = d } label: {
                        Text(String(weekdayName(d).prefix(1))).font(.cardTitle).frame(maxWidth: .infinity, minHeight: 44)
                            .background(d == day ? Color.primary : Color.raisedBackground, in: Capsule())
                            .foregroundStyle(d == day ? palette.onInverse : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.m)
    }

    private func block(_ text: String, _ c: Color, _ share: Double) -> some View {
        Text(text).font(.fineLabel).lineLimit(1).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(c, in: RoundedRectangle(cornerRadius: Radius.xs)).foregroundStyle(palette.onData)
            .layoutPriority(share)
            .frame(minHeight: 22)
    }

    // MARK: The chosen day

    private var editor: some View {
        let protKg = t.protein / kg
        let rest = max(t.kcal - t.protein * 4, 0)
        let carbShare = rest > 0 ? t.carbs * 4 / rest : 0.5
        return VStack(alignment: .leading, spacing: Space.xl) {
            HStack {
                Text(locked ? "Every day" : weekdayName(day)).font(.sectionTitle)
                Spacer()
                Button("Reset All Days") {
                    // Every day the same: the week's calories split evenly, this day's protein and carb/fat split.
                    let avg = roundTo(weekTotal / 7, 1), base = plan[day] ?? t
                    let rest = max(base.kcal - base.protein * 4, 1), share = base.carbs * 4 / rest
                    for d in order { var x = base; x.kcal = avg; x.protein = min(base.protein, avg / 4); split(&x, share); plan[d] = x }
                }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule)
                Button { locked.toggle() } label: { Image(systemName: locked ? "lock.fill" : "lock.open").frame(width: 30, height: 30) }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
                    .help(locked ? "Every day changes together. Unlock to set days separately." : "Each day on its own")
            }
            VStack(alignment: .leading, spacing: Space.s) {
                Text(locked ? "Calories: \(number(energy.fromKcal(weekTotal / 7))) a day on average"
                            : "Calories for \(weekdayName(day)): the other days adjust to keep the week the same").font(.secondaryText)
                Text("Week: \(number(energy.fromKcal(weekTotal))) \(energy.rawValue), set by your goal").font(.note).foregroundStyle(.secondary)
                HStack {
                    TextField("", value: Binding(get: { energy.fromKcal(t.kcal) }, set: { set(kcal: energy.toKcal($0)) }), format: .number.precision(.fractionLength(0)).grouping(.never).locale(appLocale))
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .font(.subsectionTitle).monospacedDigit()
                        .disabled(locked)
                    Text(energy.rawValue).foregroundStyle(.secondary)
                    if locked { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                }
                .padding(.horizontal, Space.l).frame(height: 52)
                .overlay(RoundedRectangle(cornerRadius: Radius.s).stroke(refused == nil ? Color.primary.opacity(0.2) : palette.warn))
                if let refused { Label(refused, systemImage: "exclamationmark.triangle.fill").font(.note).foregroundStyle(palette.warn) }
            }
            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Text("Protein").font(.secondaryText)
                    Spacer()
                    Text("\(number(t.protein)) g · \(number(protKg, digits: 2)) g/kg").font(.secondaryEmphasis).monospacedDigit()
                }
                Slider(value: Binding(get: { protKg }, set: { set(protein: ($0 * kg).rounded()) }), in: 0...min(4, t.kcal / 4 / kg), step: 0.05)
                    .tint(palette.protein)
                if protKg < 1.2 {
                    Label("Below 1,2 g/kg: likely too little to keep muscle while dieting. Most lifters do best at 1,6–2,2.", systemImage: "exclamationmark.triangle.fill")
                        .font(.note).foregroundStyle(palette.warn)
                } else {
                    Text("Between 0 and \(number(min(4, t.kcal / 4 / kg), digits: 2)) g per kg of body weight.").font(.note).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: Space.s) {
                HStack {
                    Text("Carb to Fat Ratio").font(.secondaryText)
                    Spacer()
                    Text("\(Int(carbShare * 100 + 0.5))% carbs").font(.secondaryEmphasis).monospacedDigit()
                }
                Slider(value: Binding(get: { carbShare }, set: { set(carbShare: $0) }), in: 0...1, step: 0.01)
                    .tint(palette.carbs)
                HStack {
                    Text("\(number(t.carbs / kg, digits: 2)) C/kg").foregroundStyle(palette.carbs)
                    Spacer()
                    Text("\(number(t.fat / kg, digits: 2)) F/kg").foregroundStyle(palette.fat)
                }
                .font(.label)
                Text("Carbs as a share of the calories left after protein.").font(.note).foregroundStyle(.secondary)
            }
            if mode == "collaborative" {
                Text("Collaborative: these are your days. Each check-in moves the calories with your expenditure and keeps each day's protein and carb/fat split.")
                    .font(.note).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Changing it

    private func apply(_ f: (inout Targets) -> Void) {
        for d in locked ? order : [day] {
            var x = plan[d] ?? t
            f(&x)
            plan[d] = x
        }
    }

    /// One day's calories, the week's total unchanged: the difference is spread over the other six days.
    /// Never below your calorie floor (Strategy → Calorie floor), for this day or the ones that make up for it.
    private var floorKcal: Double {
        guard let p = profiles.first else { return 1200 }
        return p.calorieFloorKcal > 0 ? p.calorieFloorKcal : calorieFloor(p.sexValue)
    }

    private func set(kcal: Double) {
        guard !locked else { return }
        let old = t.kcal
        let others = order.filter { $0 != day }
        // The highest this day can go while every other day stays at or above the floor.
        let room = others.compactMap { plan[$0]?.kcal }.reduce(0) { $0 + max(0, $1 - floorKcal) }
        var new = min(max(0, kcal), old + room)
        if new < floorKcal {
            new = floorKcal
            refused = "\(number(energy.fromKcal(floorKcal))) \(energy.rawValue) is your calorie floor: a day can't go lower."
        } else if kcal > old + room {
            refused = "The other days would drop below your floor (\(number(energy.fromKcal(floorKcal))) \(energy.rawValue)) to make up for it."
        } else { refused = nil }
        if refused != nil { Haptics.warning() }
        let delta = (new - old) / Double(others.count)
        for d in [day] + others {
            var x = plan[d] ?? t
            let rest = max(x.kcal - x.protein * 4, 1), share = x.carbs * 4 / rest
            x.kcal = d == day ? new : max(0, x.kcal - delta)
            x.protein = min(x.protein, x.kcal / 4)
            split(&x, share)
            plan[d] = x
        }
    }

    private var weekTotal: Double { order.compactMap { plan[$0]?.kcal }.reduce(0, +) }

    private func set(protein: Double) {
        apply { x in
            let rest = max(x.kcal - x.protein * 4, 1), share = x.carbs * 4 / rest
            x.protein = min(protein, x.kcal / 4)
            split(&x, share)
        }
    }

    private func set(carbShare: Double) { apply { split(&$0, carbShare) } }

    private func split(_ x: inout Targets, _ carbShare: Double) {
        let rest = max(x.kcal - x.protein * 4, 0)
        x.carbs = (rest * carbShare / 4).rounded()
        x.fat = (rest * (1 - carbShare) / 9).rounded()
    }

    private func load() {
        guard !loaded, let p = profiles.first else { return }
        loaded = true
        let base = ctx.targets()?.targets ?? Targets(kcal: 2000, protein: 150, fat: 60, carbs: 200)
        var mondayOf = weekStart(dayKey())
        var out: [Int: Targets] = p.weekPlan
        for d in order where out[d] == nil {
            out[d] = ctx.dayTargets(on: mondayOf) ?? p.adjust(base, on: mondayOf)
            mondayOf = addDays(mondayOf, 1)
        }
        plan = out
        locked = Set(order.compactMap { out[$0]?.kcal }).count <= 1
    }

    private func save() {
        guard let p = profiles.first else { return }
        p.weekPlan = plan
        let avg = Targets(kcal: roundTo(order.compactMap { plan[$0]?.kcal }.reduce(0, +) / 7, 10),
                          protein: (order.compactMap { plan[$0]?.protein }.reduce(0, +) / 7).rounded(),
                          fat: (order.compactMap { plan[$0]?.fat }.reduce(0, +) / 7).rounded(),
                          carbs: (order.compactMap { plan[$0]?.carbs }.reduce(0, +) / 7).rounded())
        let exp = ctx.expenditureEstimates().last?.kcal ?? ctx.targets()?.expenditure ?? avg.kcal
        ctx.activeProgram?.mode = mode
        ctx.insert(TargetSet(targets: avg, expenditure: exp, reason: "manual"))
        ctx.commit()
        dismiss()
    }
}
