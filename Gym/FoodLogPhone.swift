import SwiftData
import SwiftUI

#if os(iOS)

// The phone's food log, after MacroFactor's: a pinned header (the day, a week of day pills with a
// calorie ring each, the four macro bars) over a timeline of hours with food cards. Ours keeps the
// macro colours, an emoji per food, glow (Maximal) and glass.

struct PhoneFoodLog: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @State private var day = dayKey()
    @AppStorage("phoneLogStyle") private var style: FoodLogView.LogStyle = .timeline
    @AppStorage("showEmptyHours") private var showEmptyHours = true
    @State private var sheet: FoodLogView.LogSheet?
    @State private var details = false
    @State private var picking = false
    @ObservedObject private var selection = FoodSelection.shared

    var body: some View {
        let energy = profiles.first?.energy ?? .kcal
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    DayEntries(day: day, energy: energy, style: style, showEmptyHours: showEmptyHours, selected: $selection.ids) { sheet = $0 }
                        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 24)
                } header: {
                    header(energy)
                }
            }
        }
        .debugScrollAnchor()
        .pageBackground()
        .overlay(alignment: .top) {
            // Under the status bar: cover what scrolls past the pinned header.
            Color.clear.frame(height: 0)
                .background { if palette.glass { Rectangle().fill(.ultraThinMaterial).ignoresSafeArea(edges: .top) }
                              else { Color.pageBackground.ignoresSafeArea(edges: .top) } }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: day) { _, d in selection.ids = []; selection.day = d; Haptics.tick() }
        .onAppear {
            selection.day = day
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "selectFirst"), let e = ctx.entries(on: day).first { selection.ids = [e.syncID] }   // testing only
            #endif
        }
        .onDisappear { selection.ids = [] }
        .onReceive(selection.$editing) { e in if let e { sheet = .edit(e); selection.editing = nil } }
        .sheet(item: $sheet) { s in
            switch s {
            case .add(let t): FoodLogger(day: day, time: t)
            case .quickAdd(let t): FoodLogger(day: day, time: t, start: .quickAdd)
            case .copy: CopyDayView(target: day)
            case .edit(let e):
                if e.isQuickAdd { QuickAddView(day: day, entry: e) } else { EntryEditor(entry: e) }
            }
        }
        .sheet(isPresented: $details) { DayDetailsSheet(day: day, style: $style, showEmptyHours: $showEmptyHours) }
        .sheet(isPresented: $picking) { DayPickerSheet(day: $day) }
    }

    // MARK: Pinned header

    private func header(_ energy: EnergyUnit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(title).font(.pageTitle(title.count > 9 ? 24 : 30)).lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(GlowStyle.on || palette.glass
                                     ? AnyShapeStyle(LinearGradient(colors: [.primary, palette.accent], startPoint: .leading, endPoint: .trailing))
                                     : AnyShapeStyle(.primary))
                    .onTapGesture(count: 2) { animate(Motion.snappy) { day = dayKey() } }
                Spacer(minLength: 4)
                round("calendar") { picking = true }
                round("slider.horizontal.3") { details = true }
                Menu {
                    Button("Add food", systemImage: "plus") { sheet = .add(nil) }
                    Button("Quick add", systemImage: "bolt") { sheet = .quickAdd(nil) }
                    Divider()
                    Button("Copy yesterday", systemImage: "doc.on.doc") { _ = ctx.copyEntries(from: addDays(day, -1), to: day) }
                    Button("Copy from a day…", systemImage: "calendar.badge.plus") { sheet = .copy }
                    Divider()
                    Picker("View", selection: $style) {
                        Label("Timeline", systemImage: "clock").tag(FoodLogView.LogStyle.timeline)
                        Label("Meals", systemImage: "fork.knife").tag(FoodLogView.LogStyle.meals)
                    }
                    if style == .timeline { Toggle("Show empty hours", isOn: $showEmptyHours) }
                    if day != dayKey() { Divider(); Button("Go to today", systemImage: "arrow.uturn.backward") { day = dayKey() } }
                } label: { roundLabel("ellipsis") }
                .menuStyle(.button).buttonStyle(.plain)
            }
            DayPills(day: $day)
            MacroBarsRow(day: day, energy: energy)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
        .background {
            if palette.glass { Rectangle().fill(.ultraThinMaterial).ignoresSafeArea(edges: .top) }
            else { Color.pageBackground.ignoresSafeArea(edges: .top) }
        }
    }

    private var title: String {
        let d = date(fromKey: day)
        if Calendar.current.isDateInToday(d) { return "TODAY" }
        if Calendar.current.isDateInYesterday(d) { return "YESTERDAY" }
        if Calendar.current.isDateInTomorrow(d) { return "TOMORROW" }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(appLocale)).uppercased()
    }

    private func round(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { roundLabel(icon) }.buttonStyle(.plain)
    }

    private func roundLabel(_ icon: String) -> some View {
        Image(systemName: icon).font(.headline).frame(width: 44, height: 44).modifier(GlassCapsule())
    }
}

