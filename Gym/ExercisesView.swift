import Charts
import SwiftData
import SwiftUI

/// The exercise library by muscle; each exercise shows your records and progress.
struct ExercisesView: View {
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(filter: #Predicate<WorkoutSet> { $0.done }) private var doneSets: [WorkoutSet]
    @State private var query = ""
    @State private var creating = false
    @State private var onlyDone = false

    var body: some View {
        let done = Set(doneSets.map(\.exerciseKey))
        List {
            ForEach(Muscle.allCases) { m in
                let rows = filtered.filter { $0.muscleValue == m && (!onlyDone || done.contains($0.key)) }
                if !rows.isEmpty {
                    Section(m.label) {
                        ForEach(rows) { e in
                            NavigationLink { ExerciseDetail(exercise: e) } label: {
                                HStack {
                                    Text(e.name)
                                    if done.contains(e.key) { Image(systemName: "chart.line.uptrend.xyaxis").font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                    Text(e.equipmentValue.label).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search exercises")
        .navigationTitle("Exercises")
        .toolbar {
            ToolbarItem { Toggle("Only ones I've done", isOn: $onlyDone) }
            ToolbarItem { Button { creating = true } label: { Label("New exercise", systemImage: "plus") } }
        }
        .sheet(isPresented: $creating) { NewExerciseView() }
    }

    private var filtered: [Exercise] {
        let words = FoodAPI.fold(query).split(separator: " ").map(String.init)
        return words.isEmpty ? exercises : exercises.filter { e in words.allSatisfy { FoodAPI.fold(e.name).contains($0) } }
    }
}

struct ExerciseDetail: View {
    let exercise: Exercise
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @Query private var sets: [WorkoutSet]

    init(exercise: Exercise) {
        self.exercise = exercise
        let key = exercise.key
        _sets = Query(filter: #Predicate<WorkoutSet> { $0.exerciseKey == key && $0.done }, sort: \WorkoutSet.day)
    }

    var body: some View {
        let unit = profiles.first?.weight ?? .kg
        let lifts = sets.map(\.lift)
        let r = records(lifts)
        let byDay = oneRepMaxByDay(lifts)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(exercise.muscleValue.label)\(exercise.secondaryValues.isEmpty ? "" : " · also " + exercise.secondaryValues.map(\.label).joined(separator: ", ")) · \(exercise.equipmentValue.label)")
                    .foregroundStyle(.secondary)
                if lifts.isEmpty {
                    ContentUnavailableView("Not done yet", systemImage: "dumbbell", description: Text("Your records and progress appear after your first workout with it."))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16, alignment: .top)], spacing: 16) {
                        tile("Est. 1RM", r.bestOneRepMax.map { "\(fmt($0.value, unit)) \(unit.rawValue)" } ?? "–", r.bestOneRepMax.map { "from \(setText($0.set, unit))" } ?? "")
                        tile("Heaviest", r.heaviest.map { "\(fmt($0.kg, unit)) \(unit.rawValue)" } ?? "–", r.heaviest.map { "× \($0.reps) · \(when($0.day))" } ?? "")
                        tile("Most reps", r.mostReps.map { "\($0.reps) reps" } ?? "–", r.mostReps.map { "at \(fmt($0.kg, unit)) \(unit.rawValue)" } ?? "")
                        tile("Best set", r.bestSetVolume.map { setText($0, unit) } ?? "–", "Weight × reps")
                    }
                    Card(title: "Estimated 1-rep max", systemImage: "chart.xyaxis.line") {
                        Chart(byDay, id: \.day) { p in
                            LineMark(x: .value("Day", date(fromKey: p.day), unit: .day), y: .value("e1RM", unit.fromKg(p.value)))
                                .foregroundStyle(Macro.calories.color).interpolationMethod(.monotone)
                            PointMark(x: .value("Day", date(fromKey: p.day), unit: .day), y: .value("e1RM", unit.fromKg(p.value)))
                                .foregroundStyle(Macro.calories.color)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 220)
                        Text("The best set of each session, as the weight you could probably lift once.").font(.caption).foregroundStyle(.secondary)
                    }
                    Card(title: "History", systemImage: "list.bullet") {
                        ForEach(Dictionary(grouping: sets, by: \.workoutKey).sorted { $0.value[0].day > $1.value[0].day }.prefix(20), id: \.key) { _, rows in
                            HStack(alignment: .top) {
                                Text(when(rows[0].day)).frame(width: 110, alignment: .leading)
                                Text(rows.sorted { $0.setOrder < $1.setOrder }.map { ($0.kindValue == .warmup ? "W " : "") + setText($0.lift, unit) }.joined(separator: ",  "))
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.pageBackground)
        .navigationTitle(exercise.name)
        .environment(\.locale, appLocale)
    }

    private func fmt(_ kg: Double, _ unit: WeightUnit) -> String {
        trimmed(unit.fromKg(kg))
    }

    private func setText(_ s: LiftSet, _ unit: WeightUnit) -> String { "\(fmt(s.kg, unit)) × \(s.reps)" }

    private func when(_ day: String) -> String { date(fromKey: day).formatted(.dateTime.day().month(.abbreviated).year(.twoDigits).locale(appLocale)) }

    private func tile(_ title: String, _ value: String, _ note: String) -> some View {
        Card(title: title) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
    }
}
