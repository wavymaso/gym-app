import PhotosUI
import SwiftData
import SwiftUI
#if os(iOS)
import AVFoundation
import VisionKit
#endif

// One sheet for logging food, the MacroFactor way: a top bar (time, calories with what's in
// the cart, the cart), then Scan · Search · AI · Quick Add · Library. Foods go into a cart with
// "Add" while you keep looking; "Log Foods" logs the whole cart at once.

enum LoggerTab: String, CaseIterable, Identifiable {
    case scan, search, ai, quickAdd, library
    var id: String { rawValue }
    var label: String { ["Scan", "Search", "AI", "Quick Add", "Library"][Self.allCases.firstIndex(of: self)!] }
    var icon: String { ["barcode.viewfinder", "magnifyingglass", "sparkles", "bolt.fill", "books.vertical.fill"][Self.allCases.firstIndex(of: self)!] }
    static var available: [LoggerTab] {
        #if os(iOS)
        return allCases
        #else
        return allCases.filter { $0 != .scan }
        #endif
    }
}

/// Something waiting to be logged: a food and an amount, or a quick add.
struct CartItem: Identifiable {
    let id = UUID()
    var food: Food?
    var name: String
    var amount: Double
    var unit: String
    var quick: Nutrients?

    var nutrients: Nutrients { food?.nutrients(amount, unit: unit) ?? quick ?? .zero }
    var amountText: String {
        guard food != nil else { return "Quick add" }
        let a = number(amount, digits: amount == amount.rounded() ? 0 : 1)
        return ["g", "ml", "oz"].contains(unit) ? "\(a) \(unit)" : (amount == 1 ? unit : "\(a) × \(unit)")
    }
}

