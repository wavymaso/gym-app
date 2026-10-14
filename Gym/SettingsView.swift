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

    var body: some View {
        Form {
            if let p = profiles.first {
                #if os(macOS)
                SyncSection()
                #else
                MacSyncSection()
                #endif
                AppearanceSection()
                Section("Feature settings") {
                    NavigationLink { WeightTrendSettingsView() } label: { Label("Weight trend", systemImage: "chart.line.uptrend.xyaxis") }
                    NavigationLink { ExpenditureSettingsView() } label: { Label("Expenditure", systemImage: "flame") }
                }
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
                Section {
                    TextField("USDA API key", text: $usdaKey, prompt: Text("Using the shared demo key"))
                    Link("Get a free key (takes a minute)", destination: URL(string: "https://fdc.nal.usda.gov/api-key-signup")!)
                    if LocalFoods.shared.available {
                        LabeledContent("Built-in products", value: "\(number(Double(LocalFoods.shared.count))) · \(LocalFoods.shared.built)")
                        Text("Spain (Alcampo, Mercadona, Costco and more), Saudi Arabia and the Gulf, from Open Food Facts. Searched first and works offline.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Food search")
                } footer: {
                    Text("Plain foods come from USDA FoodData Central. The shared demo key allows only a few searches an hour; your own key is free and unlimited. Products come from Open Food Facts and need no key.")
                }
                ActivitySection()
                RemindersSection()
                HealthSection()
                BackupSection()
                ExportSection()
                Section {
                    Button("Import from MacroFactor…") { importing = true }
                } footer: {
                    Text("Weight, daily nutrition, expenditure and targets from the Quick Export; food log and workouts from the Granular Export.")
                }
                Section {
                    Button("Start over…", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Deletes everything in this app on this device and goes back to setup.")
                }
            }
        }
        .themedForm()
        .navigationTitle("Settings")
        #if DEBUG
        .navigationDestination(isPresented: Binding(get: { debugSub != nil }, set: { if !$0 { debugSub = nil } })) {
            if debugSub == "expenditure" { ExpenditureSettingsView() } else { WeightTrendSettingsView() }
        }
        #endif
        .sheet(isPresented: $importing) { ImportView() }
        .confirmationDialog("Delete all your data and start again?", isPresented: $confirmReset) {
            Button("Delete everything", role: .destructive, action: reset)
        }
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
    @AppStorage("theme") private var theme: AppTheme = .midnight
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Section("Appearance") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: isPhone ? 96 : 120), spacing: 12)], spacing: 12) {
                ForEach(AppTheme.allCases) { t in
                    Button { theme = t } label: { tile(t) }.buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
            Text(theme.detail).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func tile(_ t: AppTheme) -> some View {
        let p = t.palette(systemDark: scheme == .dark)
        return VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(p.background)
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
