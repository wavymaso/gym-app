import PhotosUI
import SwiftData
import SwiftUI
#if os(macOS)
import UniformTypeIdentifiers
#endif

/// Log a meal from a photo, a photo and a few words, or words alone (PhotoAI.swift).
/// The result is a plate you can adjust before logging: portions, matches, what to leave out.
struct PhotoLogView: View {
    enum Start: String, Identifiable { case camera, library, describe; var id: String { rawValue } }

    let day: String
    var time: Date? = nil
    var start: Start = .camera
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]

    private enum Stage: Equatable { case input, working, plate, failed(String) }
    @State private var stage = Stage.input
    @State private var jpeg: Data?
    @State private var preview: CGImage?
    @State private var details = ""
    @State private var plate: [PlateItem] = []
    @State private var seenBy = ""
    @State private var camera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var showLibrary = false
    @State private var importing = false
    @State private var swapping: PlateItem?
    @State private var started = false
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .input: input
                case .working: working
                case .plate: plateView
                case .failed(let why): failed(why)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .pageBackground()
            .navigationTitle(start == .describe && jpeg == nil ? "Describe a meal" : "Photo log")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $camera) { CameraPicker { use($0) }.ignoresSafeArea() }
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if stage == .plate {
                    ToolbarItem(placement: .confirmationAction) { Button("Log") { log() }.disabled(!plate.contains(where: \.included)) }
                }
            }
            .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task { if let d = try? await item.loadTransferable(type: Data.self) { use(d) } }
            }
            #if os(macOS)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { r in
                if case .success(let url) = r {
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    if let d = try? Data(contentsOf: url) { use(d) }
                }
            }
            .dropDestination(for: Data.self) { items, _ in
                guard let d = items.first else { return false }
                use(d); return true
            }
            #endif
            .sheet(item: $swapping) { item in
                AddFoodView(mode: .pick({ food, grams in replace(item, with: food, grams: grams) }),
                            initialQuery: item.ai?.search ?? item.name)
                    .environment(\.pickTitle, "Use this")
            }
        }
        .appStyle()
        #if os(macOS)
        .frame(width: 560, height: 700)
        #endif
        .onAppear {
            guard !started else { return }
            started = true
            #if os(iOS)
            if start == .camera { camera = true }
            #endif
            if start == .describe { typing = true }
            if start == .library { showLibrary = true }
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "photoDemo") {        // testing only: a canned answer, no camera or model
                camera = false
                let items = PhotoAI.parse(#"{"items":[{"name":"Seafood paella","name_es":"Paella de marisco","search":"paella seafood","grams":420,"kcal_100g":160,"protein_100g":9,"fat_100g":6,"carbs_100g":18,"confidence":0.8},{"name":"Lemon","name_es":"Limón","search":"lemon","grams":20,"kcal_100g":29,"protein_100g":1,"fat_100g":0,"carbs_100g":9,"confidence":0.9},{"name":"Alioli","name_es":"Alioli","search":"aioli","grams":25,"kcal_100g":700,"protein_100g":1,"fat_100g":77,"carbs_100g":1,"confidence":0.4}]}"#)
                plate = ctx.plate(from: items); seenBy = "Marcel's MacBook Pro"; stage = .plate
            }
            #endif
        }
    }

    private var energy: EnergyUnit { profiles.first?.energy ?? .kcal }

    // MARK: Taking the photo

    private var input: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                photoArea
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(jpeg == nil ? "Or describe what you ate" : "Anything the photo can't show? (optional)")
                        .font(.secondaryEmphasis).foregroundStyle(.secondary)
                    TextField(jpeg == nil ? "e.g. 2 fried eggs, 150 g of rice and a glass of orange juice"
                                          : "e.g. cooked in olive oil, I ate half, it's chicken not tofu",
                              text: $details, axis: .vertical)
                        .lineLimit(2...5).focused($typing)
                        .padding(Space.m).modifier(CardSurface(cornerRadius: Radius.m))
                }
                Button { Task { await analyse() } } label: {
                    Label(jpeg == nil ? "Find foods" : "Analyse meal", systemImage: "sparkles")
                        .font(.cardTitle).frame(maxWidth: .infinity).padding(.vertical, Space.s)
                }
                .buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent).controlSize(.large)
                .disabled(jpeg == nil && details.trimmingCharacters(in: .whitespaces).count < 3)
                tips
            }
            .padding(Space.xl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private var photoArea: some View {
        if let preview {
            ZStack(alignment: .topTrailing) {
                Image(decorative: preview, scale: 1).resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 260).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                Button { jpeg = nil; self.preview = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.sectionTitle).symbolRenderingMode(.palette)
                        .foregroundStyle(Tokens.onScrim, Tokens.scrim)
                }
                .buttonStyle(.plain).padding(Space.m)
            }
        } else {
            VStack(spacing: Space.m) {
                Image(systemName: "fork.knife.circle").font(.iconHero).foregroundStyle(palette.accent)
                HStack(spacing: Space.m) {
                    #if os(iOS)
                    Button { camera = true } label: { Label("Camera", systemImage: "camera.fill").lineLimit(1).frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).controlSize(.large)
                    #else
                    Button { importing = true } label: { Label("Choose file…", systemImage: "folder").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).controlSize(.large)
                    #endif
                    PhotosPicker(selection: $libraryItem, matching: .images) {
                        Label("Photos", systemImage: "photo.on.rectangle").lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                }
                #if os(macOS)
                Text("or drop a photo here").font(.note).foregroundStyle(.secondary)
                #endif
            }
            .padding(Space.xl).frame(maxWidth: .infinity)
            .modifier(CardSurface(cornerRadius: Radius.l))
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label("Good light, from above, everything in view", systemImage: "sun.max")
            Label("Barcodes and packets in the photo are read exactly", systemImage: "barcode")
            Label("A fork or your hand in shot helps judge portions", systemImage: "hand.raised")
        }
        .font(.note).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func use(_ data: Data) {
        guard let p = PhotoAI.prepare(data) else { stage = .failed("That photo couldn't be read."); return }
        jpeg = p.jpeg; preview = p.image
        stage = .input
    }

    // MARK: Analysing

    private var working: some View {
        VStack(spacing: Space.l) {
            if let preview {
                Image(decorative: preview, scale: 1).resizable().scaledToFill()
                    .frame(width: 180, height: 180).clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(Tokens.scrim.opacity(0.45)))
            }
            ProgressView().controlSize(.large)
            Text(jpeg == nil ? "Finding foods…" : "Looking at your meal…").font(.cardTitle)
            Text(PhotoAI.engine == .gemini ? "With Gemini" : "On your Mac, usually 10–30 seconds")
                .font(.note).foregroundStyle(.secondary)
        }
    }

    private func analyse() async {
        typing = false
        stage = .working
        // Packets with a barcode in shot: the exact product, no guessing.
        var found: [PlateItem] = []
        if let preview {
            for code in await PhotoAI.barcodes(in: preview) {
                var product = LocalFoods.shared.product(barcode: code)
                if product == nil { product = try? await FoodAPI.product(barcode: code) }
                if let p = product {
                    let g = p.servings.first?.grams ?? 100
                    found.append(PlateItem(name: p.name, detail: p.brand, per100: p.per100, isLiquid: p.isLiquid, grams: g, suggested: g,
                                           foodKey: ctx.food(key: p.key)?.key, product: p, source: .product))
                }
            }
        }
        do {
            let (items, by) = try await PhotoAI.analyse(images: jpeg.map { [$0] } ?? [], text: details)
            var matched = ctx.plate(from: items)
            if !found.isEmpty {     // the packet the model saw is the one already read from its barcode
                var skip = found.count
                for i in matched.indices where skip > 0 && matched[i].ai?.packaged == true { matched[i].included = false; skip -= 1 }
            }
            plate = found + matched
            seenBy = by
            stage = plate.isEmpty ? .failed("No food found. Try a closer photo in better light, or add a few words about it.") : .plate
        } catch {
            if found.isEmpty { stage = .failed(error.localizedDescription) } else { plate = found; seenBy = "barcode"; stage = .plate }
        }
    }

    private func failed(_ why: String) -> some View {
        VStack(spacing: Space.l) {
            Image(systemName: "exclamationmark.triangle").font(.screenTitle).foregroundStyle(palette.warning)
            Text(why).multilineTextAlignment(.center).font(.secondaryText)
            HStack {
                Button("Try again") { Task { await analyse() } }.buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent)
                Button("Back") { stage = .input }.buttonStyle(.bordered)
            }
        }
        .padding(Space.xxl)
    }

    // MARK: The plate

    private var plateView: some View {
        ScrollView {
            VStack(spacing: Space.m) {
                summary
                ForEach($plate) { $item in PlateRow(item: $item, energy: energy, swap: { swapping = item }) }
                Button { swapping = PlateItem(name: "", per100: .zero, isLiquid: false, grams: 0, suggested: 0, source: .picked, included: false) } label: {
                    Label("Add something else", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
                Text("Nutrition comes from your foods, products and USDA where they match; the rest is the model's estimate (marked ≈). Portions you change are remembered for next time.")
                    .font(.note).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Space.l)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: log) {
                Text("Log \(plate.filter(\.included).count) item\(plate.filter(\.included).count == 1 ? "" : "s")")
                    .font(.cardTitle).frame(maxWidth: .infinity).padding(.vertical, Space.s)
            }
            .buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent).controlSize(.large)
            .disabled(!plate.contains(where: \.included))
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
            .background(.bar)
        }
    }

    private var summary: some View {
        let total = plate.filter(\.included).reduce(Nutrients.zero) { $0 + $1.nutrients }
        return HStack(spacing: Space.l) {
            if let preview {
                Image(decorative: preview, scale: 1).resizable().scaledToFill()
                    .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(energy.format(total.kcal)).font(.numberLarge)
                HStack(spacing: Space.m) {
                    macro("P", total.protein, Macro.protein.color)
                    macro("F", total.fat, Macro.fat.color)
                    macro("C", total.carbs, Macro.carbs.color)
                }
                Text("Seen by \(seenBy)").font(.fine).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(Space.l)
        .modifier(CardSurface(cornerRadius: Radius.l))
    }

    private func macro(_ l: String, _ g: Double, _ c: Color) -> some View {
        HStack(spacing: Space.xs) {
            Text(l).font(.label).foregroundStyle(c)
            Text("\(number(g)) g").font(.label.monospacedDigit())
        }
    }

    /// Swapped for a food you chose (or added a new one).
    private func replace(_ item: PlateItem, with food: Food, grams: Double) {
        let new = PlateItem(ai: item.ai, name: food.name, detail: food.brand, per100: food.per100, isLiquid: food.isLiquid,
                            grams: grams.rounded(), suggested: grams, foodKey: food.key, source: .picked)
        if let i = plate.firstIndex(where: { $0.id == item.id }) { plate[i] = new } else { plate.append(new) }
    }

    private func log() {
        ctx.log(plate: plate, day: day, time: time ?? defaultTime(for: day))
        dismiss()
    }
}

/// One food on the plate: on or off, how much, and where its numbers come from.
struct PlateRow: View {
    @Binding var item: PlateItem
    let energy: EnergyUnit
    let swap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.m) {
                Button { item.included.toggle() } label: {
                    Image(systemName: item.included ? "checkmark.circle.fill" : "circle")
                        .font(.sectionTitle).foregroundStyle(item.included ? palette.accent : .secondary)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.s) {
                        Text(item.name).font(.cardTitle).lineLimit(2)
                        if (item.ai?.confidence ?? 1) < 0.5 && item.source != .picked {
                            Image(systemName: "questionmark.circle").foregroundStyle(palette.warning).help("Not sure about this one: check it")
                        }
                    }
                    HStack(spacing: Space.s) {
                        badge
                        if let d = item.detail { Text(d).font(.note).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
                Spacer(minLength: 4)
                Menu {
                    ForEach(item.options.prefix(5), id: \.key) { o in
                        Button("\(o.name) · \(number(o.per100.kcal)) kcal/100 g") { use(o) }
                    }
                    Button("Search for another…", systemImage: "magnifyingglass", action: swap)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.bodyEmphasis)
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            if item.included {
                HStack(spacing: Space.m) {
                    Button { item.grams = max(0, (item.grams - step).rounded()) } label: { Image(systemName: "minus") }
                        .buttonStyle(.bordered)
                    VStack(spacing: Space.xxs) {
                        Text("\(number(item.grams)) \(item.unit)").font(.numberMedium).monospacedDigit()
                        if item.ai != nil, item.grams != item.suggested {
                            Text("suggested \(number(item.suggested))").font(.fine).foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: 90)
                    Button { item.grams = (item.grams + step).rounded() } label: { Image(systemName: "plus") }
                        .buttonStyle(.bordered)
                    Spacer()
                    VStack(alignment: .trailing, spacing: Space.xxs) {
                        Text(energy.format(item.nutrients.kcal)).font(.secondaryEmphasis).monospacedDigit()
                        Text("P \(number(item.nutrients.protein)) · F \(number(item.nutrients.fat)) · C \(number(item.nutrients.carbs))")
                            .font(.note).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Slider(value: $item.grams, in: 0...max(item.suggested * 2.5, item.grams, 60), step: 5)
                    .tint(palette.accent)
            }
        }
        .padding(Space.l)
        .modifier(CardSurface(cornerRadius: Radius.l))
        .opacity(item.included ? 1 : 0.6)
    }

    private var step: Double { item.grams >= 200 ? 25 : item.grams >= 60 ? 10 : 5 }

    @ViewBuilder private var badge: some View {
        let (text, color): (String, Color) = {
            switch item.source {
            case .yours: return ("Your food", .green)
            case .product: return ("Barcode", palette.accent)
            case .generic: return ("USDA", .teal)
            case .estimate: return ("≈ Estimate", .orange)
            case .picked: return ("Chosen", palette.accent)
            case .dish: return ("Dish", palette.calories)
            }
        }()
        Text(text).font(.fineLabel).foregroundStyle(color)
            .padding(.horizontal, Space.s).padding(.vertical, Space.xxs)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func use(_ o: FoodResult) {
        item.per100 = o.per100; item.detail = o.name; item.product = o; item.foodKey = nil
        item.isLiquid = o.isLiquid; item.source = .generic
    }
}

/// Settings → Photo logging: which model, and the Gemini key.
struct PhotoAISection: View {
    @AppStorage("photoEngine") private var engine: PhotoAI.Engine = .auto
    @State private var geminiKey = Secrets.get("geminiKey")
    @AppStorage("geminiModel") private var geminiModel = ""
    #if os(macOS)
    @AppStorage("localVisionModel") private var localModel = ""
    @State private var status = "Checking…"
    #endif

    var body: some View {
        Section {
            Picker("Use", selection: $engine) { ForEach(PhotoAI.Engine.allCases) { Text($0.label).tag($0) } }
            #if os(macOS)
            LabeledContent("Model on this Mac", value: status)
            TextField("Model", text: $localModel, prompt: Text("qwen3-vl:8b"))
            #endif
            SecureField("Gemini API key", text: $geminiKey, prompt: Text("Paste your free key"))
                .onChange(of: geminiKey) { _, v in Secrets.set("geminiKey", v) }
            Link("Get a free Gemini key", destination: URL(string: "https://aistudio.google.com/apikey")!)
            TextField("Gemini model", text: $geminiModel, prompt: Text("gemini-flash-latest"))
        } header: {
            Text("Photo logging")
        } footer: {
            Text("Your Mac's model is free and private: photos never leave your devices (the iPhone sends them through sync, so the Mac must be on with Gym open). Gemini's free tier works anywhere with internet; Google may use what you send it on the free tier to improve its models.")
        }
        #if os(macOS)
        .task { await check() }
        #endif
    }

    #if os(macOS)
    private func check() async {
        guard let (data, _) = try? await URLSession.shared.data(from: URL(string: "\(PhotoAI.ollama)/api/tags")!) else {
            status = "Ollama isn't running"; return
        }
        let names = (((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["models"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        status = names.contains(PhotoAI.localModel) ? "Ready" : "\(PhotoAI.localModel) not installed"
    }
    #endif
}
