import SwiftData
import SwiftUI

/// How much of a food, and when. Used for logging, editing an entry, and recipe ingredients.
struct FoodAmountView: View {
    @Environment(\.pickTitle) private var pickTitle
    let food: Food
    let mode: AddFoodView.Mode
    var entry: FoodEntry?
    var done: () -> Void

    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @State private var amountText = ""
    @State private var unit = "g"
    @State private var time = Date()
    @State private var loaded = false

    var body: some View {
        let energy = profiles.first?.energy ?? .kcal
        let n = food.nutrients(amount, unit: unit)
        Form {
            Section {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(food.name).font(.subsectionTitle)
                    if let b = food.brand { Text(b).foregroundStyle(.secondary) }
                }
                HStack {
                    TextField("Amount", text: $amountText).frame(maxWidth: 110)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Picker("", selection: $unit) { ForEach(food.units, id: \.self) { Text(unitLabel($0)).tag($0) } }
                        .labelsHidden()
                }
                if case .log = mode { DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute) }
                if entry != nil { DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute) }
            }
            Section("Nutrition") {
                HStack(alignment: .firstTextBaseline) {
                    Text(energy.format(n.kcal)).font(.sectionTitle).monospacedDigit()
                    Spacer()
                    Text("\(number(food.grams(amount, unit: unit))) \(food.baseUnit)").foregroundStyle(.secondary)
                }
                HStack(spacing: Space.xl) {
                    ForEach([Macro.protein, .fat, .carbs], id: \.self) { m in
                        VStack(alignment: .leading) {
                            Text("\(number(m.value(n.targets), digits: 1)) g").font(.cardTitle).monospacedDigit()
                            Label(m.label, systemImage: "circle.fill").labelStyle(DotLabel(color: m.color)).font(.note).foregroundStyle(.secondary)
                        }
                    }
                }
                detail("Fibre", n.fiber, "g")
                detail("Sugar", n.sugar, "g")
                detail("Saturated fat", n.satFat, "g")
                detail("Sodium", n.sodium, "mg")
            }
        }
        .themedForm()
        .navigationTitle(entry == nil ? "How much?" : "Edit entry")
        .toolbar {
            ToolbarItem {
                Button { food.isFavorite.toggle(); ctx.commit() } label: {
                    Label("Favourite", systemImage: food.isFavorite ? "star.fill" : "star")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(buttonTitle, action: commit).disabled(amount <= 0).keyboardShortcut(.defaultAction)
            }
        }
        .onAppear(perform: load)
    }

    private var amount: Double { parseNumber(amountText) ?? 0 }

    private var buttonTitle: String {
        if entry != nil { return "Save" }
        if case .pick = mode { return pickTitle }
        return "Add"
    }

    private func unitLabel(_ u: String) -> String {
        guard let s = food.servings.first(where: { $0.name == u }) else { return u }
        return "\(s.name) · \(number(s.grams)) \(food.baseUnit)"
    }

    @ViewBuilder private func detail(_ label: String, _ v: Double?, _ unit: String) -> some View {
        if let v { LabeledContent(label, value: "\(number(v, digits: unit == "mg" ? 0 : 1)) \(unit)") }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let e = entry {
            amountText = number(e.amount, digits: e.amount == e.amount.rounded() ? 0 : 1)
            unit = food.units.contains(e.unit) ? e.unit : food.baseUnit
            time = e.time
        } else {
            let (a, u) = food.suggestedAmount
            amountText = number(a, digits: a == a.rounded() ? 0 : 1)
            unit = u
            if case .log(let day, let at) = mode { time = at ?? defaultTime(for: day) }
        }
    }

    private func commit() {
        if let e = entry {
            e.amount = amount; e.unit = unit; e.grams = food.grams(amount, unit: unit); e.nutrients = food.nutrients(amount, unit: unit)
            e.time = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: time),
                                           minute: Calendar.current.component(.minute, from: time), second: 0, of: date(fromKey: e.day)) ?? time
            ctx.commit()
        } else {
            switch mode {
            case .log(let day, _):
                let t = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: time),
                                              minute: Calendar.current.component(.minute, from: time), second: 0, of: date(fromKey: day)) ?? time
                ctx.log(food, amount: amount, unit: unit, day: day, time: t)
            case .pick(let hand):
                hand(food, food.grams(amount, unit: unit))
            }
        }
        done()
    }
}

/// Editing a logged entry (its food may since have been deleted: then grams only).
struct EntryEditor: View {
    let entry: FoodEntry
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            FoodDetailView(food: food, day: entry.day, initial: (entry.amount, entry.unit),
                           primary: ("Save", { a, u in save(a, u) }),
                           alreadyToday: ctx.entries(on: entry.day).filter { $0.id != entry.id }.reduce(.zero) { $0 + $1.nutrients },
                           time: $time)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) { dismiss(); ctx.deleteWithUndo([entry], "\(entry.name) removed") }
                    }
                }
        }
        .appStyle()                             // sheets don't inherit these on the Mac
        #if os(macOS)
        .frame(width: 560, height: 720)
        #endif
        .onAppear { if !loaded { loaded = true; time = entry.time } }
    }

    private func save(_ amount: Double, _ unit: String) {
        let f = food
        entry.amount = amount; entry.unit = unit; entry.grams = f.grams(amount, unit: unit); entry.nutrients = f.nutrients(amount, unit: unit)
        let c = Calendar.current
        entry.time = c.date(bySettingHour: c.component(.hour, from: time), minute: c.component(.minute, from: time), second: 0,
                            of: date(fromKey: entry.day)) ?? time
        ctx.commit()
        dismiss()
    }

    private var food: Food {
        if let k = entry.foodKey, let f = ctx.food(key: k) { return f }
        let per100 = entry.grams > 0 ? entry.nutrients.scaled(100 / entry.grams) : entry.nutrients
        return Food(key: entry.foodKey ?? "deleted", name: entry.name, brand: entry.brand, source: "custom", per100: per100)
    }
}
