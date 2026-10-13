import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#else
import AudioToolbox
#endif

/// The workout you're doing now: sets per exercise, last time's numbers, a rest timer.
struct ActiveWorkoutView: View {
    let workout: Workout
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @Query private var sets: [WorkoutSet]
    @State private var restEnds: Date?
    @State private var restTotal = 120
    @State private var picking = false
    @State private var confirmDiscard = false
    @State private var records: [PersistentIdentifier: [String]] = [:]

    init(workout: Workout) {
        self.workout = workout
        let key = workout.key
        _sets = Query(filter: #Predicate<WorkoutSet> { $0.workoutKey == key },
                      sort: [SortDescriptor(\WorkoutSet.exerciseOrder), SortDescriptor(\WorkoutSet.setOrder)])
    }

    var body: some View {
        let unit = profiles.first?.weight ?? .kg
        let groups = Dictionary(grouping: sets, by: \.exerciseOrder).sorted { $0.key < $1.key }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let restEnds { RestBar(ends: restEnds, total: restTotal) { self.restEnds = $0 } }
                ForEach(groups, id: \.key) { order, rows in
                    if let ex = ctx.exercise(rows[0].exerciseKey) {
                        ExerciseBlock(exercise: ex, rows: rows, workoutKey: workout.key, unit: unit, records: records,
                                      onDone: { row in tick(row) },
                                      addSet: { addSet(to: rows) },
                                      remove: { removeExercise(order) })
                    }
                }
                Button { picking = true } label: { Label("Add exercise", systemImage: "plus") }
                    .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.pageBackground)
        .sheet(isPresented: $picking) {
            ExercisePicker { key in
                ctx.addExercise(key, to: workout, order: (sets.map(\.exerciseOrder).max() ?? -1) + 1)
                try? ctx.save()
            }
        }
        .confirmationDialog("Discard this workout? Nothing from it is kept.", isPresented: $confirmDiscard) {
            Button("Discard workout", role: .destructive) { ctx.discard(workout) }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Workout name", text: Binding(get: { workout.name }, set: { workout.name = $0; try? ctx.save() }))
                    .font(.title.bold()).textFieldStyle(.plain)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text("\(clock(workout.duration)) · \(sets.filter(\.done).count) sets done")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Discard", role: .destructive) { confirmDiscard = true }
            Button("Finish") { ctx.finish(workout) }
                .buttonStyle(.borderedProminent).disabled(!sets.contains(where: \.done))
        }
        .controlSize(.large)
    }

    private func tick(_ row: WorkoutSet) {
        row.done.toggle()
        if row.done {
            let before = ctx.history(of: row.exerciseKey, excluding: workout.key).map(\.lift)
                + sets.filter { $0.done && $0.exerciseKey == row.exerciseKey && $0.persistentModelID != row.persistentModelID }.map(\.lift)
            records[row.persistentModelID] = newRecords(row.lift, before: before)
            restTotal = row.restSeconds
            restEnds = Date().addingTimeInterval(TimeInterval(row.restSeconds))
        } else {
            records[row.persistentModelID] = nil
        }
        try? ctx.save()
    }

    private func addSet(to rows: [WorkoutSet]) {
        guard let last = rows.last else { return }
        ctx.insert(WorkoutSet(workoutKey: workout.key, exerciseKey: last.exerciseKey, exerciseOrder: last.exerciseOrder,
                              setOrder: last.setOrder + 1, kg: last.kg, reps: last.reps, restSeconds: last.restSeconds, day: workout.day))
        try? ctx.save()
    }

    private func removeExercise(_ order: Int) {
        for s in sets where s.exerciseOrder == order { ctx.delete(s) }
        try? ctx.save()
    }
}

/// One exercise: a row per set.
private struct ExerciseBlock: View {
    let exercise: Exercise
    let rows: [WorkoutSet]
    let workoutKey: String
    let unit: WeightUnit
    let records: [PersistentIdentifier: [String]]
    let onDone: (WorkoutSet) -> Void
    let addSet: () -> Void
    let remove: () -> Void
    @Environment(\.modelContext) private var ctx