/// Monday to Sunday as tall pills: the date, the weekday, a calorie ring around it, a dot for today.
/// Swipe sideways for the week before or after.
struct DayPills: View {
    @Binding var day: String
    @Query private var entries: [FoodEntry]
    @Environment(\.modelContext) private var ctx
    let monday: String

    init(day: Binding<String>) {
        _day = day
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        let m = dayKey(cal.dateInterval(of: .weekOfYear, for: date(fromKey: day.wrappedValue))?.start ?? Date())
        let sunday = addDays(m, 6)
        monday = m
        _entries = Query(filter: #Predicate<FoodEntry> { $0.day >= m && $0.day <= sunday })
    }

    var body: some View {
        let kcal = Dictionary(grouping: entries, by: \.day).mapValues { $0.reduce(0) { $0 + $1.nutrients.kcal } }
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let d = addDays(monday, i)
                let t = ctx.dayTargets(on: d)?.kcal ?? 0
                let p = t > 0 ? (kcal[d] ?? 0) / t : 0
                Button { animate(Motion.snappy) { day = d } } label: { pill(d, p) }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 30).onEnded { g in
            guard abs(g.translation.width) > abs(g.translation.height) else { return }
            animate(Motion.snappy) { day = addDays(day, g.translation.width < 0 ? 7 : -7) }
        })
        .capType()
    }

    private func pill(_ d: String, _ p: Double) -> some View {
        let selected = d == day
        let shape = Capsule()
        return VStack(spacing: 1) {
            Text(date(fromKey: d).formatted(.dateTime.day().locale(appLocale))).font(.number(18, weight: .medium)).monospacedDigit()
            Text(date(fromKey: d).formatted(.dateTime.weekday(.abbreviated).locale(appLocale)).prefix(2))
                .font(.caption).foregroundStyle(.secondary)
            Circle().fill(d == dayKey() ? Color.primary : .clear).frame(width: 4, height: 4).padding(.top, 2)
        }
        .frame(width: 44, height: 66)
        .background(selected ? Color.primary.opacity(0.16) : .clear, in: shape)
        .overlay(shape.stroke(Color.primary.opacity(0.14), lineWidth: 3))
        .overlay(shape.trim(from: 0, to: min(p, 1)).stroke(p > 1.05 ? palette.warn : palette.calories,
                                                           style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .shadow(color: GlowStyle.on ? palette.calories.opacity(0.7) : .clear, radius: 4))
        .opacity(d > dayKey() ? 0.55 : 1)
    }
}

/// 🔥 1811 / 2319 · P 145 / 176 · F 32 / 61 · C 236 / 266, with thin bars; swipe for what's left.
struct MacroBarsRow: View {
    let day: String
    let energy: EnergyUnit
    @Query private var entries: [FoodEntry]
    @Environment(\.modelContext) private var ctx
    @State private var page = 0

