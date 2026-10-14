import SwiftData
import SwiftUI

/// A number field for nutrition forms: "12,5" or "12.5".
private struct NumberRow: View {
    let label: String
    @Binding var text: String
    var unit: String = "g"
    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField("", text: $text, prompt: Text("0")).multilineTextAlignment(.trailing).frame(maxWidth: 90)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Text(unit).foregroundStyle(.secondary).frame(width: 32, alignment: .leading)
            }
        }
    }
}

private func text(_ v: Double?) -> String {
    guard let v else { return "" }
    return number(v, digits: v == v.rounded() ? 0 : 1)
}

private func time(_ t: Date, on day: String) -> Date {
    let cal = Calendar.current
    return cal.date(bySettingHour: cal.component(.hour, from: t), minute: cal.component(.minute, from: t), second: 0,
                    of: date(fromKey: day)) ?? t
}

// MARK: - Quick add

/// Just calories and macros, when you don't want to find the food.
struct QuickAddView: View {
    let day: String
    let entry: FoodEntry?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var carbs = ""
    @State private var when = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Label (optional)", text: $name)
                Section {
                    NumberRow(label: "Protein", text: $protein)
                    NumberRow(label: "Fat", text: $fat)
                    NumberRow(label: "Carbs", text: $carbs)
                    NumberRow(label: "Calories", text: $kcal, unit: "kcal")
                } footer: {
                    Text(kcal.isEmpty ? "Leave calories empty to work them out from the macros (\(number(fromMacros)) kcal)." : "")
                }
                DatePicker("Time", selection: $when, displayedComponents: .hourAndMinute)
            }
            .themedForm()
            .navigationTitle("Quick add")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if let entry {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) { ctx.delete(entry); ctx.commit(); dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(entry == nil ? "Add" : "Save", action: save).disabled(nutrients.kcal <= 0)
                }
            }
        }
        .appStyle()                             // sheets don't inherit these on the Mac
        #if os(macOS)
        .frame(width: 420, height: 440)
        #endif
        .onAppear {
            if let e = entry {
                name = e.name == "Quick add" ? "" : e.name
                kcal = text(e.nutrients.kcal); protein = text(e.nutrients.protein); fat = text(e.nutrients.fat); carbs = text(e.nutrients.carbs)
                when = e.time
            } else {
                when = defaultTime(for: day)
            }
        }
    }

    private var fromMacros: Double {
        (parseNumber(protein) ?? 0) * 4 + (parseNumber(carbs) ?? 0) * 4 + (parseNumber(fat) ?? 0) * 9
    }

    private var nutrients: Nutrients {
        Nutrients(kcal: parseNumber(kcal) ?? fromMacros, protein: parseNumber(protein) ?? 0, fat: parseNumber(fat) ?? 0,
                  carbs: parseNumber(carbs) ?? 0)
    }

    private func save() {
        let label = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Quick add" : name.trimmingCharacters(in: .whitespaces)
        if let e = entry {
            e.name = label; e.nutrients = nutrients; e.time = time(when, on: e.day)
        } else {
            ctx.insert(FoodEntry(day: day, time: time(when, on: day), name: label, brand: nil, foodKey: nil, amount: 1, unit: "",
                                 grams: 0, nutrients: nutrients))
        }
        ctx.commit()
        dismiss()
    }
}

// MARK: - Your own food

