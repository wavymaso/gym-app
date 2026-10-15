import SwiftData
import SwiftUI

/// Find a food (your own, USDA, Open Food Facts, or a barcode), then choose how much.
struct AddFoodView: View {
    enum Mode {
        case log(day: String, time: Date? = nil)   // time: when adding to a meal
        case pick((Food, Double) -> Void)          // recipes: hand back a food and grams
    }

    let mode: Mode
    var initialQuery: String? = nil              // recipe import: search for the ingredient straight away
    /// Inside the food logger (FoodLogger.swift): just the search, or just your library; a pick goes to `choose`.
    enum Embedded { case search, library }
    var embedded: Embedded? = nil
    var choose: ((Food) -> Void)? = nil
    var chooseMeal: ((SavedMeal) -> Void)? = nil
    var quickAdd: ((Food, Double, String) -> Void)? = nil       // the round + : straight into the cart
    var logFoods: (() -> Void)? = nil
    var cartCount = 0
    var startScanning = false                    // the + button's "Scan barcode"
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    private var usdaKey: String { Secrets.get("usdaKey") }
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
    @State private var local: [FoodResult] = []                  // the offline database (LocalFoods)
    @State private var correction: String?                        // "Showing results for …" after a typo
    @AppStorage("foodScope") private var scope: LocalFoods.Scope = .all
    @State private var genericError: String?
    @State private var productError: String?
    @State private var searching = false
    @State private var chosen: Food?
    @State private var opening: String?
    @State private var newFood = false
    @State private var scanningLabel = false
    @State private var newRecipe = false
    @State private var scanning = false
    @State private var recipeLink = false
    @State private var photo: PhotoLogView.Start?
    @FocusState private var focused: Bool

    enum Tab: String, CaseIterable { case search = "Search", recent = "Recent", meals = "Meals", favourites = "Favourites", mine = "My foods" }

    var body: some View {
        if embedded != nil {
            panel
                .sheet(isPresented: $newFood) { CustomFoodView(food: nil) }
                .sheet(item: $editingFood) { CustomFoodView(food: $0) }
                .sheet(item: $editingRecipe) { RecipeView(recipe: $0) }
                .onAppear { if let q = initialQuery, query.isEmpty { query = q }; if embedded == .library { tab = .recent } }
                .sheet(isPresented: $recipeLink) { RecipeView(recipe: nil, startImport: true) }
                .sheet(item: $photo) { start in
                    if case .log(let day, let at) = mode { PhotoLogView(day: day, time: at, start: start) }
                }
                .sheet(isPresented: $scanningLabel) { LabelScanView() }
                .task(id: query) { await search() }
        } else {
            standalone
        }
    }

