import SwiftUI
import SwiftData

extension ModelContext {
    /// Your meals learned from the log, at the canonical level (Roosterz chicken counts as chicken).
    func mealPatterns() -> MealPatterns {
        var canon: [String: String?] = [:]
        return MealPatterns.learn(loggedFoods(days: 120), canonical: { key in
            if let c = canon[key] { return c }
            let c = self.food(key: key).flatMap { self.taxonomy(of: $0).canonical }
            canon[key] = c
            return c
        }, today: dayKey())
    }

    /// Learned combinations you haven't deleted, with yours (confirmed or edited) in their place.
    func usualMeals() -> [UsualMeal] {
        let s = profile?.planner ?? PlannerSettings()
        let mine = s.usualMeals
        let learned = mealPatterns().combos.filter { c in !s.deletedUsualMeals.contains(c.id) && !mine.contains { $0.id == c.id } }
        return mine + learned
    }
}

/// Planner settings → Your usual meals: food combinations you eat together, per meal. Confirm them so
/// plans reproduce them, edit or delete them.
struct UsualMealsView: View {
    @Environment(\.modelContext) private var ctx
    @State private var meals: [UsualMeal] = []
    @State private var editing: UsualMeal?
    @State private var days = 0

    var body: some View {
        List {
            Section {
                Text("Learned from \(days) day\(days == 1 ? "" : "s") of food-by-food logging. Until there's more history, your templates and staples carry the plan; confirmed combinations are reproduced first.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(MealBand.allCases, id: \.self) { band in
                let list = meals.filter { $0.band == band }
                if !list.isEmpty {
                    Section(band.label) {
                        ForEach(list) { m in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.foods.map { Taxonomy.byID[$0]?.name ?? $0 }.joined(separator: " + "))
                                    Text(m.confirmed ? "yours" : "seen \(m.seen)× · last \(m.lastDay.isEmpty ? "—" : date(fromKey: m.lastDay).formatted(.dateTime.day().month(.abbreviated).locale(appLocale)))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !m.confirmed {
                                    Button { confirm(m) } label: { Image(systemName: "checkmark.circle") }.buttonStyle(.borderless).foregroundStyle(palette.good)
                                        .accessibilityLabel("Confirm")
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { editing = m }
                            .swipeActions { Button("Delete", role: .destructive) { delete(m) } }
                            .contextMenu { Button("Edit") { editing = m }; Button("Delete", role: .destructive) { delete(m) } }
                        }
                    }
                }
            }
            if meals.isEmpty { Section { Text("No combinations yet: log a few meals food by food.").foregroundStyle(.secondary) } }
        }
        .themedList()
        .navigationTitle("Your usual meals")
        .sheet(item: $editing) { m in NavigationStack { UsualMealEditor(meal: m) { saveEdited(original: m, $0) } }.appStyle() }
        .onAppear(perform: load)
    }

    private func load() {
        meals = ctx.usualMeals()
        days = Set(ctx.loggedFoods(days: 120).map(\.day)).count
    }

    private func update(_ change: (inout PlannerSettings) -> Void) {
        guard let p = ctx.profile else { return }
        var s = p.planner; change(&s); p.planner = s; ctx.commit(); load()
    }

    private func confirm(_ m: UsualMeal) { Haptics.tap(); update { s in var c = m; c.confirmed = true; s.usualMeals.removeAll { $0.id == m.id }; s.usualMeals.append(c) } }

    private func delete(_ m: UsualMeal) {
        Haptics.tick()
        update { s in s.usualMeals.removeAll { $0.id == m.id }; if !s.deletedUsualMeals.contains(m.id) { s.deletedUsualMeals.append(m.id) } }
    }

    private func saveEdited(original: UsualMeal, _ edited: UsualMeal) {
        update { s in
            s.usualMeals.removeAll { $0.id == original.id || $0.id == edited.id }
            if edited.id != original.id && !original.confirmed { s.deletedUsualMeals.append(original.id) }   // the learned one is replaced by yours
            var e = edited; e.confirmed = true; s.usualMeals.append(e)
        }
    }
}

struct UsualMealEditor: View {
    @State var meal: UsualMeal
    let save: (UsualMeal) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Picker("Meal", selection: $meal.band) { ForEach(MealBand.allCases, id: \.self) { Text($0.label).tag($0) } }
            Section("Foods") {
                ForEach(Taxonomy.canonical.filter { $0.role != .drink }.sorted { $0.name < $1.name }, id: \.id) { c in
                    if meal.foods.contains(c.id) || meal.foods.count < 6 {
                        Button {
                            if meal.foods.contains(c.id) { if meal.foods.count > 1 { meal.foods.removeAll { $0 == c.id } } } else { meal.foods.append(c.id); meal.foods.sort() }
                        } label: {
                            HStack { Text(c.name); Spacer(); if meal.foods.contains(c.id) { Image(systemName: "checkmark").foregroundStyle(palette.accent) } }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .themedForm()
        .navigationTitle("Edit meal")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save(meal); dismiss() } }
        }
    }
}