struct FoodLogger: View {
    let day: String
    var time: Date? = nil
    var start: LoggerTab? = nil               // nil: the tab you used last
    var startCamera = false                    // AI tab: open the camera straight away
    var describe = false                       // AI tab: start on Describe

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]
    @State private var tab: LoggerTab = .search
    @State private var cart: [CartItem] = []
    @State private var when = Date()
    @State private var chosen: Food?
    @State private var editing: CartItem?
    @State private var pickingTime = false
    @State private var reviewing = false
    @State private var confirmClose = false
    @State private var started = false
    @State private var bump = false
    @State private var searchSeed: String?            // the AI couldn't: search for what you described
    @Namespace private var underline

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                tabStrip
                Group {
                    switch tab {
                    case .scan: scanPanel
                    case .search:
                        AddFoodView(mode: .log(day: day, time: when), initialQuery: searchSeed, embedded: .search, choose: { chosen = $0 }, chooseMeal: add,
                                    quickAdd: { f, a, u in add(f, a, u) }, logFoods: logAll, cartCount: cart.count)
                            .id(searchSeed ?? "")
                    case .ai: AIPanel(startCamera: startCamera && tab == start, describe: describe, add: addPlate,
                                      searchInstead: { q in searchSeed = q; animate(Motion.smooth) { tab = .search } })
                    case .quickAdd: QuickAddPanel { name, n in add(quick: n, name: name) }
                    case .library:
                        AddFoodView(mode: .log(day: day, time: when), embedded: .library, choose: { chosen = $0 }, chooseMeal: add,
                                    quickAdd: { f, a, u in add(f, a, u) }, logFoods: logAll, cartCount: cart.count)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .pageBackground()
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .navigationDestination(item: $chosen) { f in
                FoodDetailView(food: f, day: day,
                               primary: ("Add", { a, u in add(f, a, u); chosen = nil }),
                               secondary: ("Log Foods", { a, u in add(f, a, u); logAll() }),
                               alreadyToday: eatenToday + cartTotal)
            }
            .sheet(item: $editing) { item in
                NavigationStack {
                    if let f = item.food {
                        FoodDetailView(food: f, day: day, initial: (item.amount, item.unit),
                                       primary: ("Save", { a, u in update(item.id, a, u); editing = nil }),
                                       alreadyToday: eatenToday + cartTotal - item.nutrients)
                    }
                }
                .appStyle()
            }
            .sheet(isPresented: $pickingTime) { timeSheet }
            .sheet(isPresented: $reviewing) { cartSheet }
            .confirmationDialog("Discard \(cart.count) food\(cart.count == 1 ? "" : "s") in the cart?", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Log them") { logAll() }
                Button("Discard", role: .destructive) { dismiss() }
            }
        }
        .interactiveDismissDisabled(!cart.isEmpty)
        .onChange(of: tab) { _, t in UserDefaults.standard.set(t.rawValue, forKey: "lastLoggerTab"); Haptics.tick() }
        .appStyle()
        #if os(macOS)
        .frame(width: 640, height: 760)
        #endif
        .onAppear {
            guard !started else { return }
            started = true
            let last = LoggerTab(rawValue: UserDefaults.standard.string(forKey: "lastLoggerTab") ?? "") ?? .search
            let s = start ?? (last == .scan ? .search : last)      // never reopen straight into the camera
            tab = LoggerTab.available.contains(s) ? s : .search
            when = time ?? defaultTime(for: day)
            #if DEBUG
            if let k = UserDefaults.standard.string(forKey: "loggerFood") { chosen = ctx.food(key: k) }   // testing only
            if UserDefaults.standard.bool(forKey: "loggerCart"), let f = ctx.food(key: "custom:demo-oats") {
                cart = [CartItem(food: f, name: f.name, amount: 60, unit: "g"), CartItem(food: nil, name: "Café", amount: 1, unit: "",
                        quick: Nutrients(kcal: 90, protein: 5, fat: 4, carbs: 9))]
            }
            #endif
        }
    }

    // MARK: Top bar: ✕ · time · calories · cart · log

    private var eatenToday: Nutrients { ctx.entries(on: day).reduce(.zero) { $0 + $1.nutrients } }
    private var cartTotal: Nutrients { cart.reduce(.zero) { $0 + $1.nutrients } }

    private var topBar: some View {
        let target = ctx.dayTargets(on: day)?.kcal ?? 0
        let total = eatenToday.kcal + cartTotal.kcal
        return HStack(spacing: 8) {
            circleButton("xmark") { if cart.isEmpty { dismiss() } else { confirmClose = true } }
            Button { pickingTime = true } label: {
                Text(when.formatted(.dateTime.hour().minute().locale(appLocale))).font(.callout.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 14).frame(height: 44)
                    .background(Color.raisedBackground, in: Capsule())
            }
            .buttonStyle(.plain)
            caloriesPill(total, target)
            Button { if !cart.isEmpty { reviewing = true } } label: { cartPill }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.headline).frame(width: 44, height: 44).background(Color.raisedBackground, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func caloriesPill(_ total: Double, _ target: Double) -> some View {
        let p = target > 0 ? total / target : 0
        return Text("\(number(total)) / \(number(target))").font(.callout.weight(.semibold)).monospacedDigit()
            .contentTransition(.numericText()).animation(Motion.snappy, value: total)
            .padding(.horizontal, 14).frame(height: 44)
            .overlay(Capsule().stroke(Color.raisedBackground, lineWidth: 3))
            .overlay(Capsule().trim(from: 0, to: min(p, 1)).stroke(p > 1.05 ? palette.warn : palette.calories,
                                                                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .animation(Motion.snappy, value: p))
            .fixedSize()
    }

    private var cartPill: some View {
        HStack(spacing: 6) {
            if cart.isEmpty {
                Image(systemName: "fork.knife").foregroundStyle(.secondary).padding(.leading, 14)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: -8) {
                    ForEach(cart.suffix(4)) { c in
                        // Each food drops into the cart as a coloured chip.
                        Circle().fill(dominant(c.nutrients)).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.pageBackground, lineWidth: 2))
                            .transition(.asymmetric(insertion: .scale(scale: 0.2).combined(with: .offset(y: -18)).combined(with: .opacity),
                                                    removal: .opacity))
                    }
                }
                .padding(.leading, 12)
                Text("\(cart.count)").font(.callout.weight(.bold)).liveNumber(Double(cart.count))
                Spacer(minLength: 0)
            }
            Button(action: { cart.isEmpty ? dismiss() : logAll() }) {
                Image(systemName: cart.isEmpty ? "chevron.down" : "checkmark").font(.headline)
                    .frame(width: 44, height: 44)
                    .background(cart.isEmpty ? Color.primary.opacity(0.1) : palette.accent, in: Circle())
                    .foregroundStyle(cart.isEmpty ? Color.primary : palette.onAccent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color.raisedBackground, in: Capsule())
        .scaleEffect(bump && !Motion.reduceMotion ? 1.06 : 1)
        .animation(Motion.pick(Motion.bouncy), value: cart.count)
        .animation(Motion.pick(Motion.bouncy), value: bump)
        .onChange(of: cart.count) { old, new in
            guard new > old else { return }
            Haptics.tap()
            bump = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { bump = false }
        }
    }

    /// The colour of the macro that gives most of the calories.
    private func dominant(_ n: Nutrients) -> Color {
        let p = n.protein * 4, f = n.fat * 9, c = n.carbs * 4
        return p >= f && p >= c ? palette.protein : f >= c ? palette.fat : palette.carbs
    }

    // MARK: Tabs

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(LoggerTab.available) { t in
                    Button { animate(Motion.snappy) { tab = t } } label: {
                        VStack(spacing: 8) {
                            Label(t.label, systemImage: t.icon).font(.subheadline.weight(.semibold))
                                .foregroundStyle(tab == t ? .primary : .secondary)
                                .padding(.horizontal, 10)
                            ZStack {
                                Rectangle().fill(.clear).frame(height: 3)
                                if tab == t { Capsule().fill(Color.primary).frame(height: 3).matchedGeometryEffect(id: "u", in: underline) }
                            }
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
    }

    // MARK: The cart

    private func add(_ f: Food, _ amount: Double, _ unit: String) {
        animate(Motion.snappy) { cart.append(CartItem(food: f, name: f.name, amount: amount, unit: unit)) }
    }

    private func add(quick n: Nutrients, name: String) {
        animate(Motion.snappy) { cart.append(CartItem(food: nil, name: name, amount: 1, unit: "", quick: n)) }
    }

    private func add(_ meal: SavedMeal) {
        for it in meal.items {
            if let k = it.foodKey, let f = ctx.food(key: k) {
                cart.append(CartItem(food: f, name: f.name, amount: it.amount, unit: f.units.contains(it.unit) ? it.unit : f.baseUnit))
            } else {
                cart.append(CartItem(food: nil, name: it.name, amount: 1, unit: "", quick: it.nutrients))
            }
        }
        meal.useCount += 1; meal.lastUsed = Date()
    }

    private func addPlate(_ plate: [PlateItem]) {
        for (f, g) in ctx.foods(for: plate) { cart.append(CartItem(food: f, name: f.name, amount: g, unit: f.baseUnit)) }
    }

    private func update(_ id: UUID, _ amount: Double, _ unit: String) {
        if let i = cart.firstIndex(where: { $0.id == id }) { cart[i].amount = amount; cart[i].unit = unit }
    }

    private func logAll() {
        for (i, c) in cart.enumerated() {
            let t = when.addingTimeInterval(Double(i))        // keep the cart's order
            if let f = c.food {
                ctx.log(f, amount: c.amount, unit: c.unit, day: day, time: t)
            } else if let n = c.quick {
                ctx.insert(FoodEntry(day: day, time: t, name: c.name, brand: nil, foodKey: nil, amount: 1, unit: "", grams: 0, nutrients: n))
            }
        }
        ctx.commit()
        #if os(iOS)
        Haptics.success()
        #endif
        cart = []
        dismiss()
    }

    private var cartSheet: some View {
        NavigationStack {
            List {
                ForEach(cart) { c in
                    Button { if c.food != nil { reviewing = false; editing = c } } label: {
                        HStack {
                            Circle().fill(dominant(c.nutrients)).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).lineLimit(1)
                                Text(c.amountText).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(number(c.nutrients.kcal)) kcal").monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { cart.remove(atOffsets: $0) }
                Section {
                    LabeledContent("Total", value: "\(number(cartTotal.kcal)) kcal · P \(number(cartTotal.protein)) · F \(number(cartTotal.fat)) · C \(number(cartTotal.carbs))")
                }
            }
            .themedList()
            .navigationTitle("Cart")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { reviewing = false } }
                ToolbarItem(placement: .confirmationAction) { Button("Log \(cart.count)") { reviewing = false; logAll() }.disabled(cart.isEmpty) }
            }
        }
        .appStyle()
        .presentationDetents([.medium, .large])
    }

    private var timeSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    ForEach(Meal.allCases) { m in
                        Button {
                            when = Calendar.current.date(bySettingHour: m.usual.0, minute: m.usual.1, second: 0, of: date(fromKey: day)) ?? when
                        } label: {
                            VStack(spacing: 4) { Image(systemName: m.icon).foregroundStyle(m.color); Text(m.label).font(.caption2) }
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(Meal(time: when) == m ? m.color.opacity(0.2) : Color.raisedBackground, in: RoundedRectangle(cornerRadius: Radius.m))
                        }
                        .buttonStyle(.plain)
                    }
                }
                DatePicker("Time", selection: $when, displayedComponents: .hourAndMinute)
                    #if os(iOS)
                    .datePickerStyle(.wheel)
                    #endif
                    .labelsHidden()
                Spacer(minLength: 0)
            }
            .padding()
            .pageBackground()
            .navigationTitle("When")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { pickingTime = false } } }
        }
        .appStyle()
        .presentationDetents([.medium])
        #if os(macOS)
        .frame(width: 420, height: 360)
        #endif
    }

    // MARK: Scan

    @ViewBuilder private var scanPanel: some View {
        #if os(iOS)
        ScanPanel(found: { chosen = $0 })
        #else
        EmptyView()
        #endif
    }
}

