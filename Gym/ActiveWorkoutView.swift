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
    @State private var restNext = ""
    @State private var restSet = ""
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
                ForEach(groups, id: \.key) { order, rows in
                    if let ex = ctx.exercise(rows[0].exerciseKey) {
                        ExerciseBlock(exercise: ex, rows: rows, workout: workout, unit: unit, records: records,
                                      onDone: { row in tick(row) },
                                      addSet: { addSet(to: rows) },
                                      remove: { removeExercise(order) })
                    }
                }
                Button { picking = true } label: {
                    Label("Add exercise", systemImage: "plus").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(pagePadding)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        .undoToast()
        .onChange(of: sets.filter(\.done).count) { old, new in if new > old { Haptics.tap() } }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 0)
                .onChange(of: restEnds) { _, e in
                    #if os(iOS)
                    RestLive.show(ends: e, total: restTotal, workout: workout.name, next: restNext, setText: restSet)
                    #endif
                }
            if let restEnds {
                RestBar(ends: restEnds, total: restTotal) { e in animate(Motion.snappy) { self.restEnds = e } }
                    .padding(.horizontal, pagePadding).padding(.bottom, 8)
                    .frame(maxWidth: 860)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $picking) {
            ExercisePicker { key in
                ctx.addExercise(key, to: workout, order: (sets.map(\.exerciseOrder).max() ?? -1) + 1)
                ctx.commit()
            }
        }
        .confirmationDialog("Discard this workout? Nothing from it is kept.", isPresented: $confirmDiscard) {
            Button("Discard workout", role: .destructive) { ctx.discard(workout) }
        }
    }

    private var header: some View {
        let unit = profiles.first?.weight ?? .kg
        let done = sets.filter(\.done)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                TextField("Workout name", text: Binding(get: { workout.name }, set: { workout.name = $0; ctx.commit() }))
                    .font(.number(isPhone ? 26 : 30)).textFieldStyle(.plain)
                Spacer()
                Menu {
                    Button("Discard workout…", role: .destructive) { confirmDiscard = true }
                } label: {
                    Image(systemName: "ellipsis").font(.body.weight(.bold)).frame(width: 34, height: 34)
                        .background(Color.raisedBackground, in: Circle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                Button { ctx.finish(workout) } label: { Text("Finish").font(.headline).padding(.horizontal, 6) }
                    .buttonStyle(.borderedProminent).tint(palette.good).controlSize(.large)
                    .disabled(done.isEmpty)
            }
            HStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    stat(clock(workout.duration), "Time", color: palette.accent)
                }
                Spacer()
                stat("\(done.count)/\(sets.count)", "Sets", color: palette.good)
                Spacer()
                stat("\(number(unit.fromKg(volume(done.map(\.lift)))))", "Volume \(unit.rawValue)", color: Macro.fat.color)
                Spacer()
                stat("\(records.values.filter { !$0.isEmpty }.count)", "PRs", color: Macro.protein.color)
            }
        }
        .padding(16)
        .modifier(CardSurface(cornerRadius: 20))
    }

    private func stat(_ value: String, _ label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.number(20)).monospacedDigit().foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func tick(_ row: WorkoutSet) {
        row.done.toggle()
        if row.done {
            let before = ctx.history(of: row.exerciseKey, excluding: workout.key).map(\.lift)
                + sets.filter { $0.done && $0.exerciseKey == row.exerciseKey && $0.persistentModelID != row.persistentModelID }.map(\.lift)
            records[row.persistentModelID] = newRecords(row.lift, before: before)
            // No rest in the middle of a superset (go straight to the next exercise) or between a left and a right set.
            let groupOrders = row.group > 0 ? Set(sets.filter { $0.group == row.group }.map(\.exerciseOrder)).sorted() : []
            let midSuperset = row.group > 0 && row.exerciseOrder != groupOrders.last
            if midSuperset || row.side == "L" {
                restEnds = nil
            } else {
                restTotal = row.restSeconds
                let same = sets.filter { $0.exerciseKey == row.exerciseKey && $0.kindValue != .warmup }.sorted { $0.setOrder < $1.setOrder }
                let doneCount = same.filter(\.done).count
                if let nextOpen = sets.filter({ !$0.done }).sorted(by: { ($0.exerciseOrder, $0.setOrder) < ($1.exerciseOrder, $1.setOrder) }).first {
                    restNext = ctx.exercise(nextOpen.exerciseKey)?.name ?? ""
                } else { restNext = "" }
                restSet = "\(ctx.exercise(row.exerciseKey)?.name ?? "") set \(doneCount) of \(same.count) done"
                restEnds = Date().addingTimeInterval(TimeInterval(row.restSeconds))
            }
        } else {
            records[row.persistentModelID] = nil
        }
        ctx.commit()
    }

    private func addSet(to rows: [WorkoutSet]) {
        guard let last = rows.last else { return }
        for (i, side) in (last.side.isEmpty ? [""] : ["L", "R"]).enumerated() {          // tracking sides: add a pair
            let s = WorkoutSet(workoutKey: workout.key, exerciseKey: last.exerciseKey, exerciseOrder: last.exerciseOrder,
                               setOrder: last.setOrder + 1 + i, kg: last.kg, reps: last.reps, restSeconds: last.restSeconds, day: workout.day)
            s.side = side; s.group = last.group
            ctx.insert(s)
        }
        ctx.commit()
    }

    private func removeExercise(_ order: Int) {
        for s in sets where s.exerciseOrder == order { ctx.delete(s) }
        ctx.commit()
    }
}

