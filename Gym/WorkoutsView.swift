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

    var body: some View {
        if let w = active.first {
            ActiveWorkoutView(workout: w).navigationTitle("Workout")
        } else {
            overview
        }
    }

    private var overview: some View {
        let unit = profiles.first?.weight ?? .kg
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { ctx.startWorkout(routine: nil) } label: { Label("Start empty workout", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    Button { newRoutine = true } label: { Label("New routine", systemImage: "plus") }
                }
                .controlSize(.large)
                if !routines.isEmpty {
                    Card(title: "Routines", systemImage: "list.bullet.rectangle") {
                        ForEach(routines) { r in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.name).font(.headline)
                                    Text(routineSummary(r)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Button("Edit") { editingRoutine = r }
                                Button("Start") { ctx.startWorkout(routine: r) }.buttonStyle(.borderedProminent)
                            }
                            if r.id != routines.last?.id { Divider() }
                        }
                    }
                }
                WeekCard()
                if finished.isEmpty {
                    ContentUnavailableView("No workouts yet", systemImage: "dumbbell",
                                           description: Text("Start an empty workout, or make a routine like Push / Pull / Legs first."))
                } else {
                    Card(title: "History", systemImage: "clock.arrow.circlepath") {
                        ForEach(finished.prefix(50)) { w in
                            Button { showing = w } label: { WorkoutRow(workout: w, unit: unit) }.buttonStyle(.plain)
                            if w.id != finished.prefix(50).last?.id { Divider() }
                        }
                    }
                }
            }
            .padding(pagePadding)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.pageBackground)
        .navigationTitle("Workouts")
        .sheet(item: $editingRoutine) { RoutineEditor(routine: $0) }
        .sheet(isPresented: $newRoutine) { RoutineEditor(routine: nil) }
        .sheet(item: $showing) { WorkoutDetail(workout: $0) }
    }

    private func routineSummary(_ r: Routine) -> String {
        let key = r.key
        let items = (try? ctx.fetch(FetchDescriptor<RoutineExercise>(predicate: #Predicate { $0.routineKey == key }, sortBy: [SortDescriptor(\.order)]))) ?? []
        return items.compactMap { ctx.exercise($0.exerciseKey)?.name }.joined(separator: ", ")
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
                Chart(rows) { m in
                    BarMark(x: .value("Sets", counts[m] ?? 0), y: .value("Muscle", m.label))
                        .foregroundStyle(Macro.calories.color)
                        .annotation(position: .trailing) { Text(number(counts[m] ?? 0, digits: (counts[m] ?? 0).truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)).font(.caption) }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(rows.count) * 26 + 10)
                Text("Working sets; helper muscles count as half.").font(.caption).foregroundStyle(.secondary)
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
