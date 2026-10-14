import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @State private var confirmReset = false
    @AppStorage("usdaKey") private var usdaKey = ""
    @State private var importing = false
    #if DEBUG
    @State private var debugSub = UserDefaults.standard.string(forKey: "settingsPage")      // testing only: -settingsPage expenditure
    #endif

    @State private var customizing = false

    /// MacroFactor's More page: you, then short groups of rows; each opens one small page.
    var body: some View {
        ScrollView {
            if let p = profiles.first {
                VStack(alignment: .leading, spacing: 22) {
                    if isPhone {
                        Text("MORE").font(.pageTitle(30)).padding(.top, 8)
                    }
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
                        row("bolt.fill", "Expenditure", "Algorithm, starting estimate, modifiers") { ExpenditureSettingsView() },
                        row("chart.line.uptrend.xyaxis", "Weight trend", "How the trend is smoothed") { WeightTrendSettingsView() },
                        row("fork.knife", "Food search", usdaKey.isEmpty ? "USDA demo key" : "Your USDA key") { foodSearchPage },
                    ])
                    group("App", [
                        rowAction("square.grid.2x2", "Dashboard", "Sections, cards, consumed or remaining") { customizing = true },
                        row("mic.fill", "Siri & Shortcuts", "What you can say") { siriPage },
                    ])
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Theme").font(.title2.bold())
                        VStack { AppearanceSection.Grid() }.padding(14).modifier(CardSurface())
                    }
                    group("Progress & tools", [
                        row("scalemass", "Weight & body", "Weigh-ins, measurements, photos") { WeightView() },
                        row("chart.bar.xaxis", "Insights", "Weekly averages and trends") { InsightsView() },
                        row("dumbbell", "Exercise library", "\(((try? ctx.fetchCount(FetchDescriptor<Exercise>())) ?? 0)) exercises") { ExercisesView() },
                    ])
                    group("Data Management", [
                        row("externaldrive", "Backups", "Daily, restore") { page("Backups") { BackupSection() } },
                        row("square.and.arrow.up", "Data export", "Spreadsheet of weight, calories, macros") { page("Export") { ExportSection() } },
                        rowAction("square.and.arrow.down", "Import from MacroFactor", "Quick and granular exports") { importing = true },
                        rowAction("trash", "Start over", "Delete everything on this device", destructive: true) { confirmReset = true },
                    ])
                    Text("Gym · your data stays on your devices").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                .padding(pagePadding)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .pageBackground()
        .navigationTitle("Settings")
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        #if DEBUG
        .navigationDestination(isPresented: Binding(get: { debugSub != nil }, set: { if !$0 { debugSub = nil } })) {
            if debugSub == "expenditure" { ExpenditureSettingsView() } else { WeightTrendSettingsView() }
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
        let name = UserDefaults.standard.string(forKey: "displayName") ?? ""
        return HStack(spacing: 16) {
            Text(initials(name)).font(.system(size: 26, weight: .black).width(.expanded)).foregroundStyle(.black)
                .frame(width: 70, height: 70).background(.white, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                TextField("Your name", text: Binding(get: { UserDefaults.standard.string(forKey: "displayName") ?? "" },
                                                     set: { UserDefaults.standard.set($0, forKey: "displayName") }))
                    .font(.title3.weight(.semibold)).textFieldStyle(.plain)
                if let f = first {
                    Text("Logging since \(date(fromKey: f).formatted(.dateTime.day().month(.wide).year().locale(appLocale)))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16).modifier(CardSurface())
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.map { String($0.prefix(parts.count == 1 ? 2 : 1)) }.joined().uppercased()
        return s.isEmpty ? "ME" : s
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
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title2.bold())
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
        HStack(spacing: 16) {
            Image(systemName: r.icon).font(.title3).frame(width: 28).foregroundStyle(r.destructive ? palette.warn : .primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).foregroundStyle(r.destructive ? palette.warn : .primary)
                Text(r.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
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
                Link("Get a free key (takes a minute)", destination: URL(string: "https://fdc.nal.usda.gov/api-key-signup")!)
                if LocalFoods.shared.available {
                    LabeledContent("Built-in products", value: "\(number(Double(LocalFoods.shared.count))) · \(LocalFoods.shared.built)")
                    Text("Spain (Alcampo, Mercadona, Costco and more), Saudi Arabia and the Gulf, from Open Food Facts, plus USDA's common foods with Spanish names. Searched first, works offline, forgives typos.")
                        .font(.caption).foregroundStyle(.secondary)
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

/// Pick a theme: a small preview of each.
struct AppearanceSection: View {
    /// The theme tiles and style picker on their own (for the More page).
    struct Grid: View {
        var body: some View { AppearanceSection().content }
    }

    @AppStorage("theme") private var theme: AppTheme = .midnight
    @AppStorage("styleLevel") private var style: StyleLevel = .standard
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Section("Appearance") { content }
    }

    @ViewBuilder var content: some View {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: isPhone ? 96 : 120), spacing: 12)], spacing: 12) {
                ForEach(AppTheme.allCases) { t in
                    Button { theme = t } label: { tile(t) }.buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
            Text(theme.detail).font(.callout).foregroundStyle(.secondary)
            Picker("Style", selection: $style) { ForEach(StyleLevel.allCases) { Text($0.label).tag($0) } }
                .pickerStyle(.segmented)
            Text(style == .maximal ? "Glowing rings, bars and charts, gradient card edges." : "Clean and calm.")
                .font(.caption).foregroundStyle(.secondary)
    }

    private func tile(_ t: AppTheme) -> some View {
        let p = t.palette(systemDark: scheme == .dark)
        return VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.background)
                if p.glass {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [p.calories.opacity(0.7), p.protein.opacity(0.45), p.carbs.opacity(0.5)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                if t == .system {      // half and half
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.daylight.background)
                        .mask(HStack(spacing: 0) { Color.clear; Color.black })
                }
                VStack(spacing: 6) {
                    ZStack {
                        Circle().stroke(p.calories.opacity(0.2), lineWidth: 5)
                        Circle().trim(from: 0, to: 0.7).stroke(p.calories, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                    }
                    .frame(width: 30, height: 30)
                    HStack(spacing: 4) {
                        ForEach([p.protein, p.fat, p.carbs], id: \.self) { c in Capsule().fill(c).frame(width: 14, height: 5) }
                    }
                }
                .padding(10)
                .background(p.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .frame(height: 78)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(t == theme ? palette.accent : Color.primary.opacity(0.1), lineWidth: t == theme ? 2.5 : 1))
            Text(t.label).font(.caption.weight(t == theme ? .bold : .regular))
                .foregroundStyle(t == theme ? .primary : .secondary)
        }
        .contentShape(Rectangle())
    }
}