extension Nutrients {
    static func - (a: Nutrients, b: Nutrients) -> Nutrients {
        Nutrients(kcal: a.kcal - b.kcal, protein: a.protein - b.protein, fat: a.fat - b.fat, carbs: a.carbs - b.carbs)
    }
}

// MARK: - Quick Add

struct QuickAddPanel: View {
    let add: (String, Nutrients) -> Void
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var carbs = ""
    @FocusState private var focus: Int?

    var body: some View {
        let p = parseNumber(protein) ?? 0, f = parseNumber(fat) ?? 0, c = parseNumber(carbs) ?? 0
        let fromMacros = p * 4 + f * 9 + c * 4
        let k = parseNumber(kcal) ?? fromMacros
        ScrollView {
            VStack(spacing: 14) {
                field("Calories", $kcal, unit: "kcal", tag: 0, prompt: fromMacros > 0 ? number(fromMacros) : "0", big: true)
                HStack(spacing: 10) {
                    field("Protein", $protein, unit: "g", tag: 1, color: palette.protein)
                    field("Fat", $fat, unit: "g", tag: 2, color: palette.fat)
                    field("Carbs", $carbs, unit: "g", tag: 3, color: palette.carbs)
                }
                TextField("Name (optional)", text: $name)
                    .padding(14).background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: 14))
                if fromMacros > 0, let typed = parseNumber(kcal), abs(typed - fromMacros) > max(30, typed * 0.15) {
                    Label("The macros add up to \(number(fromMacros)) kcal.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    add(name.isEmpty ? "Quick add" : name, Nutrients(kcal: k, protein: p, fat: f, carbs: c))
                    name = ""; kcal = ""; protein = ""; fat = ""; carbs = ""; focus = nil
                } label: {
                    Text("Add to cart").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent).controlSize(.large).disabled(k <= 0)
            }
            .padding(16)
        }
        .onAppear { focus = 0 }
    }

    private func field(_ label: String, _ text: Binding<String>, unit: String, tag: Int, prompt: String = "0", color: Color = palette.calories,
                       big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(color)
            HStack(alignment: .firstTextBaseline) {
                TextField(prompt, text: text).font(big ? .number(34) : .number(22)).focused($focus, equals: tag)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Text(unit).foregroundStyle(.secondary)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - AI: Snap or Describe, up to 3 photos

// MARK: - Scan: barcode or nutrition label, in the same camera

#if os(iOS)
struct ScanPanel: View {
    let found: (Food) -> Void
    @Environment(\.modelContext) private var ctx
    @State private var mode = 0                  // 0 barcode, 1 label
    @State private var torch = false
    @State private var typing = false
    @State private var typed = ""
    @State private var status: String?
    @State private var looking = false
    @State private var label: LabelValues?
    @State private var scanner: DataScannerViewController?

    var body: some View {
        ZStack(alignment: .top) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                LiveScanner(barcodes: mode == 0, scanner: $scanner) { code in Task { await lookUp(code) } }
                    .id(mode)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView("Camera not available", systemImage: "camera",
                                       description: Text("Allow camera access for Gym in Settings → Privacy & Security → Camera."))
            }
            if mode == 0 {
                RoundedRectangle(cornerRadius: 14).stroke(Tokens.onScrim.opacity(0.8), lineWidth: 3)
                    .frame(width: 300, height: 170).padding(.top, 200).allowsHitTesting(false)
            }
            HStack {
                Picker("", selection: $mode) { Text("Barcode").tag(0); Text("Label").tag(1) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                Spacer()
                if mode == 0 { round("keyboard") { typing = true } }
                round(torch ? "flashlight.on.fill" : "flashlight.off.fill") { torch.toggle(); setTorch(torch) }
            }
            .padding(12)
            VStack {
                Spacer()
                if looking { ProgressView().padding().background(.ultraThinMaterial, in: Circle()) }
                if let status { Text(status).font(.callout).multilineTextAlignment(.center).padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal) }
                if mode == 1 {
                    Button { Task { await captureLabel() } } label: {
                        Circle().fill(Tokens.onScrim).frame(width: 70, height: 70).overlay(Circle().stroke(Tokens.onScrim.opacity(0.5), lineWidth: 4).padding(-6))
                    }
                    .buttonStyle(.plain).padding(.bottom, 30)
                } else {
                    Text("Point at a barcode").font(.callout.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 30)
                }
            }
        }
        .onDisappear { if torch { setTorch(false) } }
        .alert("Type a barcode", isPresented: $typing) {
            TextField("8 or 13 digits", text: $typed).keyboardType(.numberPad)
            Button("Look up") { Task { await lookUp(typed) } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: Binding(get: { label.map { LabelBox(values: $0) } }, set: { if $0 == nil { label = nil } })) { box in
            CustomFoodView(food: nil, prefill: box.values)
        }
    }

    private func round(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.headline).frame(width: 46, height: 46).background(Tokens.scrim, in: Circle()).foregroundStyle(Tokens.onScrim)
        }
        .buttonStyle(.plain)
    }

    private func lookUp(_ code: String) async {
        let c = code.filter(\.isNumber)
        guard c.count >= 6 else { return }
        looking = true; status = nil
        defer { looking = false }
        var r = LocalFoods.shared.product(barcode: c)
        if r == nil || r?.servings.isEmpty == true, let online = try? await FoodAPI.product(barcode: c) { r = online }
        if let r {
            found(ctx.food(for: r))
        } else {
            status = "Barcode \(c) isn't in the databases. Switch to Label and photograph the nutrition table."
        }
    }

    private func captureLabel() async {
        guard let s = scanner else { return }
        looking = true; status = nil
        defer { looking = false }
        do {
            let img = try await s.capturePhoto()
            let r = UIGraphicsImageRenderer(size: img.size)
            guard let cg = r.image(actions: { _ in img.draw(in: CGRect(origin: .zero, size: img.size)) }).cgImage else { return }
            let v = LabelReader.parse(try await LabelReader.rows(from: cg))
            if v.found < 3 || v.kcal == nil {
                status = "Couldn't read enough of the table. Closer, straight on, good light."
            } else {
                label = v
            }
        } catch {
            status = "Couldn't take the photo: \(error.localizedDescription)"
        }
    }

    private func setTorch(_ on: Bool) {
        guard let d = AVCaptureDevice.default(for: .video), d.hasTorch, (try? d.lockForConfiguration()) != nil else { return }
        d.torchMode = on ? .on : .off
        d.unlockForConfiguration()
    }
}

private struct LabelBox: Identifiable { let id = UUID(); let values: LabelValues }

/// The live camera: reads barcodes, or just shows the picture (for a label photo).
private struct LiveScanner: UIViewControllerRepresentable {
    let barcodes: Bool
    @Binding var scanner: DataScannerViewController?
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let types: Set<DataScannerViewController.RecognizedDataType> = barcodes ? [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])] : [.text()]
        let vc = DataScannerViewController(recognizedDataTypes: types, qualityLevel: .balanced, isHighlightingEnabled: barcodes)
        vc.delegate = context.coordinator
        DispatchQueue.main.async { scanner = vc }
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(found: found, barcodes: barcodes) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        let barcodes: Bool
        var last: (String, Date)?
        init(found: @escaping (String) -> Void, barcodes: Bool) { self.found = found; self.barcodes = barcodes }

        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard barcodes else { return }
            for case .barcode(let b) in items {
                guard let code = b.payloadStringValue else { continue }
                if let l = last, l.0 == code, Date().timeIntervalSince(l.1) < 4 { continue }   // the same code again
                last = (code, Date())
                Haptics.success()
                found(code)
            }
        }
    }
}
#endif

