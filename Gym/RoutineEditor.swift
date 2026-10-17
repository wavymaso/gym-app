import Charts
import SwiftData
import SwiftUI
import UserNotifications

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
                        VStack(alignment: .leading, spacing: Space.s) {
                            HStack {
                                Text(ctx.exercise(item.exerciseKey)?.name ?? "?").font(.cardTitle)
                                Spacer()
                                Button(role: .destructive) { items.removeAll { $0.id == item.id } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless)
                            }
                            HStack(spacing: Space.l) {
                                Stepper("\(item.sets) sets", value: $item.sets, in: 1...10)
                                Stepper("\(item.repLow)–\(item.repHigh) reps", onIncrement: { item.repLow += 1; item.repHigh += 1 },
                                        onDecrement: { if item.repLow > 1 { item.repLow -= 1; item.repHigh -= 1 } })
                                Picker("Rest", selection: $item.rest) {
                                    ForEach([30, 60, 90, 120, 150, 180, 240, 300], id: \.self) { Text(clock($0)).tag($0) }
                                }
                                .frame(maxWidth: 140)
                            }
                            .font(.secondaryText)
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
                        .foregroundStyle(w == weeks.last ? palette.accent : palette.accent.opacity(0.55)).cornerRadius(Radius.xs)
                }
                .numberYAxis(digits: 1)
                .chartYAxisLabel("Volume, t")
                .dayTip("Week of", days: weeks, format: .dateTime.day().month(.abbreviated)) { w in
                    [TipRow(label: "Volume", value: "\(number(unit.fromKg(volume[w] ?? 0) / 1000, digits: 1)) t", color: palette.accent)]
                }
                .chartSummary("Weekly training volume, last 12 weeks", weeks.map { unit.fromKg(volume[$0] ?? 0) / 1000 }) { "\(number($0, digits: 1)) tonnes" }
                .frame(height: 130)
                Divider()
                ForEach(Array(top), id: \.key) { key, rows in
                    let recent = rows.filter { $0.day >= cut }.map { estimatedOneRepMax(kg: $0.kg, reps: $0.reps) }.max()
                    let before = rows.filter { $0.day < cut }.map { estimatedOneRepMax(kg: $0.kg, reps: $0.reps) }.max()
                    HStack {
                        VStack(alignment: .leading, spacing: Space.hairline) {
                            Text(ctx.exercise(key)?.name ?? "Exercise").font(.secondaryEmphasis).lineLimit(1)
                            Text("\(rows.count) sets").font(.note).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let r = recent {
                            Text("\(number(unit.fromKg(r), digits: 1)) \(unit.rawValue)").font(.secondaryEmphasis).monospacedDigit()
                        }
                        if let r = recent, let b = before, b > 0 {
                            let pct = (r - b) / b * 100
                            Delta(text: (pct >= 0 ? "+" : "−") + "\(number(abs(pct), digits: 1))%", good: abs(pct) < 0.5 ? nil : pct > 0)
                        } else {
                            Text("new").font(.note).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Estimated 1-rep max: best of the last 4 weeks, against the 8 weeks before.").font(.note).foregroundStyle(.secondary)
            }
        }
    }

    private func mondayOf(_ day: String) -> String {
        let n = dayNumber(day)
        return dayKey(number: n - ((n + 3) % 7 + 7) % 7)
    }
}

/// Your own weekly set ranges per muscle (start: enough to grow; end: about what you recover from).
struct VolumeRangesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var ranges: [String: [Double]] = UserDefaults.standard.dictionary(forKey: "volumeRanges") as? [String: [Double]] ?? [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Muscle.allCases.filter { $0 != .cardio && $0 != .fullBody }) { m in
                        let r = ranges[m.rawValue] ?? [volumeRange(m).lowerBound, volumeRange(m).upperBound]
                        HStack {
                            Text(m.label)
                            Spacer()
                            Stepper("\(Int(r[0]))", value: Binding(get: { r[0] }, set: { ranges[m.rawValue] = [min($0, r[1]), r[1]] }), in: 0...30)
                                .fixedSize()
                            Text("–")
                            Stepper("\(Int(r[1]))", value: Binding(get: { r[1] }, set: { ranges[m.rawValue] = [r[0], max($0, r[0])] }), in: 0...40)
                                .fixedSize()
                        }
                    }
                } footer: {
                    Text("Working sets a week. Start low and raise the top end while you still recover between sessions; drop it if performance falls. Helper muscles count as half a set.")
                }
                Button("Back to the defaults", role: .destructive) { ranges = [:] }
            }
            .themedForm()
            .navigationTitle("Volume ranges")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { UserDefaults.standard.set(ranges, forKey: "volumeRanges"); dismiss() }
                }
            }
        }
        .appStyle()
        #if os(macOS)
        .frame(width: 460, height: 600)
        #endif
    }
}