    var body: some View {
        let previous = ctx.previousSets(of: exercise.key, before: workoutKey).filter { $0.kindValue.counts }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name).font(.headline)
                    Text(exercise.muscleValue.label).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Remove exercise", role: .destructive, action: remove)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text("Set"); Text("Previous"); Text(unit.rawValue); Text("Reps"); Text("RIR"); Text("")
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    let working = rows.prefix(i + 1).filter { $0.kindValue.counts }.count
                    GridRow {
                        Menu {
                            ForEach(SetKind.allCases, id: \.self) { k in
                                Button(k.label) { row.kind = k.rawValue; try? ctx.save() }
                            }
                            Divider()
                            Button("Delete set", role: .destructive) { ctx.delete(row); try? ctx.save() }
                        } label: {
                            Text(row.kindValue == .normal ? "\(working)" : row.kindValue.short)
                                .fontWeight(.semibold).frame(width: 26)
                                .foregroundStyle(row.kindValue == .warmup ? Macro.fat.color : row.kindValue == .normal ? Color.primary : Macro.protein.color)
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        Text(previousText(previous, workingIndex: working - 1, row: row))
                            .foregroundStyle(.secondary).monospacedDigit().frame(minWidth: 90, alignment: .leading)
                        DecimalField(value: Binding(get: { unit.fromKg(row.kg) }, set: { row.kg = unit.toKg($0); try? ctx.save() }), digits: 2)
                            .frame(width: 70)
                        DecimalField(value: Binding(get: { Double(row.reps) }, set: { row.reps = max(0, Int($0.rounded())); try? ctx.save() }), digits: 0)
                            .frame(width: 50)
                        DecimalField(value: Binding(get: { row.rir ?? -1 }, set: { row.rir = $0 < 0 ? nil : $0; try? ctx.save() }), digits: 1, emptyBelowZero: true)
                            .frame(width: 44)
                        HStack(spacing: 6) {
                            Button { onDone(row) } label: {
                                Image(systemName: row.done ? "checkmark.circle.fill" : "circle").font(.title3)
                                    .foregroundStyle(row.done ? Macro.carbs.color : .secondary)
                            }
                            .buttonStyle(.plain)
                            if let r = records[row.persistentModelID], !r.isEmpty {
                                Label(r.joined(separator: " · "), systemImage: "trophy.fill").font(.caption).foregroundStyle(Macro.fat.color)
                            }
                        }
                    }
                    .opacity(row.done ? 0.75 : 1)
                }
            }
            Button(action: addSet) { Label("Add set", systemImage: "plus") }.buttonStyle(.borderless).font(.callout)
        }
        .padding(16)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.06)))
    }

    private func previousText(_ prev: [WorkoutSet], workingIndex: Int, row: WorkoutSet) -> String {
        guard row.kindValue.counts, prev.indices.contains(workingIndex) else { return "–" }
        let p = prev[workingIndex]
        return "\(trimmed(unit.fromKg(p.kg))) × \(p.reps)"
    }
}

/// A number field that accepts "62,5" or "62.5" and saves when you leave it or press return.
struct DecimalField: View {
    @Binding var value: Double
    var digits = 1
    var emptyBelowZero = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(emptyBelowZero ? "–" : "0"))
            .multilineTextAlignment(.trailing).monospacedDigit().focused($focused)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
            .onAppear(perform: load)
            .onChange(of: value) { _, _ in if !focused { load() } }
            .onChange(of: focused) { _, f in if !f { commit() } }
            .onSubmit(commit)
    }

    private func load() {
        if emptyBelowZero && value < 0 { text = ""; return }
        text = value == 0 && !emptyBelowZero ? "" : trimmed(value, digits: digits)
    }

    private func commit() {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { value = emptyBelowZero ? -1 : 0; return }
        if let v = parseNumber(text) { value = v }
        load()
    }
}

/// Rest countdown, with ±15 s and skip. Rings once when time's up.
struct RestBar: View {
    let ends: Date
    let total: Int
    let change: (Date?) -> Void
    @State private var rang = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let left = max(0, Int(ends.timeIntervalSince(ctx.date).rounded(.up)))
            HStack(spacing: 14) {
                Image(systemName: "timer").font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(left > 0 ? "Rest \(clock(left))" : "Rest over — next set").font(.headline).monospacedDigit()
                    ProgressView(value: Double(total - left), total: Double(max(total, 1)))
                }
                Button("−15 s") { change(ends.addingTimeInterval(-15)) }
                Button("+15 s") { change(ends.addingTimeInterval(15)) }
                Button(left > 0 ? "Skip" : "Close") { change(nil) }
            }
            .padding(14)
            .background((left > 0 ? Macro.calories.color : Macro.carbs.color).opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
            .onChange(of: left == 0) { _, over in if over && !rang { rang = true; ring() } }
        }
    }

    private func ring() {
        #if os(macOS)
        NSSound(named: "Glass")?.play()
        #else
        AudioServicesPlaySystemSound(1005)
        #endif
    }
}

/// Choose an exercise from the library (or make one).
struct ExercisePicker: View {
    let pick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var query = ""
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(Muscle.allCases) { m in
                    let rows = filtered.filter { $0.muscleValue == m }
                    if !rows.isEmpty {
                        Section(m.label) {
                            ForEach(rows) { e in
                                Button { pick(e.key); dismiss() } label: {
                                    HStack {
                                        Text(e.name)
                                        Spacer()
                                        Text(e.equipmentValue.label).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search exercises")
            .navigationTitle("Add exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem { Button("New exercise…") { creating = true } }
            }
            .sheet(isPresented: $creating) { NewExerciseView { pick($0); dismiss() } }
        }
        .environment(\.locale, appLocale)       // sheets don't inherit it on the Mac
        #if os(macOS)
        .frame(width: 480, height: 620)
        #endif
    }

    private var filtered: [Exercise] {
        let words = FoodAPI.fold(query).split(separator: " ").map(String.init)
        return words.isEmpty ? exercises : exercises.filter { e in words.allSatisfy { FoodAPI.fold(e.name).contains($0) } }
    }
}

struct NewExerciseView: View {
    var created: (String) -> Void = { _ in }
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var muscle = Muscle.chest
    @State private var equipment = Equipment.barbell

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Main muscle", selection: $muscle) { ForEach(Muscle.allCases) { Text($0.label).tag($0) } }
                Picker("Equipment", selection: $equipment) { ForEach(Equipment.allCases) { Text($0.label).tag($0) } }
            }
            .formStyle(.grouped)
            .navigationTitle("New exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let e = Exercise(key: "custom:\(UUID().uuidString)", name: name.trimmingCharacters(in: .whitespaces), muscle: muscle,
                                         equipment: equipment, isCustom: true)
                        ctx.insert(e); try? ctx.save()
                        dismiss(); created(e.key)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 260)
        #endif
    }
}
