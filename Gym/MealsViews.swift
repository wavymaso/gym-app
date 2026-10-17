import SwiftData
import SwiftUI

// Day notes and saved meals on screen (models in Meals.swift).

/// The note and "partially logged" switch under a day's food.
struct DayNoteCard: View {
    let day: String
    @Environment(\.modelContext) private var ctx
    @Query private var notes: [DayNote]
    @State private var text = ""
    @State private var estimate = ""
    @FocusState private var focused: Bool
    @Query private var entries: [FoodEntry]

    init(day: String) {
        self.day = day
        _notes = Query(filter: #Predicate<DayNote> { $0.day == day })
        _entries = Query(filter: #Predicate<FoodEntry> { $0.day == day })
    }

    var body: some View {
        let n = notes.first
        Card(title: "Day note", systemImage: "note.text") {
            TextField("Ate out, felt ill, travel day…", text: $text, axis: .vertical)
                .lineLimit(1...4).focused($focused).textFieldStyle(.plain)
                .onSubmit(save)
                .onChange(of: focused) { _, f in if !f { save() } }
            Toggle(isOn: Binding(get: { n?.partial ?? false }, set: { v in
                let note = n ?? { let x = DayNote(day: day); ctx.insert(x); return x }()
                note.partial = v; ctx.commit()
            })) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Partially logged").font(.secondaryEmphasis)
                    Text("Leaves this day out of your expenditure, so a patchy day can't skew it.").font(.note).foregroundStyle(.secondary)
                }
            }
            Toggle(isOn: Binding(get: { n?.waterEvent ?? false }, set: { v in
                let note = n ?? { let x = DayNote(day: day); ctx.insert(x); return x }()
                note.waterEvent = v; ctx.commit()
            })) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Water event").font(.secondaryEmphasis)
                    Text("Very salty or carb-heavy day, started creatine, travel, illness: the next weigh-ins count less towards expenditure.").font(.note).foregroundStyle(.secondary)
                }
            }
            if n?.partial == true {
                let logged = entries.reduce(0) { $0 + $1.nutrients.kcal }
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Better: guess the whole day").font(.secondaryEmphasis)
                    HStack {
                        TextField("e.g. \(number(max(logged * 1.4, 1800)))", text: $estimate).textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        Text("kcal").foregroundStyle(.secondary)
                        Button("Fill in") {
                            if let v = parseNumber(estimate), v > 0 { ctx.estimateDay(day, totalKcal: v); estimate = "" }
                        }
                        .buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent).disabled((parseNumber(estimate) ?? 0) <= logged)
                    }
                    Text("You've logged \(number(logged)) kcal. The rest goes in as one estimate and the day counts again. A rough guess is fine: for a 3000 kcal day, anything from 2100 to 3900 keeps your expenditure honest.")
                        .font(.note).foregroundStyle(.secondary)
                }
                .padding(.top, Space.xs)
            }
        }
        .onAppear { text = n?.text ?? "" }
        .onChange(of: day) { _, _ in text = notes.first?.text ?? "" }
    }

    private func save() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = notes.first {
            guard n.text != t else { return }
            n.text = t
        } else {
            guard !t.isEmpty else { return }
            ctx.insert(DayNote(day: day, text: t))
        }
        ctx.commit()
    }
}

/// Saved meals list for the add-food screen.
struct SavedMealsList: View {
    let pick: (SavedMeal) -> Void
    let energy: EnergyUnit
    @Environment(\.modelContext) private var ctx
    @Query(sort: \SavedMeal.name) private var meals: [SavedMeal]

    var body: some View {
        if meals.isEmpty {
            Text("Save a meal from the food log (its + menu → Save as meal) to log it here in one tap.").font(.secondaryText).foregroundStyle(.secondary)
        }
        ForEach(meals.sorted { ($0.useCount, $0.name) > ($1.useCount, $1.name) }) { m in
            Button { pick(m) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(m.name).font(.bodyEmphasis)
                        Text(m.items.map(\.name).joined(separator: ", ")).font(.note).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Space.xxs) {
                        Text(energy.format(m.total.kcal)).font(.bodyEmphasis).monospacedDigit()
                        MacroLine(n: m.total)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { Button("Delete meal", role: .destructive) { ctx.deleteWithUndo([m], "\(m.name) deleted") } }
        }
    }
}
