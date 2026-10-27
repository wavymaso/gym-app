import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @State private var confirmReset = false
    @State private var usdaKey = Secrets.get("usdaKey")
    @State private var importing = false
    #if DEBUG
    @State private var debugSub = UserDefaults.standard.string(forKey: "settingsPage")      // testing only: -settingsPage expenditure
    #endif

    @State private var customizing = false
    @AppStorage("displayName") private var displayName = ""
    @State private var editingName = false

    /// MacroFactor's More page: you, then short groups of rows; each opens one small page.
    var body: some View {
        ScrollView {
            if let p = profiles.first {
                VStack(alignment: .leading, spacing: Space.xl) {
                    profileHeader(p)
                    group("General", [
                        row("person.crop.circle", "Profile & units", "\(p.weight.rawValue) · \(p.energy.rawValue) · \(formatHeight(p.heightCm, p.weight))") { profilePage(p) },
                        row("arrow.triangle.2.circlepath", "Integrations", "Mac sync, Apple Health, steps, sleep") { integrationsPage },
                        row("sparkles", "Photo logging (AI)", PhotoAI.engine.label) { page("Photo logging") { PhotoAISection() } },
                        row("bell.badge", "Reminders", "Weigh-in, logging, check-in") { page("Reminders") { RemindersSection() } },
                    ])
                    group("Nutrition & coaching", [
                        row("target", "Strategy & coaching", "Goal, program, check-ins, phases") { StrategyView() },
                        row("leaf", "Nutrient targets", "Fibre, sugar, vitamins and minerals") { NutrientTargetsView() },
                        row("fork.knife.circle", "My eating profile", "What you usually eat, when, and where days miss") { EatingProfileView() },
                        row("bolt.fill", "Expenditure", "Starting estimate, modifiers") { ExpenditureSettingsView() },
                        row("fork.knife", "Food search", usdaKey.isEmpty ? "USDA demo key" : "Your USDA key") { foodSearchPage },
                        row("moon.stars", "Day start", dayStartHour == 0 ? "Midnight" : "\(dayStartHour):00 · late meals count for the day before") { page("Day start") { DayStartSection() } },
                    ])
                    group("App", [
                        rowAction("square.grid.2x2", "Dashboard", "Sections, cards, consumed or remaining") { customizing = true },
                        row("mic.fill", "Siri & Shortcuts", "What you can say") { siriPage },
                    ])
                    VStack(alignment: .leading, spacing: Space.m) {
                        Text("Theme").font(.sectionTitle)
                        VStack { AppearanceSection.Grid() }.padding(Space.l).modifier(CardSurface())
                    }
                    group("Progress & tools", [
                        row("scalemass", "Weight & body", "Weigh-ins, measurements, photos") { WeightView() },
                        row("chart.bar.xaxis", "Insights", "Weekly averages and trends") { InsightsView() },
                        row("dumbbell", "Exercise library", "\(((try? ctx.fetchCount(FetchDescriptor<Exercise>())) ?? 0)) exercises") { ExercisesView() },
                    ])
                    group("Data Management", [
                        row("externaldrive", "Backups", "Daily, restore") { page("Backups") { BackupSection() } },
                        row("square.and.arrow.up", "Data export", "Everything as an archive, or spreadsheets") { page("Export") { ExportSection() } },
                        rowAction("square.and.arrow.down", "Import from MacroFactor", "Quick and granular exports") { importing = true },
                        row("text.bubble", "Coach", "How often it speaks, which AI") { page("Coach") { CoachSettings() } },
                        row("lock", "Privacy & security", "Face ID lock, what leaves this device") { page("Privacy & security") { PrivacySection() } },
                        row("stethoscope", "Diagnostics", "Version, data health, recent problems") { DiagnosticsView() },
                        rowAction("trash", "Start over", "Delete everything on this device", destructive: true) { confirmReset = true },
                    ])
                    Text("Gym · your data stays on your devices").font(.note).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                .padding(pagePadding)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .pageBackground()
        .largeTitle(isPhone ? "More" : "Settings")
        #if DEBUG
        .navigationDestination(isPresented: Binding(get: { debugSub != nil }, set: { if !$0 { debugSub = nil } })) {
            if debugSub == "expenditure" { ExpenditureSettingsView() } else if debugSub == "diagnostics" { DiagnosticsView() } else { DeveloperView() }
        }
        #endif
        .sheet(isPresented: $importing) { ImportView() }
        .sheet(isPresented: $customizing) { CustomizeDashboardView() }
        .confirmationDialog("Delete all your data and start again?", isPresented: $confirmReset) {
            Button("Delete everything", role: .destructive, action: reset)
        }
    }

    // MARK: Pieces

    private func profileHeader(_ p: Profile) -> some View {
        let first = (try? ctx.fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.day)])).first?.day)
        let name = displayName.trimmingCharacters(in: .whitespaces)
        return HStack(spacing: Space.l) {
            // Your initials, or a plain person symbol until you add a name (never placeholder text).
            Group {
                if name.isEmpty { Image(systemName: "person.fill").font(.iconMedium) }
                else { Text(initials(name)).font(.system(size: 26, weight: .black).width(.expanded)) }
            }
            .foregroundStyle(palette.onInverse)
            .frame(width: 70, height: 70).background(palette.inverseFill, in: Circle())
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                if editingName {
                    TextField("Name", text: $displayName).font(.subsectionTitle).textFieldStyle(.plain)
                        .onSubmit { editingName = false }
                } else if name.isEmpty {
                    Button { editingName = true } label: { Label("Add your name", systemImage: "pencil") }
                        .font(.secondaryEmphasis).buttonStyle(.bordered).buttonBorderShape(.capsule)
                } else {
                    Text(name).font(.subsectionTitle).onTapGesture { editingName = true }
                        .accessibilityHint("Double-tap to change your name").accessibilityAddTraits(.isButton)
                }
                if let f = first {
                    Text("Logging since \(date(fromKey: f).formatted(.dateTime.day().month(.wide).year().locale(appLocale)))")
                        .font(.secondaryText).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(Space.l).modifier(CardSurface())
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).map { String($0.prefix(name.split(separator: " ").count == 1 ? 2 : 1)) }.joined().uppercased()
    }

    private struct Row: Identifiable {
        let id = UUID()
        let icon: String, title: String, detail: String
        var destination: AnyView?
        var action: (() -> Void)?
        var destructive = false
    }

    private func row<D: View>(_ icon: String, _ title: String, _ detail: String, @ViewBuilder _ dest: () -> D) -> Row {
        Row(icon: icon, title: title, detail: detail, destination: AnyView(dest()))
    }
    private func rowAction(_ icon: String, _ title: String, _ detail: String, destructive: Bool = false, _ action: @escaping () -> Void) -> Row {
        Row(icon: icon, title: title, detail: detail, action: action, destructive: destructive)
    }

    private func group(_ title: String, _ rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(title).font(.sectionTitle)
            VStack(spacing: 0) {
                ForEach(rows) { r in
                    Group {
                        if let d = r.destination {
                            NavigationLink { d } label: { label(r) }
                        } else {
                            Button { r.action?() } label: { label(r) }
                        }
                    }
                    .buttonStyle(.plain)
                    if r.id != rows.last?.id { Divider().padding(.leading, 58) }
                }
            }
            .modifier(CardSurface())
        }
    }

    private func label(_ r: Row) -> some View {
        HStack(spacing: Space.l) {
            Image(systemName: r.icon).font(.subsectionTitle).frame(width: 28).foregroundStyle(r.destructive ? palette.warn : .primary)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(r.title).foregroundStyle(r.destructive ? palette.warn : .primary)
                Text(r.detail).font(.note).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.secondaryEmphasis).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
        .contentShape(Rectangle())
    }

    /// One existing settings section on its own page.
    private func page<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        Form { content() }.themedForm().navigationTitle(title)
    }

    // MARK: Sub-pages

    private func profilePage(_ p: Profile) -> some View {
        Form {
            Section("Units") {
                Picker("Weight", selection: binding(p, \.weightUnit)) {
                    Text("Kilograms (kg)").tag("kg")
                    Text("Pounds (lb)").tag("lb")
                }
                Picker("Energy", selection: binding(p, \.energyUnit)) {
                    Text("Calories (kcal)").tag("kcal")
                    Text("Kilojoules (kJ)").tag("kJ")
                }
            }
            Section {
                Picker("Sex", selection: binding(p, \.sex)) {
                    ForEach(Sex.allCases) { Text($0.label).tag($0.rawValue) }
                }
                DatePicker("Date of birth", selection: binding(p, \.birthDate), in: ...Date(), displayedComponents: .date)
                HeightField(heightCm: binding(p, \.heightCm), unit: p.weight)
                Picker("Activity", selection: binding(p, \.activity)) {
                    ForEach(Activity.allCases) { Text($0.label).tag($0.rawValue) }
                }
            } header: {
                Text("About you")
            } footer: {
                Text("Only used for the starting expenditure estimate. Once you've logged food and weight for a while, your own data takes over.")
            }
        }
        .themedForm().navigationTitle("Profile & units")
    }

    private var integrationsPage: some View {
        Form {
            #if os(macOS)
            SyncSection()
            #else
            MacSyncSection()
            #endif
            HealthSection()
            ActivitySection()
        }
        .themedForm().navigationTitle("Integrations")
    }

    private var foodSearchPage: some View {
        Form {
            Section {
                TextField("USDA API key", text: $usdaKey, prompt: Text("Using the shared demo key"))
                    .onChange(of: usdaKey) { _, v in Secrets.set("usdaKey", v) }
                Link("Get a free key (takes a minute)", destination: URL(string: "https://fdc.nal.usda.gov/api-key-signup")!)
                if LocalFoods.shared.available {
                    LabeledContent("Built-in products", value: "\(number(Double(LocalFoods.shared.count))) · \(LocalFoods.shared.built)")
                    Text("Spain (Alcampo, Mercadona, Costco and more), Saudi Arabia and the Gulf, from Open Food Facts, plus USDA's common foods with Spanish names. Searched first, works offline, forgives typos.")
                        .font(.note).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Plain foods come from USDA FoodData Central. The shared demo key allows only a few searches an hour; your own key is free and unlimited.")
            }
        }
        .themedForm().navigationTitle("Food search")
    }

    private var siriPage: some View {
        Form {
            Section {
                ForEach(["“Log water in Gym”", "“How many calories do I have left in Gym”", "“Log my weight in Gym”",
                         "“Quick add calories in Gym”", "“Log a meal photo in Gym”", "“Start a workout in Gym”"], id: \.self) { Text($0) }
            } footer: {
                Text("Say them to Siri, or add them in the Shortcuts app, to the Action button or to the lock screen.")
            }
        }
        .themedForm().navigationTitle("Siri & Shortcuts")
    }

    private func binding<T>(_ p: Profile, _ key: ReferenceWritableKeyPath<Profile, T>) -> Binding<T> {
        Binding(get: { p[keyPath: key] }, set: { p[keyPath: key] = $0; ctx.commit() })
    }

    private func reset() {
        for m in allModels { try? ctx.delete(model: m) }
        ctx.commit()
        // The other device keeps its copy: it has to connect again, and takes this one's (empty) data or gives it its own.
        #if os(macOS)
        if SyncServer.shared.enabled { SyncServer.shared.newCode() }
        #else
        SyncClient.shared.disconnect()
        #endif
    }
}

