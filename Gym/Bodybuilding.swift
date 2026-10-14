import Charts
import SwiftData
import SwiftUI

// For lifters: refeeds and diet breaks, protein spread across meals, and whether you're keeping
// your strength while you cut (with a deload when it says so).

// MARK: - Refeeds and diet breaks (the rules are in Models.swift)

struct RefeedSheet: View {
    let profile: Profile
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var weekday = 0
    @State private var extra = 400.0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Refeed day", selection: $weekday) {
                        Text("None").tag(0)
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { Text(weekdayName($0)).tag($0) }
                    }
                    if weekday > 0 {
                        Stepper(value: $extra, in: 150...1200, step: 50) {
                            LabeledContent("Extra", value: "\(profile.energy.format(extra)) · \(number(extra / 4)) g carbs")
                        }
                    }
                } footer: {
                    Text("Once a week, a high-carb day: fuller muscles and a better session, and a mental break while cutting. The other six days give the calories back evenly, so your week and your rate of loss stay the same. Put it on your hardest training day (legs, usually).")
                }
            }
            .themedForm()
            .navigationTitle("Refeed day")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if weekday > 0 && profile.refeedWeekday == 0 { profile.refeedSince = dayKey() }
                        profile.refeedWeekday = weekday; profile.refeedExtraKcal = weekday > 0 ? extra : 0; ctx.commit(); dismiss()
                    }
                }
            }
        }
        .appStyle()
        .presentationDetents([.medium, .large])
        .onAppear { weekday = profile.refeedWeekday; if profile.refeedExtraKcal > 0 { extra = profile.refeedExtraKcal } }
    }
}

struct DietBreakSheet: View {
    let profile: Profile
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @State private var weeks = 2

    var body: some View {
        let active = profile.inDietBreak(dayKey())
        let planned = !profile.dietBreakEnd.isEmpty && profile.dietBreakEnd >= dayKey()
        NavigationStack {
            Form {
                if planned {
                    Section {
                        LabeledContent(active ? "On a break until" : "Planned", value:
                            "\(date(fromKey: profile.dietBreakStart).formatted(.dateTime.day().month(.abbreviated).locale(appLocale))) – \(date(fromKey: profile.dietBreakEnd).formatted(.dateTime.day().month(.abbreviated).locale(appLocale)))")
                        Button(active ? "End the break now" : "Cancel it", role: .destructive) {
                            profile.dietBreakStart = ""; profile.dietBreakEnd = ""; ctx.commit(); dismiss()
                        }
                    }
                }
                Section {
                    DatePicker("Starts", selection: $start, in: Date()..., displayedComponents: .date)
                    Picker("Length", selection: $weeks) { Text("1 week").tag(1); Text("2 weeks").tag(2); Text("3 weeks").tag(3) }
                        .pickerStyle(.segmented)
                } header: {
                    Text(planned ? "Plan a new one" : "Plan a diet break")
                } footer: {
                    Text("Eat at maintenance (your current expenditure) for a week or two, protein unchanged. After 8–12 weeks of cutting it restores training quality, hunger and adherence; the scale may go up a little from water and glycogen, not fat. Your goal carries on afterwards.")
                }
            }
            .themedForm()
            .navigationTitle("Diet break")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let s = dayKey(start)
                        profile.dietBreakStart = s; profile.dietBreakEnd = addDays(s, weeks * 7 - 1); ctx.commit(); dismiss()
                    }
                }
            }
        }
        .appStyle()
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Protein per meal

/// Protein spread over the day's meals. About 0,4 g per kg per meal (≈ 30–50 g) is the amount that
/// maxes out muscle building from one sitting; four such meals beat one huge one.
struct ProteinMealsCard: View {
    let days: [String]                       // one day, or the last week (averaged per logged day)
    @Environment(\.modelContext) private var ctx
    @Query(sort: \WeightEntry.day, order: .reverse) private var weights: [WeightEntry]

