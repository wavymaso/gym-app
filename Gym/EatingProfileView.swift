import SwiftData
import SwiftUI

extension ModelContext {
    /// Your logged foods (not imported day totals) for the eating profile.
    func loggedFoods(days: Int = 120) -> [LoggedFood] {
        let from = addDays(dayKey(), -days)
        let cal = Calendar.current
        return ((try? fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.day >= from }))) ?? []).compactMap { e in
            guard let k = e.foodKey, !k.isEmpty, e.grams > 0 else { return nil }
            let hm = cal.dateComponents([.hour, .minute], from: e.time)
            return LoggedFood(day: e.day, weekday: cal.component(.weekday, from: date(fromKey: e.day)), minute: (hm.hour ?? 12) * 60 + (hm.minute ?? 0),
                              key: k, name: e.name, grams: e.grams, kcal: e.nutrients.kcal, protein: e.nutrients.protein,
                              fat: e.nutrients.fat, carbs: e.nutrients.carbs, fibre: e.nutrients.fiber ?? 0)
        }
    }

    func eatingProfile() -> EatingProfile {
        let logs = loggedFoods()
        let days = Set(logs.map(\.day))
        let t = Dictionary(uniqueKeysWithValues: days.compactMap { d in dayTargets(on: d).map { (d, DayTarget(kcal: $0.kcal, protein: $0.protein, fat: $0.fat, carbs: $0.carbs)) } })
        return EatingProfile.learn(logs, today: dayKey(), targets: t)
    }
}

/// More → My eating profile.
struct EatingProfileView: View {
    @Environment(\.modelContext) private var ctx
    @State private var profile: EatingProfile?

    var body: some View {
        List {
            if let p = profile {
                Section {
                    if p.enoughData {
                        Text("From \(p.daysUsed) days of logged foods, recent weeks counting most. Updated as you log.").font(.secondaryText).foregroundStyle(.secondary)
                    } else {
                        Label("Only \(p.daysUsed) day\(p.daysUsed == 1 ? "" : "s") with individual foods so far (imported day totals don't count). After about two weeks of normal logging this fills in, and the meal planner can build plans from your own foods.",
                              systemImage: "hourglass").font(.secondaryText).foregroundStyle(.secondary)
                    }
                }
                Section("Your day") {
                    row("Meals a day", "\(p.mealsPerDay)")
                    row("Protein a day", "\(Int(p.proteinPerDay)) g")
                    row("Fibre a day", "\(Int(p.fibrePerDay)) g")
                }
                if !p.misses.isEmpty {
                    Section("Where days usually miss") {
                        ForEach(p.misses, id: \.detail) { m in Label(m.detail, systemImage: "exclamationmark.circle").font(.secondaryText) }
                    }
                }
                ForEach(p.slots, id: \.index) { s in
                    Section("Meal \(s.index + 1) · around \(String(format: "%02d:%02d", s.typicalMinute / 60, s.typicalMinute % 60)) · \(Int(s.protein)) g protein") {
                        if s.foods.isEmpty { Text("Nothing yet").foregroundStyle(.secondary) }
                        ForEach(s.foods.prefix(6), id: \.key) { f in
                            HStack {
                                Text(f.name).lineLimit(1)
                                Spacer()
                                Text("\(Int(f.grams)) g").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
                if !p.together.isEmpty {
                    Section("Eaten together") {
                        ForEach(p.together, id: \.a) { t in Text("\(t.a) + \(t.b) · \(t.times)×").font(.secondaryText) }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .themedList()
        .navigationTitle("My eating profile")
        .task { profile = ctx.eatingProfile() }
    }

    private func row(_ k: String, _ v: String) -> some View { HStack { Text(k); Spacer(); Text(v).foregroundStyle(.secondary).monospacedDigit() } }
}
