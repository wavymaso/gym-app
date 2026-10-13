import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @State private var confirmReset = false
    @AppStorage("usdaKey") private var usdaKey = ""
    @State private var importing = false

    var body: some View {
        Form {
            if let p = profiles.first {
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
                } header: {
                    Text("Food search")
                } footer: {
                    Text("Plain foods come from USDA FoodData Central. The shared demo key allows only a few searches an hour; your own key is free and unlimited. Products come from Open Food Facts and need no key.")
                }
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
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .sheet(isPresented: $importing) { ImportView() }
        .confirmationDialog("Delete all your data and start again?", isPresented: $confirmReset) {
            Button("Delete everything", role: .destructive, action: reset)
        }
    }

    private func binding<T>(_ p: Profile, _ key: ReferenceWritableKeyPath<Profile, T>) -> Binding<T> {
        Binding(get: { p[keyPath: key] }, set: { p[keyPath: key] = $0; try? ctx.save() })
    }

    private func reset() {
        for m in allModels { try? ctx.delete(model: m) }
        try? ctx.save()
    }
}
