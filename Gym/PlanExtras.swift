import SwiftData
import SwiftUI

/// "Is this right?" for an entry or meal big enough to be a typo (1 500 kcal, or 60% of the day's
/// target). Until you confirm it, its day is left out of expenditure and the plan doesn't count it.
/// `day` nil: every such day in the last 4 weeks (the dashboard).
struct LargeEntriesCard: View {
    @Environment(\.modelContext) private var ctx
    var day: String? = nil
    var energy: EnergyUnit = .kcal
    @State private var flags: [(day: String, flag: LargeEntryRule.Flag)] = []
    @State private var later: Set<String> = []

    var body: some View {
        Group {
            let shown = flags.filter { !later.contains($0.flag.ids.joined()) }
            if !shown.isEmpty {
                VStack(alignment: .leading, spacing: Space.m) {
                    Label(shown.count == 1 ? "Is this right?" : "Are these right?", systemImage: "exclamationmark.magnifyingglass").font(.cardTitle)
                    Text("Big enough to be a typo (a serving count, or raw vs cooked weight). Until you confirm, this day stays out of your expenditure estimate and the plan doesn't count it.")
                        .font(.secondaryText).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(shown.prefix(3), id: \.flag.ids) { item in row(item.day, item.flag) }
                }
                .padding(Space.l)
                .modifier(CardSurface())
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Color.clear.frame(height: 0)        // an empty Group never runs .task
            }
        }
        .task(id: "\(day ?? "all")|\(dataVersion)") { load() }
    }

    private func load() {
        if let day { flags = ctx.largeFlags(on: day).map { (day, $0) }; return }
        flags = ctx.unconfirmedLargeDays.sorted().flatMap { d in ctx.largeFlags(on: d).map { (d, $0) } }
    }

    private func row(_ d: String, _ f: LargeEntryRule.Flag) -> some View {
        let es = ctx.entries(on: d).filter { f.ids.contains($0.syncID) }.sorted { $0.nutrients.kcal > $1.nutrients.kcal }
        let when = String(format: "%02d:%02d", f.minute / 60, f.minute % 60)
        return VStack(alignment: .leading, spacing: Space.s) {
            Text("\(day == nil ? date(fromKey: d).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(appLocale)) + ", " : "")\(f.single ? "an entry" : "a meal") at \(when): \(number(energy.fromKcal(f.kcal))) \(energy.rawValue)")
                .font(.secondaryText.weight(.semibold)).monospacedDigit()
            ForEach(es.prefix(4), id: \.syncID) { e in
                HStack {
                    Text(e.name).lineLimit(1)
                    Spacer()
                    Text("\(e.amountText) · \(number(energy.fromKcal(e.nutrients.kcal)))").foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.fine)
            }
            if es.count > 4 { Text("and \(es.count - 4) more").font(.fine).foregroundStyle(.secondary) }
            HStack {
                Button("Yes, that's right") {
                    ctx.confirmLarge(f.ids, on: d); Haptics.success()
                    animate(Motion.smooth) { flags.removeAll { $0.flag == f } }
                }
                .buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent)
                Button("I'll fix it") { Haptics.tick(); animate(Motion.smooth) { _ = later.insert(f.ids.joined()) } }
                    .buttonStyle(.bordered)
            }
            .font(.secondaryText.weight(.semibold)).controlSize(.small)
            Text("To fix it, tap the entry in the food log and change the amount.").font(.fine).foregroundStyle(.secondary)
        }
    }
}