/// A food from its label: per 100 g, or per serving.
struct CustomFoodView: View {
    let food: Food?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var brand = ""
    @State private var barcode = ""
    @State private var liquid = false
    @State private var perServing = false
    @State private var servingName = "1 serving"
    @State private var servingGrams = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var carbs = ""
    @State private var fiber = ""
    @State private var sugar = ""
    @State private var satFat = ""
    @State private var sodium = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                    TextField("Barcode (optional)", text: $barcode)
                    Toggle("Drink (measured in ml)", isOn: $liquid)
                }
                Section("Serving") {
                    TextField("Serving name", text: $servingName)
                    NumberRow(label: "Serving size", text: $servingGrams, unit: liquid ? "ml" : "g")
                }
                Section {
                    Picker("Values are", selection: $perServing) {
                        Text("Per 100 \(liquid ? "ml" : "g")").tag(false)
                        Text("Per serving").tag(true)
                    }
                    .pickerStyle(.segmented)
                    NumberRow(label: "Calories", text: $kcal, unit: "kcal")
                    NumberRow(label: "Protein", text: $protein)
                    NumberRow(label: "Fat", text: $fat)
                    NumberRow(label: "Carbs", text: $carbs)
                } header: { Text("Nutrition") }
                Section("More (optional)") {
                    NumberRow(label: "Fibre", text: $fiber)
                    NumberRow(label: "Sugar", text: $sugar)
                    NumberRow(label: "Saturated fat", text: $satFat)
                    NumberRow(label: "Sodium", text: $sodium, unit: "mg")
                }
            }
            .themedForm()
            .navigationTitle(food == nil ? "New food" : "Edit food")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!valid) }
            }
        }
        .appStyle()                             // sheets don't inherit these on the Mac
        #if os(macOS)
        .frame(width: 480, height: 680)
        #endif
        .onAppear(perform: load)
    }

    private var grams: Double? { parseNumber(servingGrams).flatMap { $0 > 0 ? $0 : nil } }

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && parseNumber(kcal) != nil && (!perServing || grams != nil)
    }

    private func load() {
        guard let f = food else { return }
        name = f.name; brand = f.brand ?? ""; barcode = f.barcode ?? ""; liquid = f.isLiquid
        if let s = f.servings.first { servingName = s.name; servingGrams = text(s.grams) }
        let n = f.per100
        kcal = text(n.kcal); protein = text(n.protein); fat = text(n.fat); carbs = text(n.carbs)
        fiber = text(n.fiber); sugar = text(n.sugar); satFat = text(n.satFat); sodium = text(n.sodium)
    }

    private func save() {
        let entered = Nutrients(kcal: parseNumber(kcal) ?? 0, protein: parseNumber(protein) ?? 0, fat: parseNumber(fat) ?? 0,
                                carbs: parseNumber(carbs) ?? 0, fiber: parseNumber(fiber), sugar: parseNumber(sugar),
                                satFat: parseNumber(satFat), sodium: parseNumber(sodium))
        let per100 = perServing ? entered.scaled(100 / (grams ?? 100)) : entered
        let servings = grams.map { [Serving(name: servingName.trimmingCharacters(in: .whitespaces).isEmpty ? "1 serving" : servingName, grams: $0)] } ?? []
        let f = food ?? {
            let f = Food(key: "custom:\(UUID().uuidString)", name: name, source: "custom", per100: per100)
            ctx.insert(f)
            return f
        }()
        f.name = name.trimmingCharacters(in: .whitespaces)
        f.brand = brand.trimmingCharacters(in: .whitespaces).isEmpty ? nil : brand.trimmingCharacters(in: .whitespaces)
        f.barcode = barcode.isEmpty ? nil : barcode
        f.isLiquid = liquid; f.per100 = per100; f.servings = servings
        ctx.commit()
        dismiss()
    }
}

// MARK: - Recipes

/// Ingredients by weight; logged in servings.
struct RecipeView: View {
    let recipe: Food?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]
    @State private var name = ""
    @State private var servings = "4"
    @State private var items: [Item] = []
    @State private var picking = false

    struct Item: Identifiable {
        let id = UUID()
        var foodKey: String?
        var name: String
        var grams: Double
        var per100: Nutrients
    }

    var body: some View {
        let energy = profiles.first?.energy ?? .kcal
        let totals = recipeTotals(items.map { ($0.grams, $0.per100) }, servings: parseNumber(servings) ?? 0)
        NavigationStack {
            Form {
                Section {
                    TextField("Recipe name", text: $name)
                    NumberRow(label: "Makes", text: $servings, unit: "servings")
                }
                Section("Ingredients") {
                    ForEach($items) { $item in
                        HStack {
                            Text(item.name).lineLimit(1)
                            Spacer()
                            TextField("", value: $item.grams, format: .number).multilineTextAlignment(.trailing).frame(width: 70)
                            Text("g").foregroundStyle(.secondary)
                            Button(role: .destructive) { items.removeAll { $0.id == item.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button { picking = true } label: { Label("Add ingredient", systemImage: "plus") }
                }
                if let t = totals {
                    Section("Per serving · \(number(t.serving.grams)) g") {
                        let n = t.per100.scaled(t.serving.grams / 100)
                        Text(energy.format(n.kcal)).font(.title2.bold())
                        MacroLine(n: n)
                    }
                }
            }
            .themedForm()
            .navigationTitle(recipe == nil ? "New recipe" : "Edit recipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || totals == nil)
                }
            }
            .sheet(isPresented: $picking) {
                AddFoodView(mode: .pick { food, grams in
                    items.append(Item(foodKey: food.key, name: food.name, grams: grams.rounded(), per100: food.per100))
                })
            }
        }
        .appStyle()                             // sheets don't inherit these on the Mac
        #if os(macOS)
        .frame(width: 520, height: 620)
        #endif
        .onAppear(perform: load)
    }

    private func load() {
        guard let r = recipe, items.isEmpty else { return }
        name = r.name
        servings = text(r.recipeServings ?? 1)
        items = ctx.ingredients(of: r.key).map { Item(foodKey: $0.foodKey, name: $0.name, grams: $0.grams, per100: $0.per100) }
    }

    private func save() {
        guard let t = recipeTotals(items.map { ($0.grams, $0.per100) }, servings: parseNumber(servings) ?? 0) else { return }
        let r = recipe ?? {
            let f = Food(key: "recipe:\(UUID().uuidString)", name: name, source: "recipe", per100: t.per100)
            ctx.insert(f)
            return f
        }()
        r.name = name.trimmingCharacters(in: .whitespaces)
        r.per100 = t.per100; r.servings = [t.serving]; r.recipeServings = parseNumber(servings)
        for old in ctx.ingredients(of: r.key) { ctx.delete(old) }
        for (i, item) in items.enumerated() {
            ctx.insert(RecipeIngredient(recipeKey: r.key, foodKey: item.foodKey, name: item.name, grams: item.grams,
                                        per100: item.per100, order: i))
        }
        ctx.commit()
        dismiss()
    }
}