    init(day: String, energy: EnergyUnit) {
        self.day = day; self.energy = energy
        _entries = Query(filter: #Predicate<FoodEntry> { $0.day == day })
    }

    var body: some View {
        let eaten = entries.reduce(Nutrients.zero) { $0 + $1.nutrients }.targets
        let t = ctx.dayTargets(on: day)
        VStack(spacing: 6) {
            TabView(selection: $page) {
                row(eaten, t, remaining: false).tag(0)
                row(eaten, t, remaining: true).tag(1)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .frame(height: 30)
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { i in Circle().fill(Color.primary.opacity(i == page ? 0.8 : 0.25)).frame(width: 6, height: 6) }
            }
        }
        .capType()
    }

    private func row(_ eaten: Targets, _ t: Targets?, remaining: Bool) -> some View {
        HStack(spacing: 12) {
            ForEach(Macro.allCases, id: \.self) { m in
                let v = m.value(eaten), goal = t.map { m.value($0) } ?? 0
                let conv: (Double) -> Double = { m == .calories ? energy.fromKcal($0) : $0 }
                let frac = goal > 0 ? v / goal : 0
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 3) {
                        if m == .calories { Image(systemName: "flame.fill").foregroundStyle(m.color) }
                        else { Text(m.short).fontWeight(.heavy).foregroundStyle(m.color) }
                        Text(remaining ? (goal - v >= 0 ? "\(number(conv(goal - v))) left" : "\(number(conv(v - goal))) over")
                                       : "\(number(conv(v))) / \(number(conv(goal)))")
                            .liveNumber(v).foregroundStyle(remaining && v > goal ? palette.warn : .primary)
                    }
                    .font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.12))
                            Capsule().fill(frac > 1.05 ? palette.warn : m.color).frame(width: g.size.width * min(frac, 1))
                                .shadow(color: GlowStyle.on ? m.color.opacity(0.8) : .clear, radius: 4)
                                .animation(Motion.pick(Motion.smooth), value: frac)
                        }
                    }
                    .frame(height: 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The day's food: a timeline of hours, or by meal.
struct DayEntries: View {
    @Environment(\.modelContext) private var ctx
    @Query private var entries: [FoodEntry]
    let day: String
    let energy: EnergyUnit
    let style: FoodLogView.LogStyle
    let showEmptyHours: Bool
    @Binding var selected: Set<String>
    let open: (FoodLogView.LogSheet) -> Void
    @State private var targetHour: Int?

    init(day: String, energy: EnergyUnit, style: FoodLogView.LogStyle, showEmptyHours: Bool, selected: Binding<Set<String>>,
         open: @escaping (FoodLogView.LogSheet) -> Void) {
        _entries = Query(filter: #Predicate<FoodEntry> { $0.day == day }, sort: \FoodEntry.time)
        self.day = day; self.energy = energy; self.style = style; self.showEmptyHours = showEmptyHours; _selected = selected; self.open = open
    }

    private func toggle(_ e: FoodEntry) {
        animate(Motion.snappy) { if selected.contains(e.syncID) { selected.remove(e.syncID) } else { selected.insert(e.syncID) } }
        #if os(iOS)
        Haptics.tick()
        #endif
    }

    /// The food card, tappable to select (the pencil still edits straight away).
    @ViewBuilder private func card(_ e: FoodEntry) -> some View {
        HStack(spacing: 10) {
            if !selected.isEmpty {
                Image(systemName: selected.contains(e.syncID) ? "checkmark.circle.fill" : "circle").font(.title2)
                    .foregroundStyle(selected.contains(e.syncID) ? palette.accent : Color.secondary)
                    .transition(.scale.combined(with: .opacity))
            }
            EntryCard(entry: e, energy: energy, tap: { toggle(e) }) { open(.edit(e)) }
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected.contains(e.syncID) ? palette.accent : .clear, lineWidth: 2))
        }
    }

    var body: some View {
        Group {
            if style == .timeline { timeline } else { meals }
        }
        .sensoryFeedback(.success, trigger: entries.count) { old, new in new > old }
    }

    // MARK: Timeline

    private var timeline: some View {
        let cal = Calendar.current
        let byHour = Dictionary(grouping: entries) { cal.component(.hour, from: $0.time) }
        let now = day == dayKey() ? cal.component(.hour, from: Date()) : 0
        let lo = min(7, byHour.keys.min() ?? 7), hi = max(22, byHour.keys.max() ?? 22, now)
        let hours = showEmptyHours ? Array(lo...hi) : byHour.keys.sorted()
        return VStack(alignment: .leading, spacing: 14) {
            if entries.isEmpty && !showEmptyHours {
                emptyState
            }
            ForEach(hours, id: \.self) { h in hourBlock(h, (byHour[h] ?? []).sorted { $0.time < $1.time }) }
        }
        .background(alignment: .leading) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 2).padding(.leading, 30).padding(.vertical, 14)
        }
    }

    private func hourBlock(_ h: Int, _ items: [FoodEntry]) -> some View {
        let n = items.reduce(Nutrients.zero) { $0 + $1.nutrients }
        let cal = Calendar.current
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                let nowHour = day == dayKey() && cal.component(.hour, from: Date()) == h
                HStack(spacing: 4) {
                    Text(String(format: "%02d:00", h)).font(.subheadline.weight(.medium)).monospacedDigit()
                    if nowHour { Circle().fill(palette.accent).frame(width: 6, height: 6) }
                }
                    .padding(.horizontal, 12).frame(minWidth: 62).frame(height: 34)
                    .background(Color.raisedBackground, in: Capsule())
                    .overlay(Capsule().stroke(targetHour == h ? palette.accent : .clear, lineWidth: 2))
                Button { open(.add(cal.date(bySettingHour: h, minute: 0, second: 0, of: date(fromKey: day)))) } label: {
                    Image(systemName: "plus").font(.subheadline.weight(.bold)).frame(width: 34, height: 34)
                        .background(Color.raisedBackground, in: Circle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 4)
                if !items.isEmpty { HourTotals(n: n, energy: energy) }
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { i, e in
                let showTime = i == 0 || cal.component(.minute, from: e.time) != cal.component(.minute, from: items[i - 1].time)
                HStack(alignment: .center, spacing: 8) {
                    Text(showTime ? e.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(appLocale)) : "")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        .lineLimit(1).fixedSize()
                        .frame(width: 62)
                        .background { if showTime { Color.pageBackground.padding(.vertical, -2) } }
                    card(e)
                        .contextMenu { menu(e) }
                        .draggable(e.syncID) {
                            Text(e.name).font(.callout.weight(.semibold)).padding(8)
                                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                        }
                }
            }
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { ids, _ in move(ids, to: h) } isTargeted: { targetHour = $0 ? h : (targetHour == h ? nil : targetHour) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Nothing logged").font(.headline)
            Text("Tap + by an hour, or search for a food below.").font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    // MARK: Meals

    private var meals: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Meal.allCases) { m in
                let items = entries.filter { Meal(time: $0.time) == m }
                let n = items.reduce(Nutrients.zero) { $0 + $1.nutrients }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: m.icon).foregroundStyle(m.color).frame(width: 34, height: 34).background(m.color.opacity(0.16), in: Circle())
                        Text(m.label).font(.title3.weight(.bold))
                        Button { open(.add(m.time(on: day))) } label: {
                            Image(systemName: "plus").font(.subheadline.weight(.bold)).frame(width: 30, height: 30).background(Color.raisedBackground, in: Circle())
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 4)
                        if !items.isEmpty { HourTotals(n: n, energy: energy) }
                    }
                    ForEach(items) { e in
                        card(e).contextMenu { menu(e) }
                    }
                }
            }
        }
    }

    // MARK: Actions

    @ViewBuilder private func menu(_ e: FoodEntry) -> some View {
        Button("Edit…", systemImage: "pencil") { open(.edit(e)) }
        Button("Duplicate", systemImage: "plus.square.on.square") {
            ctx.insert(FoodEntry(day: e.day, time: e.time, name: e.name, brand: e.brand, foodKey: e.foodKey,
                                 amount: e.amount, unit: e.unit, grams: e.grams, nutrients: e.nutrients))
            ctx.commit()
        }
        Menu("Move to") {
            ForEach(Meal.allCases) { m in
                Button(m.label) {
                    let u = m.usual
                    e.time = Calendar.current.date(bySettingHour: u.0, minute: u.1, second: 0, of: date(fromKey: e.day)) ?? e.time
                    ctx.commit()
                }
            }
        }
        if e.day != dayKey() {
            Button("Copy to today", systemImage: "doc.on.doc") {
                let cal = Calendar.current, hm = cal.dateComponents([.hour, .minute], from: e.time)
                let t = cal.date(bySettingHour: hm.hour ?? 12, minute: hm.minute ?? 0, second: 0, of: Date()) ?? Date()
                ctx.insert(FoodEntry(day: dayKey(), time: t, name: e.name, brand: e.brand, foodKey: e.foodKey,
                                     amount: e.amount, unit: e.unit, grams: e.grams, nutrients: e.nutrients))
                ctx.commit()
            }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { ctx.deleteWithUndo([e], "\(e.name) removed") }
    }

    private func move(_ ids: [String], to hour: Int) -> Bool {
        let cal = Calendar.current
        let moving = entries.filter { ids.contains($0.syncID) }
        guard !moving.isEmpty else { return false }
        for e in moving {
            let m = cal.component(.minute, from: e.time)
            e.time = cal.date(bySettingHour: hour, minute: m, second: 0, of: date(fromKey: e.day)) ?? e.time
        }
        animate(Motion.snappy) { ctx.commit() }
        return true
    }
}

