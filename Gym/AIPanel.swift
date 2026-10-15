import PhotosUI
import SwiftData
import SwiftUI
#if os(iOS)
import AVFoundation
import VisionKit
#endif

struct AIPanel: View {
    var startCamera = false
    var describe = false
    let add: ([PlateItem]) -> Void
    var searchInstead: ((String) -> Void)? = nil
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @State private var mode = 0                 // 0 Snap, 1 Describe
    @State private var photos: [(jpeg: Data, image: CGImage)] = []
    @State private var text = ""
    @State private var camera = false
    @State private var library: [PhotosPickerItem] = []
    @State private var working = false
    @State private var error: String?
    @State private var plate: [PlateItem] = []
    @State private var seenBy = ""
    @State private var swapping: PlateItem?
    @State private var started = false

    var body: some View {
        Group {
            if !plate.isEmpty { plateView } else { input }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $camera) { CameraPicker { use($0) }.ignoresSafeArea() }
        #endif
        .onChange(of: library) { _, items in
            Task {
                for i in items { if let d = try? await i.loadTransferable(type: Data.self) { use(d) } }
                library = []
            }
        }
        .sheet(item: $swapping) { item in
            AddFoodView(mode: .pick({ food, grams in replace(item, with: food, grams: grams) }), initialQuery: item.ai?.search ?? item.name)
                .environment(\.pickTitle, "Use this")
        }
        .onAppear {
            guard !started else { return }
            started = true
            if describe { mode = 1 }
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "photoDemo") {        // testing only: a canned answer
                let items = PhotoAI.parse(#"{"items":[{"name":"Air fried potato fries","name_es":"Patatas fritas al aire","search":"potato fries","amount":"1 serving","grams":200,"kcal_100g":180,"protein_100g":2,"fat_100g":10,"carbs_100g":20,"confidence":0.8,"ingredients":[{"name":"Potato","name_es":"Patata","search":"potato baked","amount":"1 medium","grams":185,"kcal_100g":93,"protein_100g":2.5,"fat_100g":0.1,"carbs_100g":21,"confidence":0.8},{"name":"Olive oil","name_es":"Aceite de oliva","search":"oil olive","amount":"1 tbsp","grams":13.5,"kcal_100g":884,"protein_100g":0,"fat_100g":100,"carbs_100g":0,"assumed":true,"likelihood":0.85},{"name":"Salt","name_es":"Sal","search":"salt table","amount":"1 pinch","grams":1,"kcal_100g":0,"protein_100g":0,"fat_100g":0,"carbs_100g":0}]},{"name":"Coke Zero","name_es":"Coca-Cola Zero","search":"soft drink diet cola","amount":"1 can","grams":330,"kcal_100g":0.3,"protein_100g":0,"fat_100g":0,"carbs_100g":0,"liquid":true,"confidence":0.9,"ingredients":[]}]}"#)
                plate = ctx.plate(from: items); seenBy = "Gemini"
            }
            #endif
            #if os(iOS)
            if startCamera { camera = true }
            #endif
        }
    }