    var body: some View {
        let first = days.min() ?? dayKey(), last = days.max() ?? dayKey()
        let entries = (try? ctx.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.day >= first && $0.day <= last }))) ?? []
        let logged = max(1, Set(entries.map(\.day)).count)
        let kg = trendSeries(weights.map { DayValue(day: $0.day, value: $0.kg) }, through: dayKey()).last?.trend ?? 75
        let per = roundTo(0.4 * kg, 1)
        let byMeal = Dictionary(grouping: entries) { Meal(time: $0.time) }.mapValues { $0.reduce(0) { $0 + $1.nutrients.protein } / Double(logged) }
        let hits = Meal.allCases.filter { (byMeal[$0] ?? 0) >= per * 0.85 }.count
        Card(title: days.count > 1 ? "Protein per meal · 7-day average" : "Protein per meal", systemImage: "fork.knife") {
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(Meal.allCases) { m in
                    let g = byMeal[m] ?? 0
                    VStack(spacing: 6) {
                        Text("\(number(g)) g").font(.caption.weight(.semibold)).monospacedDigit()
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6).fill(Color.raisedBackground).frame(height: 90)
                            RoundedRectangle(cornerRadius: 6).fill(g >= per * 0.85 ? palette.protein : palette.protein.opacity(0.45))
                                .frame(height: min(90, 90 * g / max(per * 1.6, 1)))
                                .shadow(color: GlowStyle.on && g >= per * 0.85 ? palette.protein.opacity(0.6) : .clear, radius: 5)
                            Rectangle().fill(Color.primary.opacity(0.7)).frame(height: 2).offset(y: -90 * (per / (per * 1.6)))
                        }
                        .frame(maxWidth: 46)
                        Image(systemName: m.icon).font(.caption).foregroundStyle(m.color)
                        Text(m.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("\(hits) of 4 meals reach about \(number(per)) g (0,4 g per kg). Spreading protein over 3–5 meals builds more muscle than the same total in one or two.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Strength while cutting, and deloads

/// For your main lifts: best estimated 1RM each week, how it's moving, and against body weight.
/// Strength holding while weight drops = muscle kept. Two weeks of falling lifts = time to deload.
struct StrengthRetentionCard: View {
    let unit: WeightUnit
    @Environment(\.modelContext) private var ctx
    @Query private var sets: [WorkoutSet]
    @Query(sort: \WeightEntry.day) private var weights: [WeightEntry]

    init(unit: WeightUnit) {
        self.unit = unit
        let from = addDays(dayKey(), -62)
        _sets = Query(filter: #Predicate<WorkoutSet> { $0.day >= from && $0.done })
    }

    struct Lift: Identifiable {
        let key: String, name: String
        let weekly: [(week: String, e1rm: Double)]
        var id: String { key }
        var change: Double? {          // last 2 weeks' best vs the 4 before
            guard weekly.count >= 3 else { return nil }
            let recent = weekly.suffix(2).map(\.e1rm).max()!, before = weekly.dropLast(2).suffix(4).map(\.e1rm).max()!
            return before > 0 ? recent / before - 1 : nil
        }
    }

    var body: some View {
        let working = sets.filter { $0.kindValue.counts && $0.reps > 0 && $0.reps <= 10 && $0.kg > 0 }   // e1RM is unreliable past 10 reps
        let top = Dictionary(grouping: working, by: \.exerciseKey).sorted { $0.value.count > $1.value.count }.prefix(4)
        let lifts: [Lift] = top.map { key, rows in
            let weekly = Dictionary(grouping: rows) { weekStart($0.day) }
                .map { (week: $0.key, e1rm: $0.value.map(\.e1rm).max() ?? 0) }
                .sorted { $0.week < $1.week }
            return Lift(key: key, name: ctx.exercise(key)?.name ?? key, weekly: weekly)
        }
        let trend = trendSeries(weights.map { DayValue(day: $0.day, value: $0.kg) }, through: dayKey())
        let bwNow = trend.last?.trend, bwThen = trend.last { $0.day <= addDays(dayKey(), -42) }?.trend
        let falling = lifts.filter { ($0.change ?? 0) < -0.03 }
        if !lifts.isEmpty {
            Card(title: "Strength retention", systemImage: "figure.strengthtraining.traditional") {
                if let now = bwNow, let then = bwThen {
                    let held = lifts.compactMap(\.change).filter { $0 > -0.02 }.count
                    Text("Body weight \(signed(unit, now - then)) in 6 weeks · \(held) of \(lifts.count) main lifts holding or up")
                        .font(.callout.weight(.semibold))
                }
                ForEach(lifts) { l in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if let e = l.weekly.last?.e1rm {
                                Text("e1RM \(unit.format(e, digits: 0))\(bwNow.map { " · \(number(e / $0, digits: 2))× body weight" } ?? "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        MiniArea(values: l.weekly.map(\.e1rm), color: palette.protein).frame(width: 70, height: 26)
                        if let c = l.change {
                            Delta(text: (c >= 0 ? "+" : "−") + "\(number(abs(c) * 100, digits: 1))%", good: c > -0.02)
                                .frame(width: 66, alignment: .trailing)
                        }
                    }
                }
                if falling.count >= 2 {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.down.heart.fill").foregroundStyle(palette.warn).font(.title3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Time for a deload").font(.subheadline.weight(.bold))
                            Text("\(falling.map(\.name).joined(separator: " and ")) dropped over 3% for two weeks. Take an easy week: same exercises, about half the sets, 3–4 reps in reserve. Strength usually comes back above where it was.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12).background(palette.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Text("Estimated 1RM from your best working set each week (Epley). Holding strength while the scale drops means you're keeping muscle.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
