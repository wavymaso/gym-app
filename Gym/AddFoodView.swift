import SwiftData
import SwiftUI

/// Find a food (your own, USDA, Open Food Facts, or a barcode), then choose how much.
struct AddFoodView: View {
    enum Mode {
        case log(day: String)
        case pick((Food, Double) -> Void)          // recipes: hand back a food and grams
    }

    let mode: Mode
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @AppStorage("usdaKey") private var usdaKey = ""
    @Query(sort: \Food.lastUsed, order: .reverse) private var foods: [Food]

    @State private var query: String = {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "searchQuery") ?? ""                // testing only: -searchQuery yogur
        #else
        return ""
        #endif
    }()
    @State private var tab = Tab.search
    @State private var generic: [FoodResult] = []
    @State private var products: [FoodResult] = []
    @State private var genericError: String?
    @State private var productError: String?
    @State private var searching = false
    @State private var chosen: Food?
    @State private var opening: String?
    @State private var newFood = false
    @State private var newRecipe = false
    @FocusState private var focused: Bool

    enum Tab: String, CaseIterable { case search = "Search", recent = "Recent", favourites = "Favourites", mine = "My foods" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    TextField("Search foods, brands or a barcode", text: $query)
                        .textFieldStyle(.roundedBorder).focused($focused)
                        .onSubmit { tab = .search }
                    Picker("", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden()
                }
                .padding(16)
                List {
                    switch tab {
                    case .search: searchResults
                    case .recent: localList(foods.filter { $0.lastUsed != nil }.prefix(60).map { $0 }, empty: "Foods you log appear here.")
                    case .favourites: localList(foods.filter(\.isFavorite).sorted { $0.name < $1.name }, empty: "Star a food to keep it here.")
                    case .mine: myFoods
                    }
                }
                #if os(macOS)
                .listStyle(.inset)
                #endif
            }
            .navigationTitle(isPicking ? "Add ingredient" : "Add food")
            .navigationDestination(item: $chosen) { f in FoodAmountView(food: f, mode: mode, done: { dismiss() }) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if !isPicking {
                    ToolbarItem {
                        Menu {
                            Button("New food…") { newFood = true }
                            Button("New recipe…") { newRecipe = true }
                        } label: { Label("New", systemImage: "square.and.pencil") }
                    }
                }
            }
            .sheet(isPresented: $newFood) { CustomFoodView(food: nil) }
            .sheet(isPresented: $newRecipe) { RecipeView(recipe: nil) }
            .sheet(item: $editingFood) { CustomFoodView(food: $0) }
            .sheet(item: $editingRecipe) { RecipeView(recipe: $0) }
        }
        .environment(\.locale, appLocale)       // sheets don't inherit it on the Mac
        #if os(macOS)
        .frame(width: 620, height: 680)
        #endif
        .onAppear {
            focused = true
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "chooseFirst") { chosen = localMatches.first }   // testing only
            #endif
        }
        .task(id: query) { await search() }
    }

    private var isPicking: Bool { if case .pick = mode { return true } else { return false } }

    private var localMatches: [Food] {
        let words = FoodAPI.fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return foods.filter { f in
            let text = FoodAPI.fold("\(f.name) \(f.brand ?? "")")
            return words.allSatisfy { text.contains($0) }
        }.sorted { $0.useCount > $1.useCount }.prefix(8).map { $0 }
    }

    @ViewBuilder private var searchResults: some View {
        if query.trimmingCharacters(in: .whitespaces).count < 2 {
            Text("Type at least two letters. Plain foods (rice, chicken breast) come from USDA, in English; supermarket products from Open Food Facts, in Spanish.")
                .font(.callout).foregroundStyle(.secondary).listRowSeparator(.hidden)
        } else {
            if !localMatches.isEmpty {
                Section("Your foods") { ForEach(localMatches) { f in foodRow(f) } }
            }
            Section {
                ForEach(generic) { r in resultRow(r) }
                if let genericError { Text(genericError).font(.callout).foregroundStyle(.secondary) }
                else if generic.isEmpty && !searching { Text("No matches").font(.callout).foregroundStyle(.secondary) }
            } header: { header("Common foods · USDA") }
            Section {
                ForEach(products.filter { p in !localMatches.contains { $0.key == p.key } }) { r in resultRow(r) }
                if let productError { Text(productError).font(.callout).foregroundStyle(.secondary) }
                else if products.isEmpty && !searching { Text("No matches").font(.callout).foregroundStyle(.secondary) }
            } header: { header("Products · Open Food Facts") }
        }
    }

    private func header(_ t: String) -> some View {
        HStack { Text(t); if searching { ProgressView().controlSize(.small) } }
    }

    @ViewBuilder private var myFoods: some View {
        let mine = foods.filter { $0.source == "custom" || $0.source == "recipe" }.sorted { $0.name < $1.name }
        if mine.isEmpty {
            Text("Foods and recipes you create appear here. Use New (top right).").font(.callout).foregroundStyle(.secondary)
        }
        ForEach(mine) { f in
            foodRow(f).contextMenu {
                if f.source == "recipe" { Button("Edit recipe…") { editingRecipe = f } } else { Button("Edit food…") { editingFood = f } }
                Button("Delete", role: .destructive) {
                    for i in ctx.ingredients(of: f.key) { ctx.delete(i) }
                    ctx.delete(f); try? ctx.save()
                }
            }
        }
    }
    @State private var editingFood: Food?
    @State private var editingRecipe: Food?

    private func localList(_ list: [Food], empty: String) -> some View {
        Group {
            if list.isEmpty { Text(empty).font(.callout).foregroundStyle(.secondary) }
            ForEach(list) { f in foodRow(f) }
        }
    }

    private func foodRow(_ f: Food) -> some View {
        Button { chosen = f } label: {
            FoodRowLabel(name: f.name, brand: f.brand, source: f.source, per100: f.per100, unit: f.baseUnit, favorite: f.isFavorite)
        }
        .buttonStyle(.plain)
    }

    private func resultRow(_ r: FoodResult) -> some View {
        Button { Task { await open(r) } } label: {
            HStack {
                FoodRowLabel(name: r.name, brand: r.brand, source: r.source, per100: r.per100, unit: r.isLiquid ? "ml" : "g", favorite: false)
                if opening == r.key { ProgressView().controlSize(.small) }
            }
        }
        .buttonStyle(.plain)
    }

    /// Products: fetch the full record first, for its serving size.
    private func open(_ r: FoodResult) async {
        var r = r
        if r.source == "off", let code = r.barcode {
            opening = r.key
            if let full = try? await FoodAPI.product(barcode: code) { r.servings = full.servings }
            opening = nil
        }
        chosen = ctx.food(for: r)
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, tab == .search else { generic = []; products = []; return }
        try? await Task.sleep(nanoseconds: 450_000_000)            // wait until you stop typing
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        genericError = nil; productError = nil

        if q.allSatisfy(\.isNumber) && q.count >= 8 {               // a barcode
            generic = []
            do {
                if let p = try await FoodAPI.product(barcode: q) { products = [p] }
                else { products = []; productError = "No product with barcode \(q) on Open Food Facts. You can add it as a new food." }
            } catch { productError = error.localizedDescription }
            return
        }
        async let g = Result { try await FoodAPI.searchGeneric(q, apiKey: usdaKey) }
        async let p = Result { try await FoodAPI.searchProducts(q) }
        let (gr, pr) = await (g, p)
        guard !Task.isCancelled else { return }
        switch gr { case .success(let x): generic = x; case .failure(let e): generic = []; genericError = e.localizedDescription }
        switch pr { case .success(let x): products = x; case .failure(let e): products = []; productError = e.localizedDescription }
    }
}

extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}

struct FoodRowLabel: View {
    let name: String
    let brand: String?
    let source: String
    let per100: Nutrients
    let unit: String
    let favorite: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(name).font(.body.weight(.medium)).lineLimit(1)
                    if favorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(Macro.fat.color) }
                }
                Text([brand, sourceLabel].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(number(per100.kcal)) kcal").font(.callout.weight(.semibold)).monospacedDigit()
                    Text("/100 \(unit)").font(.caption).foregroundStyle(.secondary)
                }
                MacroLine(n: per100)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var sourceLabel: String? {
        switch source {
        case "custom": return "My food"
        case "recipe": return "Recipe"
        default: return nil
        }
    }
}

/// How much of a food, and when. Used for logging, editing an entry, and recipe ingredients.
struct FoodAmountView: View {
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name).font(.title3.bold())
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
                    Text(energy.format(n.kcal)).font(.title2.bold()).monospacedDigit()
                    Spacer()
                    Text("\(number(food.grams(amount, unit: unit))) \(food.baseUnit)").foregroundStyle(.secondary)
                }
                HStack(spacing: 24) {
                    ForEach([Macro.protein, .fat, .carbs], id: \.self) { m in
                        VStack(alignment: .leading) {
                            Text("\(number(m.value(n.targets), digits: 1)) g").font(.headline).monospacedDigit()
                            Label(m.label, systemImage: "circle.fill").labelStyle(DotLabel(color: m.color)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                detail("Fibre", n.fiber, "g")
                detail("Sugar", n.sugar, "g")
                detail("Saturated fat", n.satFat, "g")
                detail("Sodium", n.sodium, "mg")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(entry == nil ? "How much?" : "Edit entry")
        .toolbar {
            ToolbarItem {
                Button { food.isFavorite.toggle(); try? ctx.save() } label: {
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
        if case .pick = mode { return "Add to recipe" }
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
            if case .log(let day) = mode { time = defaultTime(for: day) }
        }
    }

    private func commit() {
        if let e = entry {
            e.amount = amount; e.unit = unit; e.grams = food.grams(amount, unit: unit); e.nutrients = food.nutrients(amount, unit: unit)
            e.time = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: time),
                                           minute: Calendar.current.component(.minute, from: time), second: 0, of: date(fromKey: e.day)) ?? time
            try? ctx.save()
        } else {
            switch mode {
            case .log(let day):
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

    var body: some View {
        NavigationStack {
            FoodAmountView(food: food, mode: .log(day: entry.day), entry: entry, done: { dismiss() })
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) { ctx.delete(entry); try? ctx.save(); dismiss() }
                    }
                }
        }
        .environment(\.locale, appLocale)       // sheets don't inherit it on the Mac
        #if os(macOS)
        .frame(width: 520, height: 600)
        #endif
    }

    private var food: Food {
        if let k = entry.foodKey, let f = ctx.food(key: k) { return f }
        let per100 = entry.grams > 0 ? entry.nutrients.scaled(100 / entry.grams) : entry.nutrients
        return Food(key: entry.foodKey ?? "deleted", name: entry.name, brand: entry.brand, source: "custom", per100: per100)
    }
}
