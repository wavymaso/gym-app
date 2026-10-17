import SwiftUI
import SwiftData

/// Planner settings → Meal templates: the structure of each meal. Edit slots (required or optional,
/// on by default, the default food, which foods are allowed); reset any template to its default.
struct TemplatesView: View {
    @Environment(\.modelContext) private var ctx
    @State private var settings = PlannerSettings()

    var body: some View {
        List {
            Section {
                Text("Each meal is built from these slots, then the portions are sized to hit your targets. Pre- and post-workout replace the meal in the training window; they never add meals.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Evening treat (one a day, after dinner)", isOn: Binding(get: { settings.treatsEnabled }, set: { settings.treatsEnabled = $0; save() }))
            }
            ForEach(settings.mealTemplates) { t in
                NavigationLink {
                    TemplateEditor(template: t, isDefault: !settings.templates.contains { $0.id == t.id }) { edited in
                        settings.templates.removeAll { $0.id == t.id }
                        if let edited, edited != MealTemplates.defaults.first(where: { $0.id == t.id }) { settings.templates.append(edited) }
                        save()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name + (settings.templates.contains { $0.id == t.id } ? " · edited" : ""))
                        Text(t.slots.map { ($0.required ? "" : "optional ") + $0.kind.label.lowercased() }.joined(separator: " + ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .themedList()
        .navigationTitle("Meal templates")
        .onAppear { settings = ctx.profile?.planner ?? PlannerSettings() }
    }

    private func save() {
        guard let p = ctx.profile else { return }
        var s = p.planner
        s.templates = settings.templates; s.treatsEnabled = settings.treatsEnabled
        p.planner = s; ctx.commit()
    }
}

struct TemplateEditor: View {
    @State var template: MealTemplate
    let isDefault: Bool
    let done: (MealTemplate?) -> Void          // nil: back to the default
    @Environment(\.dismiss) private var dismiss
    @State private var reset = false

    var body: some View {
        Form {
            if !template.note.isEmpty { Section { Text(template.note).font(.caption).foregroundStyle(.secondary) } }
            ForEach($template.slots) { $slot in
                Section(slot.kind.label) {
                    Toggle("Required", isOn: $slot.required)
                    if !slot.required { Toggle("On by default (dropped first when calories are tight)", isOn: $slot.defaultOn) }
                    Picker("Default", selection: $slot.defaultFood) {
                        ForEach(slot.allowed, id: \.self) { Text(Taxonomy.byID[$0]?.name ?? $0).tag($0) }
                    }
                    if slot.kind == .spread { Stepper("Up to \(slot.maxFoods)", value: $slot.maxFoods, in: 1...3) }
                    NavigationLink("Allowed foods (\(slot.allowed.count))") { AllowedFoodsView(slot: $slot) }
                }
            }
            if !isDefault { Section { Button("Back to the default", role: .destructive) { reset = true; done(nil); dismiss() } } }
        }
        .themedForm()
        .navigationTitle(template.name)
        .onDisappear { if !reset { done(template) } }
    }
}

struct AllowedFoodsView: View {
    @Binding var slot: TemplateSlot
    var body: some View {
        List(Taxonomy.canonical.filter { $0.role != .drink }.sorted { ($0.role.rawValue, $0.name) < ($1.role.rawValue, $1.name) }, id: \.id) { c in
            Button {
                if let i = slot.allowed.firstIndex(of: c.id) {
                    guard slot.allowed.count > 1 else { return }
                    slot.allowed.remove(at: i)
                    if slot.defaultFood == c.id { slot.defaultFood = slot.allowed[0] }
                } else { slot.allowed.append(c.id) }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) { Text(c.name); Text(c.role.label).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if slot.allowed.contains(c.id) { Image(systemName: "checkmark").foregroundStyle(palette.accent) }
                }
            }
            .buttonStyle(.plain)
        }
        .themedList()
        .navigationTitle("Allowed in \(slot.kind.label.lowercased())")
    }
}