/// Cold start: pick 15–25 foods you eat regularly, with your usual portion and meal. The planner uses
/// these until your log has about two weeks of food-by-food history.
struct StaplesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: [SortDescriptor(\Food.useCount, order: .reverse), SortDescriptor(\Food.name)]) private var foods: [Food]
    @State private var staples: [Staple] = []
    @State private var loaded = false
    @State private var search = ""
    @State private var suggestions: [StapleSuggestions.Suggestion] = []
    @State private var minDays = 6
    @State private var window = 28

    var body: some View {
        List {
            Section {
                Text("Pick 15–25 foods you eat most weeks. Set how much you usually have and at which meal. The planner builds your meals from these until your log has about two weeks of history; then it learns from what you actually eat.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("\(staples.count) picked").font(.secondaryText.weight(.semibold)).monospacedDigit()
                    Spacer()
                    Text(staples.count < 15 ? "aim for at least 15" : staples.count > 25 ? "25 is plenty" : "good")
                        .font(.caption).foregroundStyle(staples.count < 15 || staples.count > 25 ? palette.warn : palette.good)
                }
            }
            Section {
                if suggestions.isEmpty {
                    Text("Nothing logged on \(minDays) or more of the last \(window) days yet. Foods you log often will show up here.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(suggestions, id: \.key) { s in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.name).lineLimit(1)
                            Text("\(s.days) of the last \(window) days · usually \(Int(s.grams)) g at \(s.band.label.lowercased())").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { confirm(s) } label: { Image(systemName: "checkmark.circle.fill") }.buttonStyle(.borderless).foregroundStyle(palette.good)
                            .accessibilityLabel("Add \(s.name) as a staple")
                        Button { dismissSuggestion(s) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).foregroundStyle(.secondary)
                            .accessibilityLabel("Not a staple")
                    }
                }
                Stepper("Suggest after \(minDays) days", value: $minDays, in: 2...20).onChange(of: minDays) { _, _ in saveThresholds() }
                Stepper("Look back \(window / 7) weeks", value: $window, in: 14...84, step: 7).onChange(of: window) { _, _ in saveThresholds() }
            } header: { Text("Suggested from your log") } footer: { Text("Your own picks always win over suggestions.") }
            if !staples.isEmpty {
                Section("Your staples") {
                    ForEach($staples) { $st in
                        if let f = foods.first(where: { $0.key == st.key }) { stapleRow(f, $st) }
                    }
                    .onDelete { staples.remove(atOffsets: $0) }
                }
            }
            Section {
                ForEach(foods.filter { f in !staples.contains { $0.key == f.key } && (search.isEmpty || f.name.localizedCaseInsensitiveContains(search)) }.prefix(80)) { f in
                    Button { add(f) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.name).lineLimit(1)
                                Text("\(Int(f.per100.kcal)) kcal · \(Int(f.per100.protein)) g protein per 100 g").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle").foregroundStyle(palette.accent)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: { Text("Your foods") } footer: { Text("Missing something? Log it once (search or scan) and it appears here.") }
        }
        .searchable(text: $search, prompt: "Find a food")
        .themedList()
        .navigationTitle("Staples")
        .onAppear {
            if !loaded, let p = ctx.profile { staples = p.planner.staples; minDays = p.planner.stapleMinDays; window = p.planner.stapleWindowDays; loaded = true }
            suggestions = ctx.stapleSuggestions()
        }
        .onDisappear(perform: save)
    }

    private func stapleRow(_ f: Food, _ st: Binding<Staple>) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(f.name).lineLimit(1).font(.secondaryText.weight(.semibold))
            HStack {
                Picker("Meal", selection: st.band) { ForEach(MealBand.allCases, id: \.self) { Text($0.label).tag($0) } }
                    .pickerStyle(.menu).labelsHidden().fixedSize()
                Spacer()
                Stepper("\(Int(st.wrappedValue.grams)) g", value: st.grams, in: 5...1000, step: f.per100.kcal > 500 ? 5 : 10)
                    .monospacedDigit().fixedSize()
            }
            .font(.secondaryText)
        }
    }

    private func add(_ f: Food) {
        let g = f.lastAmount.map { f.grams($0, unit: f.lastUnit ?? f.baseUnit) } ?? f.servings.first?.grams ?? 100
        var band = MealBand.guess(name: f.name).sorted().first ?? .lunch
        if let d = f.lastUsed {
            band = MealBand.of(minute: Calendar.current.component(.hour, from: d) * 60 + Calendar.current.component(.minute, from: d))
        }
        Haptics.tick()
        animate(Motion.snappy) { staples.append(Staple(key: f.key, grams: max(5, g.rounded()), band: band)) }
    }

    private func confirm(_ s: StapleSuggestions.Suggestion) {
        Haptics.tap()
        animate(Motion.snappy) {
            staples.append(Staple(key: s.key, grams: s.grams, band: s.band, suggested: true))
            suggestions.removeAll { $0.key == s.key }
        }
        save()
    }

    private func dismissSuggestion(_ s: StapleSuggestions.Suggestion) {
        guard let p = ctx.profile else { return }
        var st = p.planner
        st.dismissedStaples.append(s.key); p.planner = st; ctx.commit(); Haptics.tick()
        animate(Motion.snappy) { suggestions.removeAll { $0.key == s.key } }
    }

    private func saveThresholds() {
        guard let p = ctx.profile else { return }
        var st = p.planner
        st.stapleMinDays = minDays; st.stapleWindowDays = window; p.planner = st; ctx.commit()
        suggestions = ctx.stapleSuggestions()
    }

    private func save() {
        guard let p = ctx.profile else { return }
        var s = p.planner
        guard s.staples != staples else { return }
        s.staples = staples; p.planner = s; ctx.commit()
    }
}

