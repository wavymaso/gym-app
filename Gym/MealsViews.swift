import SwiftData
import SwiftUI

// Day notes and saved meals on screen (models in Meals.swift).

/// The note and "partially logged" switch under a day's food.
struct DayNoteCard: View {
    let day: String
    @Environment(\.modelContext) private var ctx
    @Query private var notes: [DayNote]
    @State private var text = ""
    @FocusState private var focused: Bool

    init(day: String) {
        self.day = day
        _notes = Query(filter: #Predicate<DayNote> { $0.day == day })
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Partially logged").font(.subheadline.weight(.semibold))
                    Text("Leaves this day out of your expenditure, so a patchy day can't skew it.").font(.caption).foregroundStyle(.secondary)
                }
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
            Text("Save a meal from the food log (its + menu → Save as meal) to log it here in one tap.").font(.callout).foregroundStyle(.secondary)
        }
        ForEach(meals.sorted { ($0.useCount, $0.name) > ($1.useCount, $1.name) }) { m in
            Button { pick(m) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name).font(.body.weight(.medium))
                        Text(m.items.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(energy.format(m.total.kcal)).font(.body.weight(.semibold)).monospacedDigit()
                        MacroLine(n: m.total)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { Button("Delete meal", role: .destructive) { ctx.delete(m); ctx.commit() } }
        }
    }
}
