import Charts
import SwiftData
import SwiftUI

/// Start a workout (empty or from a routine), see this week's training, and your history.
/// While a workout is going, this page shows it.
struct WorkoutsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<Workout> { $0.end == nil }) private var active: [Workout]
    @Query(filter: #Predicate<Workout> { $0.end != nil }, sort: \Workout.start, order: .reverse) private var finished: [Workout]
    @Query(sort: \Routine.order) private var routines: [Routine]
    @Query private var profiles: [Profile]
    @State private var editingRoutine: Routine?
    @State private var newRoutine = false
    @State private var showing: Workout?

    @State private var summary: Workout?
    @State private var lastActiveKey: String?

    var body: some View {
        Group {
            if let w = active.first {
                ActiveWorkoutView(workout: w).navigationTitle("Workout")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            } else {
                overview
            }
        }
        .onChange(of: active.first?.key, initial: true) { old, new in
            // A workout just finished: show how it went.
            if new == nil, let k = lastActiveKey, let w = finished.first(where: { $0.key == k }) { summary = w }
            lastActiveKey = new
        }
        .sheet(item: $summary) { WorkoutSummary(workout: $0) }
    }

    private var nextRoutine: Routine? {
        guard !routines.isEmpty else { return nil }
        if let lastKey = finished.first(where: { $0.routineKey != nil })?.routineKey, let i = routines.firstIndex(where: { $0.key == lastKey }) {
            return routines[(i + 1) % routines.count]
        }
        return routines.first
    }

    private var overview: some View {
        let unit = profiles.first?.weight ?? .kg
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                if !routines.isEmpty {
                    HStack {
                        Text("Routines").font(.title3.bold())
                        Spacer()
                        Button { newRoutine = true } label: { Label("New", systemImage: "plus") }.buttonStyle(.bordered).controlSize(.small)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: isPhone ? 150 : 190), spacing: 12)], spacing: 12) {
                        ForEach(routines) { r in routineCard(r) }
                    }
                }
                WeekCard()
                StrengthCard(unit: unit)
                if finished.isEmpty {
                    ContentUnavailableView("No workouts yet", systemImage: "dumbbell",
                                           description: Text("Start an empty workout, or make a routine like Push / Pull / Legs first."))
                } else {
                    Text("History").font(.title3.bold()).padding(.top, 4)
                    let months = Dictionary(grouping: finished.prefix(120), by: { monthKey($0.start) }).sorted { $0.key > $1.key }
                    ForEach(months, id: \.key) { _, ws in
                        Card(title: ws[0].start.formatted(.dateTime.month(.wide).year().locale(appLocale)), systemImage: "calendar",
                             accessory: AnyView(Text("\(ws.count) workouts").font(.caption).foregroundStyle(.secondary))) {
                            ForEach(ws) { w in
                                Button { showing = w } label: { WorkoutRow(workout: w, unit: unit) }.buttonStyle(.plain)
                                if w.id != ws.last?.id { Divider() }
                            }
                        }
                    }
                }
            }
            .padding(pagePadding)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .debugScrollAnchor()
        .pageBackground()
        .navigationTitle("Workouts")
        .sheet(item: $editingRoutine) { RoutineEditor(routine: $0) }
        .sheet(isPresented: $newRoutine) { RoutineEditor(routine: nil) }
        .sheet(item: $showing) { WorkoutDetail(workout: $0) }
    }

    /// The big "start" card: your next routine, or an empty workout.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let r = nextRoutine {
                Text("UP NEXT").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.white.opacity(0.75))
                Text(r.name).font(.number(34)).foregroundStyle(.white)
                Text(routineSummary(r)).font(.callout).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                HStack(spacing: 10) {
                    Button { ctx.startWorkout(routine: r) } label: {
                        Label("Start \(r.name)", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    Button { ctx.startWorkout(routine: nil) } label: {
                        Text("Empty").font(.headline).padding(.horizontal, 18).padding(.vertical, 12)
                            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("READY WHEN YOU ARE").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.white.opacity(0.75))
                Text("Start training").font(.number(34)).foregroundStyle(.white)
                HStack(spacing: 10) {
                    Button { ctx.startWorkout(routine: nil) } label: {
                        Label("Empty workout", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    Button { newRoutine = true } label: {
                        Text("New routine").font(.headline).padding(.horizontal, 18).padding(.vertical, 12)
                            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Macro.protein.color, Macro.protein.color.mix(with: palette.accent, by: 0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func routineCard(_ r: Routine) -> some View {
        let count = routineCount(r)
        let last = finished.first { $0.routineKey == r.key || $0.name == r.name }
        return VStack(alignment: .leading, spacing: 8) {
            Text(r.name).font(.headline).lineLimit(1)
            Text("\(count) exercises").font(.caption).foregroundStyle(.secondary)
            Text(last.map { "Last \(relative($0.day))" } ?? "Not done yet").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Start") { ctx.startWorkout(routine: r) }.buttonStyle(.borderedProminent).controlSize(.small)
                Spacer()
                Button { editingRoutine = r } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(palette.stroke))
        .contextMenu {
            Button("Start") { ctx.startWorkout(routine: r) }
            Button("Edit…") { editingRoutine = r }
        }
    }

    private func routineCount(_ r: Routine) -> Int {
        let key = r.key
        return (try? ctx.fetchCount(FetchDescriptor<RoutineExercise>(predicate: #Predicate { $0.routineKey == key }))) ?? 0
    }

    private func monthKey(_ d: Date) -> String { String(dayKey(d).prefix(7)) }

    private func routineSummary(_ r: Routine) -> String {
        let key = r.key
        let items = (try? ctx.fetch(FetchDescriptor<RoutineExercise>(predicate: #Predicate { $0.routineKey == key }, sortBy: [SortDescriptor(\.order)]))) ?? []
        return items.compactMap { ctx.exercise($0.exerciseKey)?.name }.joined(separator: ", ")
    }
}

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
                VStack(spacing: 18) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(palette.good)
                        .padding(.top, 10)
                    Text("Workout complete").font(.number(28))
                    Text(workout.name).font(.headline).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        tile(clock(workout.duration), "Time", palette.accent)
                        tile("\(sets.filter { $0.kindValue.counts }.count)", "Sets", palette.good)
                        tile(number(unit.fromKg(volume(sets.map(\.lift)))), "Volume \(unit.rawValue)", Macro.fat.color)
                    }
                    if !prs.isEmpty {
                        Card(title: "New records", systemImage: "trophy.fill") {
                            ForEach(prs, id: \.0) { name, what in
                                HStack {
                                    Text(name).font(.body.weight(.medium))
                                    Spacer()
                                    Text(what.joined(separator: " · ")).font(.callout).foregroundStyle(Macro.fat.color)
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
        VStack(spacing: 2) {
            Text(value).font(.number(22)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16))
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
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name).font(.headline)
                Text(workout.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(appLocale)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(clock(workout.duration)) · \(sets.filter { $0.kindValue.counts }.count) sets").monospacedDigit()
                Text("\(number(unit.fromKg(volume(sets.map(\.lift))))) \(unit.rawValue) volume").font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Working sets per muscle this week (Monday to Sunday). Around 10–20 a week per muscle is a common target.
struct WeekCard: View {
    @Environment(\.modelContext) private var ctx
    @Query private var all: [WorkoutSet]

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
        Card(title: "This week", systemImage: "calendar") {
            if rows.isEmpty {
                Text("Sets you finish this week show up here by muscle. Helper muscles count as half a set.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                let top = max(20, rows.map { counts[$0] ?? 0 }.max() ?? 0)
                VStack(spacing: 10) {
                    ForEach(rows) { m in
                        let n = counts[m] ?? 0
                        HStack(spacing: 10) {
                            Text(m.label).font(.callout).frame(width: isPhone ? 86 : 110, alignment: .leading).lineLimit(1)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.raisedBackground)
                                    // 10–20 working sets a week: the usual target zone
                                    Rectangle().fill(palette.good.opacity(0.12)).frame(width: g.size.width * 10 / top).offset(x: g.size.width * 10 / top)
                                    Capsule().fill(n >= 10 ? palette.good : palette.accent).frame(width: max(8, g.size.width * min(n, top) / top))
                                }
                                .clipShape(Capsule())
                            }
                            .frame(height: 10)
                            Text(number(n, digits: n.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)).font(.callout.weight(.semibold)).monospacedDigit()
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }
                Text("Working sets; helper muscles count as half. Shaded: 10–20 a week, a common target.").font(.caption).foregroundStyle(.secondary)
            }
        }
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
                                Text(s.kindValue == .normal ? "" : s.kindValue.label).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                                Text("\(trimmed(unit.fromKg(s.kg))) \(unit.rawValue) × \(s.reps)").monospacedDigit()
                                if let rir = s.rir { Text("RIR \(number(rir, digits: 1))").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Text("e1RM \(number(unit.fromKg(estimatedOneRepMax(kg: s.kg, reps: s.reps)), digits: 1))")
                                    .font(.caption).foregroundStyle(.secondary)
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

/// A routine: exercises in order, with sets, rep range and rest.
struct RoutineEditor: View {
    let routine: Routine?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var items: [Item] = []
    @State private var picking = false
    @State private var confirmDelete = false

    struct Item: Identifiable {
        let id = UUID()
        var exerciseKey: String
        var sets = 3
        var repLow = 8
        var repHigh = 12
        var rest = 120
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Routine name, e.g. Push", text: $name)
                Section("Exercises") {
                    ForEach($items) { $item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(ctx.exercise(item.exerciseKey)?.name ?? "?").font(.headline)
                                Spacer()
                                Button(role: .destructive) { items.removeAll { $0.id == item.id } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless)
                            }
                            HStack(spacing: 14) {
                                Stepper("\(item.sets) sets", value: $item.sets, in: 1...10)
                                Stepper("\(item.repLow)–\(item.repHigh) reps", onIncrement: { item.repLow += 1; item.repHigh += 1 },
                                        onDecrement: { if item.repLow > 1 { item.repLow -= 1; item.repHigh -= 1 } })
                                Picker("Rest", selection: $item.rest) {
                                    ForEach([30, 60, 90, 120, 150, 180, 240, 300], id: \.self) { Text(clock($0)).tag($0) }
                                }
                                .frame(maxWidth: 140)
                            }
                            .font(.callout)
                        }
                    }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    Button { picking = true } label: { Label("Add exercise", systemImage: "plus") }
                }
                if routine != nil {
                    Section { Button("Delete routine", role: .destructive) { confirmDelete = true } }
                }
            }
            .themedForm()
            .navigationTitle(routine == nil ? "New routine" : "Edit routine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || items.isEmpty)
                }
            }
            .sheet(isPresented: $picking) { ExercisePicker { items.append(Item(exerciseKey: $0)) } }
            .confirmationDialog("Delete this routine? Workouts you did with it stay in your history.", isPresented: $confirmDelete) {
                Button("Delete routine", role: .destructive) {
                    if let r = routine { clearItems(r.key); ctx.delete(r); ctx.commit() }
                    dismiss()
                }
            }
        }
        .appStyle()                             // sheets don't inherit these on the Mac
        #if os(macOS)
        .frame(width: 600, height: 620)
        #endif
        .onAppear(perform: load)
    }

    private func load() {
        guard let r = routine, items.isEmpty else { return }
        name = r.name
        let key = r.key
        items = ((try? ctx.fetch(FetchDescriptor<RoutineExercise>(predicate: #Predicate { $0.routineKey == key }, sortBy: [SortDescriptor(\.order)]))) ?? [])
            .map { Item(exerciseKey: $0.exerciseKey, sets: $0.sets, repLow: $0.repLow, repHigh: $0.repHigh, rest: $0.restSeconds) }
    }

    private func clearItems(_ key: String) {
        for old in (try? ctx.fetch(FetchDescriptor<RoutineExercise>(predicate: #Predicate { $0.routineKey == key }))) ?? [] { ctx.delete(old) }
    }

    private func save() {
        let r = routine ?? {
            let r = Routine(name: name, order: (try? ctx.fetchCount(FetchDescriptor<Routine>())) ?? 0)
            ctx.insert(r)
            return r
        }()
        r.name = name.trimmingCharacters(in: .whitespaces)
        clearItems(r.key)
        for (i, item) in items.enumerated() {
            ctx.insert(RoutineExercise(routineKey: r.key, exerciseKey: item.exerciseKey, order: i, sets: item.sets,
                                       repLow: item.repLow, repHigh: item.repHigh, restSeconds: item.rest))
        }
        ctx.commit()
        dismiss()
    }
}

/// Training over the last 12 weeks: volume per week, and your most-trained lifts getting stronger (or not).
struct StrengthCard: View {
    let unit: WeightUnit
    @Environment(\.modelContext) private var ctx
    @Query private var sets: [WorkoutSet]

    init(unit: WeightUnit) {
        self.unit = unit
        let from = addDays(dayKey(), -83)
        _sets = Query(filter: #Predicate<WorkoutSet> { $0.day >= from && $0.done })
    }

    var body: some View {
        let working = sets.filter { $0.kindValue.counts && $0.reps > 0 }
        if working.count >= 6 {
            let weeks = (0..<12).map { i in mondayOf(addDays(dayKey(), -7 * (11 - i))) }
            let volume = Dictionary(grouping: working) { mondayOf($0.day) }.mapValues { $0.reduce(0) { $0 + $1.kg * Double($1.reps) } }
            let top = Dictionary(grouping: working, by: \.exerciseKey).sorted { $0.value.count > $1.value.count }.prefix(5)
            let cut = addDays(dayKey(), -27)
            Card(title: "Strength, last 12 weeks", systemImage: "chart.line.uptrend.xyaxis") {
                Chart(weeks, id: \.self) { w in
                    BarMark(x: .value("Week", date(fromKey: w), unit: .weekOfYear), y: .value("Volume", unit.fromKg(volume[w] ?? 0) / 1000))
                        .foregroundStyle(w == weeks.last ? palette.accent : palette.accent.opacity(0.55)).cornerRadius(4)
                }
                .numberYAxis(digits: 1)
                .chartYAxisLabel("Volume, t")
                .frame(height: 130)
                Divider()
                ForEach(Array(top), id: \.key) { key, rows in
                    let recent = rows.filter { $0.day >= cut }.map { estimatedOneRepMax(kg: $0.kg, reps: $0.reps) }.max()
                    let before = rows.filter { $0.day < cut }.map { estimatedOneRepMax(kg: $0.kg, reps: $0.reps) }.max()
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ctx.exercise(key)?.name ?? "Exercise").font(.callout.weight(.medium)).lineLimit(1)
                            Text("\(rows.count) sets").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let r = recent {
                            Text("\(number(unit.fromKg(r), digits: 1)) \(unit.rawValue)").font(.callout.weight(.semibold)).monospacedDigit()
                        }
                        if let r = recent, let b = before, b > 0 {
                            let pct = (r - b) / b * 100
                            Delta(text: (pct >= 0 ? "+" : "−") + "\(number(abs(pct), digits: 1))%", good: abs(pct) < 0.5 ? nil : pct > 0)
                        } else {
                            Text("new").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Estimated 1-rep max: best of the last 4 weeks, against the 8 weeks before.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func mondayOf(_ day: String) -> String {
        let n = dayNumber(day)
        return dayKey(number: n - ((n + 3) % 7 + 7) % 7)
    }
}
