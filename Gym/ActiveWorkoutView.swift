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
                        .background(palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
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
            let pr = newRecords(row.lift, before: before)
            animate(Motion.bouncy) { records[row.persistentModelID] = pr }
            if pr.isEmpty { Haptics.tap() } else { Haptics.record() }
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
                .background(Color.raisedBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.s))
                .onSubmit { ctx.commit() }
            if let t = target, !rows.contains(where: \.done) {
                Label {
                    Text("\(t.kg > 0 ? "\(trimmed(unit.fromKg(t.kg))) \(unit.rawValue) × " : "")\(repsText(t.reps)) · \(t.reason)")
                } icon: { Image(systemName: "arrow.up.right.circle.fill") }
                .font(.caption.weight(.semibold)).foregroundStyle(palette.good)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(palette.good.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.s))
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
                        DecimalField(value: Binding(get: { unit.fromKg(row.kg) }, set: { row.kg = unit.toKg($0); ctx.commitSoon() }), digits: 2,
                                     step: (unit.fromKg(weightStep(exercise.equipmentValue)) * 100).rounded() / 100, onLog: row.done ? nil : { animate(Motion.snappy) { onDone(row) } })
                            .frame(width: isPhone ? 64 : 70)
                        DecimalField(value: Binding(get: { Double(row.reps) }, set: { row.reps = max(0, Int($0.rounded())); ctx.commitSoon() }), digits: 0,
                                     step: 1, onLog: row.done ? nil : { animate(Motion.snappy) { onDone(row) } })
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
                                    .foregroundStyle(row.done ? palette.onData : .secondary)
                                    .frame(width: 32, height: 28)
                                    .background(row.done ? palette.good : Color.raisedBackground, in: RoundedRectangle(cornerRadius: Radius.s))
                            }
                            .buttonStyle(.plain)
                            if let r = records[row.persistentModelID], !r.isEmpty {
                                Label(r.joined(separator: " · "), systemImage: "trophy.fill").font(.caption).foregroundStyle(Macro.fat.color)
                                    .symbolEffect(.bounce, options: .repeat(2), value: r)
                                    .transition(.scale(scale: 0.4, anchor: .leading).combined(with: .opacity))
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

    private var supersetColor: Color { [Macro.fat.color, Macro.carbs.color, Color.extraTone, Macro.protein.color][(max(rows[0].group, 1) - 1) % 4] }

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
