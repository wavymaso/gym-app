import Charts
import SwiftData
import SwiftUI
import UserNotifications

/// Straight after finishing: how the workout went, and any records.
struct WorkoutSummary: View {
    let workout: Workout
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]

    var body: some View {
        let unit = profiles.first?.weight ?? .kg
        let sets = ctx.sets(of: workout.key).filter(\.done)
        let prs = records(sets)
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.l) {
                    Image(systemName: "checkmark.seal.fill").font(.iconHero).foregroundStyle(palette.good)
                        .padding(.top, Space.m)
                    Text("Workout complete").font(.numberLarge)
                    Text(workout.name).font(.cardTitle).foregroundStyle(.secondary)
                    HStack(spacing: Space.m) {
                        tile(clock(workout.duration), "Time", palette.accent)
                        tile("\(sets.filter { $0.kindValue.counts }.count)", "Sets", palette.good)
                        tile(number(unit.fromKg(volume(sets.map(\.lift)))), "Volume \(unit.rawValue)", Macro.fat.color)
                    }
                    if !prs.isEmpty {
                        Card(title: "New records", systemImage: "trophy.fill") {
                            ForEach(prs, id: \.0) { name, what in
                                HStack {
                                    Text(name).font(.bodyEmphasis)
                                    Spacer()
                                    Text(what.joined(separator: " · ")).font(.secondaryText).foregroundStyle(Macro.fat.color)
                                }
                            }
                        }
                    }
                }
                .padding(pagePadding)
            }
            .pageBackground()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .appStyle()
        #if os(macOS)
        .frame(width: 480, height: 520)
        #endif
    }

    private func tile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: Space.xxs) {
            Text(value).font(.numberMedium).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.note).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Space.l)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.l))
    }

    /// Per exercise, the records set today (best of each kind).
    private func records(_ sets: [WorkoutSet]) -> [(String, [String])] {
        var out: [(String, [String])] = []
        for (key, rows) in Dictionary(grouping: sets, by: \.exerciseKey) {
            let before = ctx.history(of: key, excluding: workout.key).map(\.lift)
            var found: [String] = []
            var earlier: [LiftSet] = []
            for r in rows.sorted(by: { $0.setOrder < $1.setOrder }) {
                for rec in newRecords(r.lift, before: before + earlier) where !found.contains(rec) { found.append(rec) }
                earlier.append(r.lift)
            }
            if !found.isEmpty, let name = ctx.exercise(key)?.name { out.append((name, found)) }
        }
        return out.sorted { $0.0 < $1.0 }
    }
}

struct WorkoutRow: View {
    let workout: Workout
    let unit: WeightUnit
    @Environment(\.modelContext) private var ctx

    var body: some View {
        let sets = ctx.sets(of: workout.key)
        HStack {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(workout.name).font(.cardTitle)
                Text(workout.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(appLocale)))
                    .font(.note).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Space.xxs) {
                Text("\(clock(workout.duration)) · \(sets.filter { $0.kindValue.counts }.count) sets").monospacedDigit()
                Text("\(number(unit.fromKg(volume(sets.map(\.lift))))) \(unit.rawValue) volume").font(.note).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Working sets per muscle this week (Monday to Sunday). Around 10–20 a week per muscle is a common target.
struct WeekCard: View {
    @Environment(\.modelContext) private var ctx
    @Query private var all: [WorkoutSet]
    @State private var editingRanges = false

    init() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let monday = dayKey(cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date())
        _all = Query(filter: #Predicate<WorkoutSet> { $0.day >= monday && $0.done })
    }

    var body: some View {
        let counts = setsPerMuscle(all.compactMap { s in
            ctx.exercise(s.exerciseKey).map { ($0.muscleValue, $0.secondaryValues, s.kindValue) }
        })
        let rows = Muscle.allCases.filter { (counts[$0] ?? 0) > 0 && $0 != .cardio }
        Card(title: "This week", systemImage: "calendar",
             accessory: AnyView(Button("Ranges") { editingRanges = true }.buttonStyle(.borderless).font(.label))) {
            if rows.isEmpty {
                Text("Sets you finish this week show up here by muscle. Helper muscles count as half a set.")
                    .font(.secondaryText).foregroundStyle(.secondary)
            } else {
                let top = max(20, rows.map { counts[$0] ?? 0 }.max() ?? 0)
                VStack(spacing: Space.m) {
                    ForEach(rows) { m in
                        let n = counts[m] ?? 0
                        HStack(spacing: Space.m) {
                            Text(m.label).font(.secondaryText).frame(width: isPhone ? 86 : 110, alignment: .leading).lineLimit(1)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.raisedBackground)
                                    // This muscle's growth range (volumeRange, adjustable)
                                    let r = volumeRange(m)
                                    Rectangle().fill(palette.good.opacity(0.12)).frame(width: g.size.width * (r.upperBound - r.lowerBound) / top)
                                        .offset(x: g.size.width * r.lowerBound / top)
                                    Capsule().fill(n >= r.lowerBound ? (n > r.upperBound ? palette.protein : palette.good) : palette.accent)
                                        .frame(width: max(8, g.size.width * min(n, top) / top))
                                }
                                .clipShape(Capsule())
                            }
                            .frame(height: 10)
                            Text(number(n, digits: n.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)).font(.secondaryEmphasis).monospacedDigit()
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }
                Text("Working sets; helper muscles count as half. Shaded: each muscle's growth range (tap Ranges to fit how you recover).").font(.note).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $editingRanges) { VolumeRangesSheet() }
    }
}

/// A finished workout, set by set.
struct WorkoutDetail: View {
    let workout: Workout
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]
    @State private var confirmDelete = false

    var body: some View {
        let unit = profiles.first?.weight ?? .kg
        let groups = Dictionary(grouping: ctx.sets(of: workout.key), by: \.exerciseOrder).sorted { $0.key < $1.key }
        NavigationStack {
            List {
                Section {
                    LabeledContent("Date", value: workout.start.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(appLocale)))
                    LabeledContent("Duration", value: clock(workout.duration))
                }
                ForEach(groups, id: \.key) { _, rows in
                    Section(ctx.exercise(rows[0].exerciseKey)?.name ?? "Exercise") {
                        ForEach(rows) { s in
                            HStack {
                                Text(s.kindValue == .normal ? "" : s.kindValue.label).font(.note).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                                Text("\(trimmed(unit.fromKg(s.kg))) \(unit.rawValue) × \(s.reps)").monospacedDigit()
                                if let rir = s.rir { Text("RIR \(number(rir, digits: 1))").font(.note).foregroundStyle(.secondary) }
                                Spacer()
                                Text("e1RM \(number(unit.fromKg(estimatedOneRepMax(kg: s.kg, reps: s.reps)), digits: 1))")
                                    .font(.note).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .themedList()
            .navigationTitle(workout.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) { Button("Delete", role: .destructive) { confirmDelete = true } }
            }
            .confirmationDialog("Delete this workout from your history?", isPresented: $confirmDelete) {
                Button("Delete workout", role: .destructive) { ctx.discard(workout); dismiss() }
            }
        }
        .appStyle()                             // sheets don't inherit these on the Mac
        #if os(macOS)
        .frame(width: 520, height: 600)
        #endif
    }
}