/// Pick the look: a live preview, Appearance, and the Finish as five small metal discs.
struct AppearanceSection: View {
    /// On the More page.
    struct Grid: View {
        var body: some View { AppearanceSection().content }
    }

    @AppStorage("appearance") private var appearance: Appearance = .black
    @AppStorage("finish") private var finish: Finish = .platinum
    @AppStorage("reduceDepth") private var reduceDepth = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Section("Appearance") { content }
    }

    @ViewBuilder var content: some View {
        let t = Tokens.make(appearance.resolved(systemDark: scheme == .dark), finish)
        VStack(alignment: .leading, spacing: Space.l) {
            ThemePreview(t: t, flat: reduceDepth)
            Picker("Appearance", selection: Binding(get: { appearance }, set: { a in Haptics.tick(); appearance = a })) {
                ForEach(Appearance.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            HStack(spacing: 0) {
                ForEach(Finish.allCases) { f in
                    let ft = Tokens.make(t.appearance, f)
                    Button { Haptics.tick(); finish = f } label: {
                        VStack(spacing: Space.s) {
                            Circle().fill(MetalTexture.paint(ft)).frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(t.separator.color.opacity(t.isDark ? 0 : 1), lineWidth: 0.5))
                                .padding(Space.xs)
                                .overlay(Circle().strokeBorder(f == finish ? t.accent.color : .clear, lineWidth: 1.5))
                            Text(f.label).font(f == finish ? Font.fineLabel : Font.fine)
                                .foregroundStyle(f == finish ? Color.primary : .secondary).lineLimit(1).fixedSize()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(f.label)
                    .accessibilityAddTraits(f == finish ? .isSelected : [])
                }
            }
            Toggle(isOn: $reduceDepth) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Reduce depth")
                    Text("Flat: no highlights or edge sheens.").font(.note).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A slice of Today in the chosen look: updates as you change Appearance or Finish.
struct ThemePreview: View {
    let t: Tokens
    var flat = false

    var body: some View {
        HStack(spacing: Space.l) {
            ZStack {
                Circle().stroke(t.raised.color, lineWidth: 8)
                Circle().trim(from: 0, to: 0.66)
                    .stroke(flat ? AnyShapeStyle(t.accent.color)
                                 : AnyShapeStyle(AngularGradient(colors: [t.accentLow.color, t.accent.color, t.accentHigh.color, t.accent.color], center: .center)),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("1 557").font(.system(.title3, design: .default).weight(.semibold)).monospacedDigit().foregroundStyle(t.text1.color)
                    Text("kcal left").font(.fineLabel).foregroundStyle(t.text2.color)
                }
            }
            .frame(width: 86, height: 86)
            VStack(alignment: .leading, spacing: Space.s) {
                bar("Protein", "142 g", t.protein, 0.75)
                bar("Fat", "48 g", t.fat, 0.6)
                bar("Carbs", "201 g", t.carbs, 0.9)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity)
        .background(t.card.color, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .overlay {
            if !flat {
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous).strokeBorder(t.hairline, lineWidth: 0.5)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
            }
        }
        .padding(Space.s)
        .background(t.background.color, in: RoundedRectangle(cornerRadius: Radius.l + Space.s, style: .continuous))
        .accessibilityHidden(true)
    }

    private func bar(_ l: String, _ v: String, _ c: RGB, _ f: Double) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(l).font(.fineLabel).foregroundStyle(t.text2.color)
                Spacer()
                Text(v).font(.fineLabel).monospacedDigit().foregroundStyle(t.text1.color)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(t.raised.color)
                    Capsule().fill(c.color).frame(width: g.size.width * f)
                }
            }
            .frame(height: 4)
        }
    }
}

struct PrivacySection: View {
    var body: some View {
        Section { AppLockToggle() } header: { Text("Lock") }
        Section {
            Label("Your data stays on your phone and your Mac. Sync goes directly between them.", systemImage: "iphone.and.arrow.forward")
            Label("Progress photos never go to any AI and stay out of exports unless you include them.", systemImage: "camera")
            Label("Food photos go to the AI you choose in Photo logging: your Mac only, or Gemini (Google may use free-tier inputs).", systemImage: "sparkles")
            Label("API keys are kept in the Keychain.", systemImage: "key")
        } header: { Text("What leaves this device") }
        .font(.secondaryText)
    }
}


struct DayStartSection: View {
    @AppStorage("dayStartHour") private var hour = 0
    var body: some View {
        Section {
            Picker("Day starts at", selection: $hour) {
                Text("Midnight").tag(0)
                ForEach(1...6, id: \.self) { h in Text(String(format: "%02d:00", h)).tag(h) }
            }
            .onChange(of: hour) { _, _ in dataVersion += 1 }
        } footer: {
            Text("Food logged before this counts for the day before: a late dinner or a night out stays with that day. Weigh-ins and past days don't change.")
        }
        Section {
            Toggle(isOn: Binding(get: { ramadan }, set: { on in
                UserDefaults.standard.set(on ? addDays(dayKey(Date()), 30) : nil, forKey: "ramadanUntil")
                ramadan = on; dataVersion += 1
            })) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Ramadan")
                    Text(ramadan ? "On until \(date(fromKey: UserDefaults.standard.string(forKey: "ramadanUntil") ?? dayKey()).formatted(.dateTime.day().month(.wide).locale(appLocale)))" : "Iftar to suhoor counts as one day")
                        .font(.note).foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("The day starts at 05:00 (or your later choice above), so iftar, the night and suhoor all count as one day. Switches itself off after 30 days.")
        }
    }
    @State private var ramadan = ramadanActive
}