    /// Inside the logger the top only holds the tabs (Library) or store chips (while typing).
    private var showsTop: Bool {
        embedded == nil || embedded == .library || (LocalFoods.shared.available && !query.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            if showsTop {
            VStack(spacing: 10) {
                if embedded == nil {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search foods, brands or a barcode", text: $query)
                            .textFieldStyle(.plain).focused($focused)
                            .onSubmit { tab = .search }
                            #if os(iOS)
                            .submitLabel(.search).autocorrectionDisabled()
                            #endif
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Color.raisedBackground, in: Capsule())
                }
                if embedded != .search {
                    Picker("", selection: $tab) {
                        ForEach(Tab.allCases.filter { embedded == nil || $0 != .search }, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                if tab == .search && LocalFoods.shared.available && (embedded == nil || !query.trimmingCharacters(in: .whitespaces).isEmpty) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(LocalFoods.Scope.allCases) { s in
                                Button(s.label) { scope = s; local = LocalFoods.shared.search(query, scope: s) }
                                    .font(.caption.weight(.semibold)).buttonStyle(.plain)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(scope == s ? palette.accent : Color.raisedBackground, in: Capsule())
                                    .foregroundStyle(scope == s ? .white : .primary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, embedded == nil ? 16 : 10)
            .background { if embedded == nil { Color.pageBackground } }
            }
            List {
                if embedded == .library {
                    Button { recipeLink = true } label: {
                        Label("Recipe from a TikTok or Instagram link", systemImage: "link")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
                switch tab {
                case .search: searchResults
                case .recent: localList(foods.filter { $0.lastUsed != nil }.prefix(60).map { $0 }, empty: "Foods you log appear here.")
                case .favourites: localList(foods.filter(\.isFavorite).sorted { $0.name < $1.name }, empty: "Star a food to keep it here.")
                case .mine: myFoods
                case .meals:
                    SavedMealsList(pick: { m in
                        if let chooseMeal { chooseMeal(m) }
                        else if case .log(let day, let at) = mode { ctx.log(m, day: day, time: at ?? defaultTime(for: day)); dismiss() }
                    }, energy: (try? ctx.fetch(FetchDescriptor<Profile>()).first?.energy) ?? .kcal)
                }
            }
            #if os(macOS)
            .listStyle(.inset)
            .themedList()
            #else
            .listStyle(.plain).scrollContentBackground(.hidden)
            #endif
        }
        .safeAreaInset(edge: .bottom) {
            if embedded != nil {
                HStack(spacing: 10) {
                    if embedded == .search {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").font(.headline)
                            TextField("Search for a food", text: $query)
                                .textFieldStyle(.plain).focused($focused)
                                #if os(iOS)
                                .submitLabel(.search).autocorrectionDisabled()
                                #endif
                            if !query.isEmpty {
                                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 18).frame(height: 54)
                        .modifier(GlassCapsule())
                    } else { Spacer() }
                    if cartCount > 0, let logFoods {
                        Button(action: logFoods) {
                            Text("Log Foods").font(.headline).padding(.horizontal, 20).frame(height: 54)
                                .background(.white, in: Capsule()).foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 6)
                .animation(Motion.snappy, value: cartCount)
            }
        }
    }

    private var standalone: some View {
        NavigationStack {
            panel
            .pageBackground()
            .navigationTitle(isPicking ? "Add ingredient" : "Add food")
            .navigationDestination(item: $chosen) { f in FoodAmountView(food: f, mode: mode, done: { dismiss() }) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                #if os(iOS)
                ToolbarItem { Button { scanning = true } label: { Label("Scan barcode", systemImage: "barcode.viewfinder") } }
                #endif
                if !isPicking {
                    ToolbarItem {
                        Menu {
                            Button("Photo of your meal…", systemImage: "camera") { photo = .camera }
                            Button("Choose a photo…", systemImage: "photo") { photo = .library }
                            Button("Describe it…", systemImage: "text.bubble") { photo = .describe }
                        } label: { Label("AI", systemImage: "sparkles") }
                    }
                }
                if !isPicking {
                    ToolbarItem {
                        Menu {
                            Button("New food…") { newFood = true }
                            Button("Scan a nutrition label…") { scanningLabel = true }
                            Button("New recipe…") { newRecipe = true }
                        } label: { Label("New", systemImage: "square.and.pencil") }
                    }
                }
            }
            #if os(iOS)
            .sheet(isPresented: $scanning) { BarcodeScanner { code in tab = .search; query = code } }
            #endif
            .sheet(isPresented: $newFood) { CustomFoodView(food: nil) }
            .sheet(item: $photo) { start in
                if case .log(let day, let at) = mode { PhotoLogView(day: day, time: at, start: start) }
            }
            .sheet(isPresented: $scanningLabel) { LabelScanView() }
            .sheet(isPresented: $newRecipe) { RecipeView(recipe: nil) }
            .sheet(item: $editingFood) { CustomFoodView(food: $0) }
            .sheet(item: $editingRecipe) { RecipeView(recipe: $0) }
        }
        .appStyle()                             // sheets don't inherit these on the Mac
        #if os(macOS)
        .frame(width: 620, height: 680)
        #endif
        .onAppear {
            focused = true
            if let q = initialQuery, query.isEmpty { query = q }
            #if os(iOS)
            if startScanning { scanning = true }
            #endif
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "chooseFirst") { chosen = localMatches.first }   // testing only
            #endif
        }
        .task(id: query) { await search() }
    }

    private var isPicking: Bool { if case .pick = mode { return true } else { return false } }

    /// Smart history: the foods you most often have at this meal (last 60 days), most frequent first.
    private var usual: (meal: Meal, foods: [Food]) {
        var when = Date()
        if case .log(let day, let at) = mode { when = at ?? defaultTime(for: day) }
        let meal = Meal(time: when)
        let from = addDays(dayKey(), -60)
        let recent = (try? ctx.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.day >= from && $0.foodKey != nil }))) ?? []
        var score: [String: Double] = [:]
        for e in recent where Meal(time: e.time) == meal {
            guard let k = e.foodKey, k != "import" else { continue }
            score[k, default: 0] += 1 + 30 / Double(max(1, daysBetween(e.day, dayKey())) + 30)   // recent days count a bit more
        }
        let byKey = Dictionary(foods.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        return (meal, score.sorted { $0.value > $1.value }.prefix(8).compactMap { byKey[$0.key] })
    }

    private var nothingAnywhere: Bool { localMatches.isEmpty && local.isEmpty && generic.isEmpty && products.isEmpty && !searching }

    private var localMatches: [Food] {
        let words = FoodAPI.fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return foods.filter { f in
            let text = FoodAPI.fold("\(f.name) \(f.brand ?? "")")
            return words.allSatisfy { text.contains($0) }
        }.sorted { $0.useCount > $1.useCount }.prefix(8).map { $0 }
    }

    @ViewBuilder private var searchResults: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty, !isPicking, !usual.foods.isEmpty || foods.contains(where: { $0.lastUsed != nil }) {
            if !usual.foods.isEmpty {
                Section { ForEach(usual.foods) { f in foodRow(f) } } header: { sectionTitle(picksTitle) }
            }
            Section { ForEach(foods.filter { $0.lastUsed != nil && !usual.foods.contains($0) }.prefix(25).map { $0 }) { f in foodRow(f) } } header: { sectionTitle("Latest") }
        } else if query.trimmingCharacters(in: .whitespaces).count < 2 {
            Text("Type at least two letters. Plain foods (rice, chicken breast) come from USDA, in English; supermarket products from Open Food Facts, in Spanish.")
                .font(.callout).foregroundStyle(.secondary).listRowSeparator(.hidden)
        } else {
            if let correction {
                Label("Showing results for “\(correction)”", systemImage: "wand.and.stars").font(.callout).foregroundStyle(.secondary)
            }
            if nothingAnywhere {
                NoMatch(query: query.trimmingCharacters(in: .whitespaces), describe: { photo = .describe },
                        create: { newFood = true }, scanLabel: { scanningLabel = true })
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            if !localMatches.isEmpty {
                Section("Your foods") { ForEach(localMatches) { f in foodRow(f) } }
            }
            let mine = Set(localMatches.map(\.key))
            if !local.isEmpty {
                Section { ForEach(local.filter { !mine.contains($0.key) }) { r in resultRow(r) } } header: {
                    Text(scope == .all ? "Products · Spain & Saudi" : "Products · \(scope.label)")
                }
            }
            Section {
                ForEach(generic) { r in resultRow(r) }
                if let genericError { Text(genericError).font(.callout).foregroundStyle(.secondary) }
                else if generic.isEmpty && !searching && !nothingAnywhere { Text("Nothing here").font(.callout).foregroundStyle(.tertiary) }
            } header: { header("Common foods · USDA") }
            Section {
                ForEach(products.filter { p in !mine.contains(p.key) && !local.contains { $0.key == p.key } }) { r in resultRow(r) }
                if let productError { Text(productError).font(.callout).foregroundStyle(.secondary) }
                else if products.isEmpty && !searching && !nothingAnywhere { Text("Nothing here").font(.callout).foregroundStyle(.tertiary) }
            } header: { header(local.isEmpty ? "Products · Open Food Facts" : "More products online · Open Food Facts") }
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
                    ctx.delete(f); ctx.commit()
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

    /// "12 PM Picks": what you usually have around now.
    private var picksTitle: String {
        var when = Date()
        if case .log(let day, let at) = mode { when = at ?? defaultTime(for: day) }
        return "\(when.formatted(.dateTime.hour().locale(appLocale))) Picks"
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.title3.weight(.semibold)).foregroundStyle(.primary).textCase(nil)
    }

    private func foodRow(_ f: Food) -> some View {
        Group {
            if embedded != nil {
                let (a, u) = f.suggestedAmount
                MFFoodRow(name: f.name, brand: f.brand, n: f.nutrients(a, unit: u), amount: amountText(a, u, f), favorite: f.isFavorite,
                          open: { pick(f) }, plus: quickAdd.map { q in { q(f, a, u) } },
                          logNow: quickAdd.flatMap { q in logFoods.map { l in { q(f, a, u); l() } } })
            } else {
                Button { pick(f) } label: {
                    FoodRowLabel(name: f.name, brand: f.brand, source: f.source, per100: f.per100, unit: f.baseUnit, favorite: f.isFavorite)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func amountText(_ a: Double, _ u: String, _ f: Food) -> String {
        let n = number(a, digits: a == a.rounded() ? 0 : 1)
        if ["g", "ml", "oz"].contains(u) { return "\(n) \(u)" }
        return "\(a == 1 ? "" : "\(n) × ")\(u)"
    }

    private func resultRow(_ r: FoodResult) -> some View {
        Group {
            if embedded != nil {
                let g = r.servings.first?.grams ?? 100
                MFFoodRow(name: r.name, brand: r.brand, n: r.per100.scaled(g / 100),
                          amount: r.servings.first.map { $0.name } ?? "100 \(r.isLiquid ? "ml" : "g")", favorite: false,
                          busy: opening == r.key, open: { Task { await open(r) } },
                          plus: quickAdd.map { q in {
                              let f = ctx.food(for: r)
                              let (a, u) = f.suggestedAmount
                              q(f, a, u)
                          } })
            } else {
                Button { Task { await open(r) } } label: {
                    HStack {
                        FoodRowLabel(name: r.name, brand: r.brand, source: r.source, per100: r.per100, unit: r.isLiquid ? "ml" : "g", favorite: false)
                        if opening == r.key { ProgressView().controlSize(.small) }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Products: fetch the full record first, for its serving size.
    private func open(_ r: FoodResult) async {
        var r = r
        if r.source == "off", r.servings.isEmpty, let code = r.barcode {      // local results usually have their servings already
            opening = r.key
            if let full = try? await FoodAPI.product(barcode: code) { r.servings = full.servings }
            opening = nil
        }
        pick(ctx.food(for: r))
    }

    private func pick(_ f: Food) { if let choose { choose(f) } else { chosen = f } }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, tab == .search else { generic = []; products = []; local = []; return }
        // The offline database answers straight away; the internet ones once you stop typing.
        if q.allSatisfy(\.isNumber) && q.count >= 8 {
            local = LocalFoods.shared.product(barcode: q).map { [$0] } ?? []
        } else {
            local = LocalFoods.shared.search(q, scope: scope)
            correction = LocalFoods.shared.lastCorrection
        }
        try? await Task.sleep(nanoseconds: 450_000_000)            // wait until you stop typing
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        genericError = nil; productError = nil

        if q.allSatisfy(\.isNumber) && q.count >= 8 {               // a barcode
            generic = []
            do {
                if let p = try await FoodAPI.product(barcode: q) { products = local.contains { $0.key == p.key } ? [] : [p] }
                else if local.isEmpty { products = []; productError = "No product with barcode \(q) on Open Food Facts. You can add it as a new food, or scan its label." }
            } catch { if local.isEmpty { productError = error.localizedDescription } }
            return
        }
        async let g = Result { try await FoodAPI.searchGeneric(q, apiKey: usdaKey) }
        async let p = Result { try await FoodAPI.searchProducts(q) }
        let (gr, pr) = await (g, p)
        guard !Task.isCancelled else { return }
        switch gr { case .success(let x): generic = x; case .failure(let e): generic = []; genericError = e.localizedDescription }
        switch pr {
        case .success(let x): products = x
        case .failure(let e): products = []; productError = local.isEmpty ? e.localizedDescription : "Offline: showing the built-in database only."
        }
    }
}

extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}

/// What the button says when picking a food for something else ("Add to recipe", "Use this").
private struct PickTitleKey: EnvironmentKey { static let defaultValue = "Add to recipe" }
extension EnvironmentValues {
    var pickTitle: String { get { self[PickTitleKey.self] } set { self[PickTitleKey.self] = newValue } }
}