    private var input: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("", selection: $mode) { Text("Snap").tag(0); Text("Describe").tag(1) }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 240)
                HStack { Text("Photos").font(.headline); Spacer(); Text("\(photos.count)/3").foregroundStyle(.secondary) }
                if !photos.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(photos.indices, id: \.self) { i in
                            Image(decorative: photos[i].image, scale: 1).resizable().scaledToFill()
                                .frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button { photos.remove(at: i) } label: {
                                        Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .buttonStyle(.plain).padding(4)
                                }
                        }
                    }
                }
                HStack(spacing: 10) {
                    #if os(iOS)
                    Button { camera = true } label: {
                        Label("Capture", systemImage: "camera.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                            .background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain).disabled(photos.count >= 3)
                    #endif
                    PhotosPicker(selection: $library, maxSelectionCount: max(1, 3 - photos.count), matching: .images) {
                        Image(systemName: "icloud.and.arrow.up.fill").font(.title3).frame(width: 64, height: 54)
                            #if os(macOS)
                            .frame(maxWidth: .infinity)
                            #endif
                            .background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain).disabled(photos.count >= 3)
                }
                if mode == 1 || !text.isEmpty {
                    HStack { Text("Description").font(.headline); Spacer(); Text("\(text.count)/500").foregroundStyle(.secondary) }
                    TextField(mode == 1 ? "Describe your meal" : "Anything the photo can't show", text: $text, axis: .vertical)
                        .lineLimit(3...8).padding(14)
                        .background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onChange(of: text) { _, t in if t.count > 500 { text = String(t.prefix(500)) } }
                } else {
                    Button("Add a description") { mode = 1 }.font(.callout)
                }
                if let error, !working {
                    ProblemCard(title: "The AI couldn't read this", message: error, actions: problemActions)
                }
                if working {
                    WorkingCard(title: PhotoAI.engine == .gemini ? "Gemini is looking at your meal…" : "Looking at your meal…",
                                detail: "Splitting it into foods and ingredients. Usually 5–20 seconds; longer when Gemini is busy.")
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            Button { Task { await analyse() } } label: {
                Text("Analyze").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(PadButtonStyle(kind: canAnalyse ? .primary : .dark))
            .disabled(!canAnalyse || working)
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    private var problemActions: [(label: String, run: () -> Void)] {
        var a: [(label: String, run: () -> Void)] = [("Try again", { Task { await analyse() } })]
        if let searchInstead {
            let q = text.split(whereSeparator: { ",.;\n".contains($0) }).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
            a.append(("Search instead", { searchInstead(String(q.prefix(40))) }))
        }
        if !photos.isEmpty && mode != 1 { a.append(("Describe it instead", { animate { mode = 1 } })) }
        return a
    }

    private var canAnalyse: Bool { !photos.isEmpty || text.trimmingCharacters(in: .whitespaces).count >= 3 }

    private func use(_ d: Data) {
        guard photos.count < 3, let p = PhotoAI.prepare(d) else { return }
        photos.append((p.jpeg, p.image))
    }

    private func analyse() async {
        working = true; error = nil
        defer { working = false }
        var found: [PlateItem] = []
        for p in photos {
            for code in await PhotoAI.barcodes(in: p.image) {
                var product = LocalFoods.shared.product(barcode: code)
                if product == nil { product = try? await FoodAPI.product(barcode: code) }
                if let r = product, !found.contains(where: { $0.product?.key == r.key }) {
                    let g = r.servings.first?.grams ?? 100
                    found.append(PlateItem(name: r.name, detail: r.brand, per100: r.per100, isLiquid: r.isLiquid, grams: g, suggested: g,
                                           product: r, source: .product))
                }
            }
        }
        do {
            let (items, by) = try await PhotoAI.analyse(images: photos.map(\.jpeg), text: text)
            var matched = ctx.plate(from: items)
            var skip = found.count
            for i in matched.indices where skip > 0 && matched[i].ai?.packaged == true { matched[i].included = false; skip -= 1 }
            animate(Motion.snappy) { plate = found + matched }
            seenBy = by
            if plate.isEmpty { error = "No food found. Try a closer photo in better light, or describe it." }
        } catch {
            if found.isEmpty { self.error = error.localizedDescription } else { plate = found; seenBy = "barcode" }
        }
    }

    private var plateView: some View {
        let energy = profiles.first?.energy ?? .kcal
        let total = plate.filter(\.included).reduce(Nutrients.zero) { $0 + $1.nutrients }
        return ScrollView {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(energy.format(total.kcal)).font(.number(28))
                        Text("P \(number(total.protein)) · F \(number(total.fat)) · C \(number(total.carbs)) · seen by \(seenBy)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Start over") { plate = []; photos = []; text = "" }.font(.callout)
                }
                Text("AI Plate").font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                ForEach($plate) { $item in AIPlateCard(item: $item, energy: energy, swap: { swapping = $0 }) }
                if plate.contains(where: { $0.children.contains(where: \.assumed) }) {
                    Label("Rows marked ✦ are inferred, not seen: mostly cooking oil and butter, with how likely they are. Change or remove them if you know better.",
                          systemImage: "drop.fill").font(.caption).foregroundStyle(.secondary)
                }
                Text("AI can make mistakes, so always check its results.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                PlateNutrition(plate: total, day: ctx.entries(on: dayKey()).reduce(Nutrients.zero) { $0 + $1.nutrients },
                               target: ctx.dayTargets(on: dayKey()), energy: energy)
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                add(plate); plate = []; photos = []; text = ""
            } label: {
                Text("Add \(plate.filter(\.included).count) to cart").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(PadButtonStyle(kind: .primary)).disabled(!plate.contains(where: \.included))
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    private func replace(_ item: PlateItem, with food: Food, grams: Double) {
        var new = PlateItem(ai: item.ai, name: food.name, detail: food.brand, per100: food.per100, isLiquid: food.isLiquid,
                            grams: grams.rounded(), suggested: grams, foodKey: food.key, source: .picked)
        new.amount = "\(number(grams.rounded())) \(food.baseUnit)"
        for i in plate.indices {
            if plate[i].id == item.id { plate[i] = new; return }
            if let j = plate[i].children.firstIndex(where: { $0.id == item.id }) { plate[i].children[j] = new; return }
        }
    }
}

/// One food on the AI plate, MacroFactor-style: emoji, name, macros, an amount chip; a dish opens to
/// its ingredients, each with its own amount (and inferred oil marked, with how likely it is).
struct AIPlateCard: View {
    @Binding var item: PlateItem
    let energy: EnergyUnit
    let swap: (PlateItem) -> Void
    @State private var open = true

    var body: some View {
        VStack(spacing: 0) {
            row($item, top: true)
            if item.isDish {
                Divider().padding(.leading, 16)
                Button { animate(Motion.snappy) { open.toggle() } } label: {
                    HStack {
                        Text(open ? "Collapse Ingredients" : "Show \(item.children.count) Ingredients").font(.subheadline)
                        Spacer()
                        Image(systemName: open ? "chevron.up" : "chevron.down").font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if open {
                    ForEach($item.children) { $c in
                        row($c, top: false)
                        if c.id != item.children.last?.id { Divider().padding(.leading, 72) }
                    }
                }
            }
        }
        .modifier(CardSurface(cornerRadius: Radius.l))
        .opacity(item.included ? 1 : 0.5)
    }

    private func row(_ x: Binding<PlateItem>, top: Bool) -> some View {
        let v = x.wrappedValue, n = v.nutrients
        return HStack(spacing: 12) {
            Button { animate { x.wrappedValue.included.toggle() } } label: {
                Text(foodEmoji(name: v.name, brand: nil)).font(.system(size: top ? 30 : 26)).frame(width: 44)
                    .overlay(alignment: .bottomTrailing) {
                        if !v.included { Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(palette.warn) }
                    }
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if v.assumed { Image(systemName: "sparkles").font(.caption).foregroundStyle(palette.fat) }
                    Text(v.name).font(.body).lineLimit(2)
                    if v.source == .estimate { Text("≈").font(.caption.weight(.bold)).foregroundStyle(palette.warn) }
                }
                (Text("\(number(energy.fromKcal(n.kcal)))") + Text(Image(systemName: "flame.fill")).font(.caption2)
                 + Text("  \(number(n.protein))P  \(number(n.fat))F  \(number(n.carbs))C  •  \(number(v.totalGrams)) \(v.unit)"))
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                if v.assumed {
                    Text("Likely \(Int((v.ai?.likelihood ?? 0.6) * 100))%: inferred from how it's usually cooked").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            amountChip(x)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contextMenu {
            if !v.isDish { Button("Swap for another food", systemImage: "arrow.triangle.2.circlepath") { swap(v) } }
            Button(v.included ? "Leave out" : "Include", systemImage: v.included ? "minus.circle" : "plus.circle") { x.wrappedValue.included.toggle() }
        }
    }

    /// "1 serving" / "13,5 g": tap to change it.
    private func amountChip(_ x: Binding<PlateItem>) -> some View {
        let v = x.wrappedValue
        return Menu {
            if v.isDish {
                ForEach([0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { s in
                    Button("\(number(s, digits: 2)) serving\(s == 1 ? "" : "s")") { x.wrappedValue.setServings(s) }
                }
            } else {
                let g = v.grams
                ForEach([0.0, 0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { k in
                    Button(k == 0 ? "None" : "\(number((g * k).rounded())) \(v.unit)") {
                        if k == 0 { x.wrappedValue.included = false } else { x.wrappedValue.grams = (g * k).rounded(); x.wrappedValue.included = true }
                    }
                }
                Divider()
                Button("Swap for another food…", systemImage: "magnifyingglass") { swap(v) }
            }
        } label: {
            VStack(spacing: 0) {
                Text(v.isDish ? number(v.servings, digits: v.servings == v.servings.rounded() ? 0 : 2) : (v.amount.isEmpty ? number(v.grams) : leadingNumber(v.amount)))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(v.isDish ? (v.servings == 1 ? "serving" : "servings") : (v.amount.isEmpty ? v.unit : unitWord(v.amount)))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 92, height: 50)
            .background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .menuStyle(.button).buttonStyle(.plain)
    }

    private func leadingNumber(_ s: String) -> String { s.split(separator: " ").first.map(String.init) ?? s }
    private func unitWord(_ s: String) -> String { s.split(separator: " ").dropFirst().joined(separator: " ") }
}

/// Plate or day: what this adds, against today's targets.
struct PlateNutrition: View {
    let plate: Nutrients
    let day: Nutrients
    let target: Targets?
    let energy: EnergyUnit
    @State private var showDay = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nutrition").font(.title2.bold())
                Spacer()
                Picker("", selection: $showDay) { Text("Plate").tag(false); Text("Day").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 160)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Macro.allCases, id: \.self) { m in tile(m) }
            }
        }
        .padding(.top, 8)
    }

    private func tile(_ m: Macro) -> some View {
        let p = m.value(plate.targets), d = m.value(day.targets), t = target.map { m.value($0) } ?? 0
        let conv: (Double) -> Double = { m == .calories ? energy.fromKcal($0) : $0 }
        let u = m == .calories ? energy.rawValue : "g"
        return VStack(alignment: .leading, spacing: 10) {
            Text(m.label).font(.headline)
            Text(showDay ? "\(number(conv(d + p))) / \(number(conv(t))) \(u)" : "\(number(conv(p))) \(u)").font(.subheadline).monospacedDigit()
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.raisedBackground)
                    if showDay { Capsule().fill(m.color.opacity(0.4)).frame(width: g.size.width * min(t > 0 ? d / t : 0, 1)) }
                    Capsule().fill(m.color)
                        .frame(width: g.size.width * min(t > 0 ? p / t : 0, 1))
                        .offset(x: showDay ? g.size.width * min(t > 0 ? d / t : 0, 1) : 0)
                }
            }
            .frame(height: 6)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardSurface(cornerRadius: 16))
    }
}