/// One exercise: a row per set.
private struct ExerciseBlock: View {
    let exercise: Exercise
    let rows: [WorkoutSet]
    let workout: Workout
    var workoutKey: String { workout.key }
    let unit: WeightUnit
    let records: [PersistentIdentifier: [String]]
    let onDone: (WorkoutSet) -> Void
    let addSet: () -> Void
    let remove: () -> Void
    @Environment(\.modelContext) private var ctx
    @State private var plates = false

    var body: some View {
        let previous = ctx.previousSets(of: exercise.key, before: workoutKey).filter { $0.kindValue.counts }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(String(exercise.name.prefix(1))).font(.headline).foregroundStyle(palette.accent)
                    .frame(width: 34, height: 34).background(palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name).font(.headline)
                    Text("\(exercise.muscleValue.label) · \(rows.filter(\.done).count)/\(rows.count) sets").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if exercise.equipmentValue == .barbell {
                    Button { plates = true } label: {
                        Label("Plates", systemImage: "line.3.horizontal.decrease").font(.caption.weight(.semibold))
                            .labelStyle(isPhone ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                    }
                        .buttonStyle(.bordered).controlSize(.small).help("Plates to load")
                        .popover(isPresented: $plates) {
                            PlateCalculator(kg: rows.first { !$0.done }?.kg ?? rows.last?.kg ?? 20, unit: unit).appStyle()
                        }
                }
                Menu {
                    Button { ctx.addWarmUps(exerciseKey: exercise.key, order: rows[0].exerciseOrder, to: workout) } label: {
                        Label("Add warm-up sets", systemImage: "flame")
                    }
                    .disabled(rows.contains { $0.kindValue == .warmup })
                    Menu {
                        ForEach(ctx.alternatives(to: exercise.key).prefix(12)) { alt in
                            Button("\(alt.name) · \(alt.equipmentValue.label)") { ctx.swap(order: rows[0].exerciseOrder, in: workout, to: alt.key) }
                        }
                    } label: { Label("Swap for…", systemImage: "arrow.triangle.2.circlepath") }
                    .disabled(rows.contains(where: \.done))
                    if rows[0].group > 0 {
                        Button { ctx.leaveSuperset(order: rows[0].exerciseOrder, in: workout) } label: { Label("Leave superset", systemImage: "link.badge.plus") }
                    } else {
                        Button { ctx.supersetWithNext(order: rows[0].exerciseOrder, in: workout) } label: { Label("Superset with next", systemImage: "link") }
                    }
                    if rows.allSatisfy({ $0.side.isEmpty }) {
                        Button { ctx.trackSides(order: rows[0].exerciseOrder, in: workout) } label: { Label("Track left & right", systemImage: "arrow.left.and.right") }
                    }
                    Divider()
                    Button {
                        // Busy gym, sore joint: drop what's left of it today; the routine keeps it.
                        for r in rows where !r.done { ctx.delete(r) }
                        ctx.commit()
                    } label: { Label("Skip the rest today", systemImage: "forward.end") }
                    .disabled(rows.allSatisfy(\.done))
                    Button("Remove exercise", role: .destructive, action: remove)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            }
            if rows[0].group > 0 {
                Label("Superset \(String(UnicodeScalar(64 + min(rows[0].group, 26))!)) · rest after the last exercise", systemImage: "link")
                    .font(.caption.weight(.bold)).foregroundStyle(supersetColor)
            }
            TextField("Note",
                      text: Binding(get: { workout.notesByExercise[exercise.key] ?? "" },
                                    set: { v in var n = workout.notesByExercise; n[exercise.key] = v.isEmpty ? nil : v; workout.notesByExercise = n }),
                      prompt: Text(ctx.lastNote(for: exercise.key, before: workoutKey).map { "Last time: \($0)" } ?? "Note (seat height, grip, how it felt…)")
                        .foregroundStyle(.secondary),
                      axis: .vertical)
                .font(.callout).lineLimit(1...3).textFieldStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color.raisedBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                .onSubmit { ctx.commit() }
            if let t = target, !rows.contains(where: \.done) {
                Label {
                    Text("\(t.kg > 0 ? "\(trimmed(unit.fromKg(t.kg))) \(unit.rawValue) × " : "")\(repsText(t.reps)) · \(t.reason)")
                } icon: { Image(systemName: "arrow.up.right.circle.fill") }
                .font(.caption.weight(.semibold)).foregroundStyle(palette.good)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(palette.good.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            Grid(alignment: .leading, horizontalSpacing: isPhone ? 10 : 14, verticalSpacing: 8) {
                GridRow {
                    Text("Set"); Text("Previous"); Text(unit.rawValue); Text("Reps")
                    Text("RIR").frame(width: isPhone ? 34 : 44)
                    Text("")
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    let working = rows.prefix(i + 1).filter { $0.kindValue.counts }.count
                    GridRow {
                        Menu {
                            ForEach(SetKind.allCases, id: \.self) { k in
                                Button(k.label) { row.kind = k.rawValue; ctx.commit() }
                            }
                            Divider()
                            Button("Delete set", role: .destructive) { ctx.deleteWithUndo([row], "Set deleted") }
                        } label: {
                            Text((row.kindValue == .normal ? "\(row.side == "R" ? working - 1 : working)" : row.kindValue.short) + row.side)
                                .fontWeight(.semibold).frame(width: 26)
                                .foregroundStyle(row.kindValue == .warmup ? Macro.fat.color : row.kindValue == .normal ? Color.primary : Macro.protein.color)
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        Text(previousText(previous, workingIndex: working - 1, row: row))
                            .foregroundStyle(.secondary).monospacedDigit().frame(minWidth: isPhone ? 60 : 90, alignment: .leading)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        DecimalField(value: Binding(get: { unit.fromKg(row.kg) }, set: { row.kg = unit.toKg($0); ctx.commitSoon() }), digits: 2)
                            .frame(width: isPhone ? 64 : 70)
                        DecimalField(value: Binding(get: { Double(row.reps) }, set: { row.reps = max(0, Int($0.rounded())); ctx.commitSoon() }), digits: 0)
                            .frame(width: isPhone ? 44 : 50)
                        if isPhone {
                            // Reps in reserve: one tap picks it (it makes progression and e1RM honest).
                            Menu {
                                Button("–") { row.rir = nil; ctx.commit() }
                                ForEach([0, 1, 2, 3, 4, 5], id: \.self) { v in Button("\(v)\(v == 0 ? " (failure)" : "")") { row.rir = Double(v); ctx.commit() } }
                            } label: {
                                Text(row.rir.map { number($0) } ?? "–").font(.callout.weight(.semibold)).monospacedDigit()
                                    .frame(width: 34, height: 34).background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: 9))
                            }
                            .menuStyle(.button).buttonStyle(.plain)
                        } else {
                            DecimalField(value: Binding(get: { row.rir ?? -1 }, set: { row.rir = $0 < 0 ? nil : $0; ctx.commitSoon() }), digits: 1, emptyBelowZero: true)
                                .frame(width: 44)
                        }
                        HStack(spacing: 6) {
                            Button { animate(Motion.snappy) { onDone(row) } } label: {
                                Image(systemName: "checkmark").font(.callout.weight(.heavy))
                                    .foregroundStyle(row.done ? .white : .secondary)
                                    .frame(width: 32, height: 28)
                                    .background(row.done ? palette.good : Color.raisedBackground, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            if let r = records[row.persistentModelID], !r.isEmpty {
                                Label(r.joined(separator: " · "), systemImage: "trophy.fill").font(.caption).foregroundStyle(Macro.fat.color)
                            }
                        }
                    }
                    .foregroundStyle(row.done ? palette.good : .primary)
                }
            }
            Button(action: addSet) {
                Label("Add set", systemImage: "plus").font(.callout.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .modifier(CardSurface())
        .overlay { if rows[0].group > 0 { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(supersetColor.opacity(0.7), lineWidth: 2) } }
    }

    private var supersetColor: Color { [Macro.fat.color, Macro.carbs.color, Color(hex: 0xA78BFA), Macro.protein.color][(max(rows[0].group, 1) - 1) % 4] }

    /// Today's aim from last time (double progression in the routine's rep range).
    private var target: Progression? {
        let prev = ctx.previousSets(of: exercise.key, before: workoutKey).filter { $0.kindValue.counts }
        guard !prev.isEmpty else { return nil }
        let (lo, hi) = ctx.repRange(exercise.key, routineKey: workout.routineKey)
        return nextTarget(previous: prev.map(\.lift), repLow: lo, repHigh: hi, step: weightStep(exercise.equipmentValue))
    }

    private func repsText(_ r: [Int]) -> String {
        Set(r).count == 1 ? "\(r.count)×\(r[0])" : r.map(String.init).joined(separator: "/")
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
            .textFieldStyle(.plain)
            .padding(.horizontal, 8).frame(height: 34)
            .background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(focused ? palette.accent : .clear, lineWidth: 1.5))
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
            let color = left > 0 ? palette.accent : palette.good
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(color.opacity(0.2), lineWidth: 5)
                    Circle().trim(from: 0, to: total > 0 ? Double(left) / Double(total) : 0)
                        .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: left)
                    Image(systemName: left > 0 ? "timer" : "checkmark").font(.callout.weight(.bold)).foregroundStyle(color)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(left > 0 ? clock(left) : "Go!").font(.number(24)).monospacedDigit()
                    Text(left > 0 ? "Rest" : "Rest over, next set").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("−15") { change(ends.addingTimeInterval(-15)) }.buttonStyle(.bordered)
                Button("+15") { change(ends.addingTimeInterval(15)) }.buttonStyle(.bordered)
                Button { change(nil) } label: { Image(systemName: "xmark") }.buttonStyle(.bordered)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(color.opacity(0.5), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .onChange(of: left == 0) { _, over in if over && !rang { rang = true; ring() } }
        }
    }

    private func ring() {
        #if os(macOS)
        NSSound(named: "Glass")?.play()
        #else
        AudioServicesPlaySystemSound(1005)
        Haptics.success()
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
            .themedList()
            .searchable(text: $query, prompt: "Search exercises")
            .navigationTitle("Add exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem { Button("New exercise…") { creating = true } }
            }
            .sheet(isPresented: $creating) { NewExerciseView { pick($0); dismiss() } }
        }
        .appStyle()                             // sheets don't inherit these on the Mac
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
            .themedForm()
            .navigationTitle("New exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let e = Exercise(key: "custom:\(UUID().uuidString)", name: name.trimmingCharacters(in: .whitespaces), muscle: muscle,
                                         equipment: equipment, isCustom: true)
                        ctx.insert(e); ctx.commit()
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

/// Which plates to put on each side of the bar for a weight.
struct PlateCalculator: View {
    let kg: Double
    let unit: WeightUnit
    @AppStorage("barKg") private var bar: Double = 20
    @AppStorage("platesAvailable") private var available = "25,20,15,10,5,2.5,1.25"

    static let plates: [Double] = [25, 20, 15, 10, 5, 2.5, 2, 1.25, 1, 0.5]
    private var have: [Double] { available.split(separator: ",").compactMap { Double($0) }.sorted(by: >) }

    var body: some View {
        let side = Self.perSide(total: kg, bar: bar, plates: have)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(trimmed(unit.fromKg(kg))) \(unit.rawValue)").font(.number(26))
                Text("on a \(trimmed(bar)) kg bar").foregroundStyle(.secondary)
            }
            if side.plates.isEmpty {
                Text(kg <= bar ? "Just the bar." : "Can't make this exactly.").foregroundStyle(.secondary)
            } else {
                HStack(alignment: .center, spacing: 3) {
                    Rectangle().fill(.secondary).frame(width: 30, height: 8)
                    ForEach(Array(side.plates.enumerated()), id: \.offset) { _, p in
                        RoundedRectangle(cornerRadius: 3).fill(color(p))
                            .frame(width: p >= 10 ? 14 : 10, height: 34 + p * 2.6)
                            .overlay { Text(trimmed(p)).font(.system(size: 8, weight: .bold)).rotationEffect(.degrees(-90)).foregroundStyle(.white).fixedSize() }
                    }
                }
                .frame(height: 104)
                Text("Each side: " + side.plates.map { trimmed($0) }.joined(separator: " + ") + " kg").font(.callout.weight(.semibold))
                if side.left > 0.01 { Text("\(trimmed(side.left * 2)) kg short of the target").font(.caption).foregroundStyle(palette.warn) }
            }
            Picker("Bar", selection: $bar) {
                Text("20 kg bar").tag(20.0); Text("15 kg bar").tag(15.0); Text("10 kg bar").tag(10.0)
            }
            .pickerStyle(.segmented).labelsHidden()
            VStack(alignment: .leading, spacing: 6) {
                Text("Plates at your gym").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    ForEach(Self.plates, id: \.self) { p in
                        let on = have.contains(p)
                        Button(trimmed(p)) {
                            var set = Set(have); if on { set.remove(p) } else { set.insert(p) }
                            available = set.sorted(by: >).map { trimmed($0).replacingOccurrences(of: ",", with: ".") }.joined(separator: ",")
                        }
                        .font(.caption2.weight(.bold)).buttonStyle(.plain)
                        .frame(minWidth: 24).padding(.vertical, 5)
                        .background(on ? palette.accent : Color.raisedBackground, in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(on ? .white : .secondary)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 340)
        .presentationCompactAdaptation(.popover)
    }

    static func perSide(total: Double, bar: Double, plates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]) -> (plates: [Double], left: Double) {
        var left = max(0, (total - bar) / 2)
        var out: [Double] = []
        for p in plates.sorted(by: >) { while left >= p - 0.001 { out.append(p); left -= p } }
        return (out, left)
    }

    private func color(_ p: Double) -> Color {
        switch p {
        case 25: return Color(hex: 0xE5383B)
        case 20: return Color(hex: 0x3A6FF7)
        case 15: return Color(hex: 0xF2C12E)
        case 10: return Color(hex: 0x2BB673)
        case 5: return Color(hex: 0xF5F5F5).mix(with: .gray, by: 0.3)
        default: return Color(hex: 0x6B6B76)
        }
    }
}