/// 1811 🔥  145 P  32 F  236 C — an hour's (or meal's) totals as small chips.
struct HourTotals: View {
    let n: Nutrients
    let energy: EnergyUnit

    var body: some View {
        HStack(spacing: 10) {
            chip(number(energy.fromKcal(n.kcal)), icon: "flame.fill", color: palette.calories)
            chip(number(n.protein), letter: "P", color: palette.protein)
            chip(number(n.fat), letter: "F", color: palette.fat)
            chip(number(n.carbs), letter: "C", color: palette.carbs)
        }
        .font(.subheadline.weight(.medium)).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.7)
    }

    private func chip(_ v: String, icon: String? = nil, letter: String? = nil, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(v)
            Group {
                if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
                else { Text(letter ?? "").font(.system(size: 11, weight: .heavy)) }
            }
            .foregroundStyle(color)
            .frame(width: 20, height: 20)
            .background(color.opacity(0.18), in: Circle())
        }
    }
}

/// A logged food: emoji, name, kcal and macros (coloured letters), amount, and an edit button.
struct EntryCard: View {
    let entry: FoodEntry
    let energy: EnergyUnit
    var tap: (() -> Void)? = nil
    let edit: () -> Void

    var body: some View {
        let n = entry.nutrients
        Button(action: tap ?? edit) {
            HStack(spacing: 12) {
                Text(foodEmoji(entry))
                    .font(.system(size: 26))
                    .frame(width: 46, height: 46)
                    .background(dominant(n).opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name).font(.body.weight(.medium)).lineLimit(2).multilineTextAlignment(.leading)
                    (Text("\(number(energy.fromKcal(n.kcal)))").foregroundStyle(.primary)
                     + Text(Image(systemName: "flame.fill")).font(.caption2).foregroundStyle(palette.calories)
                     + Text("  \(number(n.protein))").foregroundStyle(.primary) + Text("P").foregroundStyle(palette.protein).fontWeight(.bold)
                     + Text("  \(number(n.fat))").foregroundStyle(.primary) + Text("F").foregroundStyle(palette.fat).fontWeight(.bold)
                     + Text("  \(number(n.carbs))").foregroundStyle(.primary) + Text("C").foregroundStyle(palette.carbs).fontWeight(.bold)
                     + Text(entry.isQuickAdd ? "" : "  •  \(entry.amountText)").foregroundStyle(.secondary))
                        .font(.subheadline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                }
                Spacer(minLength: 4)
                if tap == nil {
                    Image(systemName: "pencil").font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 36).background(Color.raisedBackground, in: Circle())
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .modifier(CardSurface(cornerRadius: 18))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dominant(_ n: Nutrients) -> Color {
        let p = n.protein * 4, f = n.fat * 9, c = n.carbs * 4
        return p >= f && p >= c ? palette.protein : f >= c ? palette.fat : palette.carbs
    }
}

/// The sliders button: nutrients for the day, the note, and how the log looks.
struct DayDetailsSheet: View {
    let day: String
    @Binding var style: FoodLogView.LogStyle
    @Binding var showEmptyHours: Bool
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [FoodEntry]

    init(day: String, style: Binding<FoodLogView.LogStyle>, showEmptyHours: Binding<Bool>) {
        self.day = day; _style = style; _showEmptyHours = showEmptyHours
        _entries = Query(filter: #Predicate<FoodEntry> { $0.day == day })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Card(title: "View", systemImage: "eye") {
                        Picker("", selection: $style) {
                            Text("Timeline").tag(FoodLogView.LogStyle.timeline)
                            Text("Meals").tag(FoodLogView.LogStyle.meals)
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        if style == .timeline { Toggle("Show empty hours", isOn: $showEmptyHours) }
                    }
                    DayNoteCard(day: day)
                    ProteinMealsCard(days: [day])
                    NutrientPanel(total: entries.reduce(Nutrients.zero) { $0 + $1.nutrients }, entries: entries)
                }
                .padding(16)
            }
            .pageBackground()
            .navigationTitle(date(fromKey: day).formatted(.dateTime.weekday(.wide).day().month(.wide).locale(appLocale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .appStyle()
        .presentationDetents([.large])
    }
}

/// Jump to any day.
struct DayPickerSheet: View {
    @Binding var day: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker("Day", selection: Binding(get: { date(fromKey: day) }, set: { day = dayKey($0); dismiss() }),
                       in: ...Date().addingTimeInterval(86400 * 30), displayedComponents: .date)
                .datePickerStyle(.graphical).padding()
                .pageBackground()
                .navigationTitle("Go to a day").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Today") { day = dayKey(); dismiss() } }
                }
        }
        .appStyle()
        .presentationDetents([.medium, .large])
    }
}

/// Which logged foods are selected (shared so the bar can sit where the search bar is).
@MainActor final class FoodSelection: ObservableObject {
    static let shared = FoodSelection()
    @Published var ids: Set<String> = []
    @Published var editing: FoodEntry?
    var day = dayKey()
}

/// MacroFactor's bar for selected foods: Edit, Copy, Move, Move to day, Remove, More.
struct SelectionBar: View {
    @Environment(\.modelContext) private var ctx
    @ObservedObject private var sel = FoodSelection.shared
    @State private var moving = false
    @State private var copying = false
    @State private var pickingDay = false
    @State private var copyAfterPick = false
    @State private var target = Date()


    private var chosen: [FoodEntry] { ctx.entries(on: sel.day).filter { sel.ids.contains($0.syncID) } }

    var body: some View {
        HStack(spacing: 10) {
            Button { animate(Motion.snappy) { sel.ids = [] } } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40).background(Color.primary, in: Circle())
                    .foregroundStyle(palette.scheme == .dark ? Color.black : .white)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 0) {
                Text("Select").font(.subheadline.weight(.semibold))
                Text("\(sel.ids.count) food\(sel.ids.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            }
            Divider().frame(height: 36)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if sel.ids.count == 1, let e = chosen.first { action("Edit") { sel.ids = []; sel.editing = e } }
                    action("Copy") { copying = true }
                    action("Move") { moving = true }
                    action("Move to day") { pickingDay = true }
                    action("Remove", destructive: true) { remove() }
                    Menu {
                        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate() }
                        Button("Save as meal", systemImage: "square.and.arrow.down") {
                            ctx.saveMeal(chosen.first?.name ?? "Meal", from: chosen); sel.ids = []
                        }
                        Button("Select all", systemImage: "checkmark.circle") { sel.ids = Set(ctx.entries(on: sel.day).map(\.syncID)) }
                    } label: { pill("More") }
                    .menuStyle(.button).buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.bar)
        .confirmationDialog("Move \(sel.ids.count) food\(sel.ids.count == 1 ? "" : "s") to", isPresented: $moving, titleVisibility: .visible) {
            ForEach(Meal.allCases) { m in Button(m.label) { move(to: m) } }
            Button("Now (\(Date().formatted(.dateTime.hour().minute().locale(appLocale))))") { moveToNow() }
        }
        .confirmationDialog("Copy \(sel.ids.count) food\(sel.ids.count == 1 ? "" : "s") to", isPresented: $copying, titleVisibility: .visible) {
            if sel.day != dayKey() { Button("Today") { copy(to: dayKey()) } }
            Button("The next day") { copy(to: addDays(sel.day, 1)) }
            Button("Tomorrow") { copy(to: addDays(dayKey(), 1)) }
            Button("Another day…") { copyAfterPick = true; pickingDay = true }
        }
        .sheet(isPresented: $pickingDay) {
            NavigationStack {
                DatePicker("Day", selection: $target, displayedComponents: .date).datePickerStyle(.graphical).padding()
                    .navigationTitle(copyAfterPick ? "Copy to" : "Move to").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pickingDay = false; copyAfterPick = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(copyAfterPick ? "Copy" : "Move") {
                                if copyAfterPick { copy(to: dayKey(target)) } else { moveDay(to: dayKey(target)) }
                                pickingDay = false; copyAfterPick = false
                            }
                        }
                    }
            }
            .appStyle().presentationDetents([.medium, .large])
        }
    }

    private func moveDay(to target: String) {
        let cal = Calendar.current
        for e in chosen {
            let hm = cal.dateComponents([.hour, .minute], from: e.time)
            e.day = target
            e.time = cal.date(bySettingHour: hm.hour ?? 12, minute: hm.minute ?? 0, second: 0, of: date(fromKey: target)) ?? e.time
        }
        ctx.commit(); sel.ids = []
    }

    private func action(_ t: String, destructive: Bool = false, _ f: @escaping () -> Void) -> some View {
        Button(action: f) { pill(t, destructive: destructive) }.buttonStyle(.plain)
    }

    private func pill(_ t: String, destructive: Bool = false) -> some View {
        Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(destructive ? palette.warn : .primary)
            .padding(.horizontal, 18).frame(height: 40).background(Color.raisedBackground, in: Capsule())
    }

    private func remove() {
        let c = chosen
        sel.ids = []
        ctx.deleteWithUndo(c, c.count == 1 ? "\(c[0].name) removed" : "\(c.count) foods removed")
    }

    private func duplicate() {
        for e in chosen {
            ctx.insert(FoodEntry(day: e.day, time: e.time, name: e.name, brand: e.brand, foodKey: e.foodKey, amount: e.amount, unit: e.unit,
                                 grams: e.grams, nutrients: e.nutrients))
        }
        ctx.commit(); sel.ids = []
    }

    private func move(to m: Meal) {
        for e in chosen { e.time = m.time(on: e.day) }
        ctx.commit(); sel.ids = []
    }

    private func moveToNow() {
        let cal = Calendar.current, now = Date()
        for e in chosen {
            e.time = cal.date(bySettingHour: cal.component(.hour, from: now), minute: cal.component(.minute, from: now), second: 0,
                              of: date(fromKey: e.day)) ?? e.time
        }
        ctx.commit(); sel.ids = []
    }

    private func copy(to target: String) {
        let cal = Calendar.current
        for e in chosen {
            let hm = cal.dateComponents([.hour, .minute], from: e.time)
            let t = cal.date(bySettingHour: hm.hour ?? 12, minute: hm.minute ?? 0, second: 0, of: date(fromKey: target)) ?? e.time
            ctx.insert(FoodEntry(day: target, time: t, name: e.name, brand: e.brand, foodKey: e.foodKey, amount: e.amount, unit: e.unit,
                                 grams: e.grams, nutrients: e.nutrients))
        }
        ctx.commit(); sel.ids = []
    }

}
#endif
