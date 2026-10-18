import SwiftData
import SwiftUI

/// "Is this right?" for an entry or meal big enough to be a typo (1 500 kcal, or 60% of the day's
/// target). Until you confirm it, its day is left out of expenditure and the plan doesn't count it.
/// One line ("2 entries to check") that opens the list; `day` nil: every such day in the last 4 weeks.
struct LargeEntriesCard: View {
    @Environment(\.modelContext) private var ctx
    var day: String? = nil
    var energy: EnergyUnit = .kcal
    @State private var count = 0
    @State private var open = false

    var body: some View {
        Group {
            if count > 0 {
                Button { open = true } label: {
                    HStack(spacing: Space.m) {
                        Image(systemName: "exclamationmark.magnifyingglass").font(.cardTitle).foregroundStyle(palette.warn)
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(count == 1 ? "1 entry to check" : "\(count) entries to check").font(.cardTitle)
                            Text("Big enough to be a typo; left out of your expenditure until you answer").font(.note).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.label).foregroundStyle(.tertiary)
                    }
                    .padding(Space.l).frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(CardSurface())
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens the list to confirm or fix each one")
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Color.clear.frame(height: 0)        // an empty Group never runs .task
            }
        }
        .task(id: "\(day ?? "all")|\(dataVersion)") { count = ctx.largeEntryFlags(day: day).count }
        .sheet(isPresented: $open, onDismiss: { count = ctx.largeEntryFlags(day: day).count }) {
            NavigationStack { LargeEntriesList(day: day, energy: energy) }.appStyle()
        }
    }
}

extension ModelContext {
    /// The large entries still to answer: on one day, or every day of the last 4 weeks.
    func largeEntryFlags(day: String?) -> [(day: String, flag: LargeEntryRule.Flag)] {
        if let day { return largeFlags(on: day).map { (day, $0) } }
        return unconfirmedLargeDays.sorted().flatMap { d in largeFlags(on: d).map { (d, $0) } }
    }
}

/// The list behind "N entries to check": each entry or meal with Confirm (it's right, count it) or
/// Fix (open the entry and change the amount).
struct LargeEntriesList: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let day: String?
    let energy: EnergyUnit
    @State private var flags: [(day: String, flag: LargeEntryRule.Flag)] = []
    @State private var editing: FoodEntry?

    var body: some View {
        List {
            ForEach(flags, id: \.flag.ids) { item in section(item.day, item.flag) }
            if flags.isEmpty { Text("All checked.").foregroundStyle(.secondary) }
        }
        .themedForm()
        .navigationTitle("Entries to check")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task(id: dataVersion) { load() }
        .sheet(item: $editing, onDismiss: load) { EntryEditor(entry: $0).appStyle() }
    }

    private func load() { flags = ctx.largeEntryFlags(day: day) }

    private func section(_ d: String, _ f: LargeEntryRule.Flag) -> some View {
        let es = ctx.entries(on: d).filter { f.ids.contains($0.syncID) }.sorted { $0.nutrients.kcal > $1.nutrients.kcal }
        let when = String(format: "%02d:%02d", f.minute / 60, f.minute % 60)
        let dayText = date(fromKey: d).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(appLocale))
        return Section {
            ForEach(es, id: \.syncID) { e in
                Button { editing = e } label: {
                    HStack {
                        Text(e.name).lineLimit(2)
                        Spacer()
                        Text("\(e.amountText) · \(number(energy.fromKcal(e.nutrients.kcal)))").foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.secondaryText).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the entry to change the amount")
            }
            HStack(spacing: Space.m) {
                Button("Confirm") {
                    ctx.confirmLarge(f.ids, on: d); Haptics.success()
                    animate(Motion.smooth) { flags.removeAll { $0.flag == f } }
                }
                .buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent)
                .accessibilityHint("It's right: count this day in your expenditure")
                Button("Fix") { editing = es.first }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Opens the biggest entry to change the amount")
            }
            .font(.secondaryEmphasis)
        } header: {
            Text("\(dayText), \(f.single ? "an entry" : "a meal") at \(when): \(number(energy.fromKcal(f.kcal))) \(energy.rawValue)").monospacedDigit()
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
                    .font(.note).foregroundStyle(.secondary)
                HStack {
                    Text("\(staples.count) picked").font(.secondaryEmphasis).monospacedDigit()
                    Spacer()
                    Text(staples.count < 15 ? "aim for at least 15" : staples.count > 25 ? "25 is plenty" : "good")
                        .font(.note).foregroundStyle(staples.count < 15 || staples.count > 25 ? palette.warn : palette.good)
                }
            }
            Section {
                if suggestions.isEmpty {
                    Text("Nothing logged on \(minDays) or more of the last \(window) days yet. Foods you log often will show up here.").font(.note).foregroundStyle(.secondary)
                }
                ForEach(suggestions, id: \.key) { s in
                    HStack {
                        VStack(alignment: .leading, spacing: Space.hairline) {
                            Text(s.name).lineLimit(1)
                            Text("\(s.days) of the last \(window) days · usually \(Int(s.grams)) g at \(s.band.label.lowercased())").font(.note).foregroundStyle(.secondary)
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
                            VStack(alignment: .leading, spacing: Space.hairline) {
                                Text(f.name).lineLimit(1)
                                Text("\(Int(f.per100.kcal)) kcal · \(Int(f.per100.protein)) g protein per 100 g").font(.note).foregroundStyle(.secondary)
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
            Text(f.name).lineLimit(1).font(.secondaryEmphasis)
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

