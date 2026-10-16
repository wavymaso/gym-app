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
                    if style != .plan { LargeEntriesCard(day: day, energy: energy).padding(.horizontal, 12).padding(.top, 10) }
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
                .background { Color.pageBackground.ignoresSafeArea(edges: .top) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: day) { _, d in if selection.mode == nil { selection.ids = [] }; selection.day = d; Haptics.tick() }
        .onAppear {
            selection.day = day
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "selectFirst"), let e = ctx.entries(on: day).first { selection.sourceDay = day; selection.ids = [e.syncID]; if UserDefaults.standard.bool(forKey: "copyMode") { selection.mode = .copy } }   // testing only
            #endif
        }
        .onDisappear { selection.ids = []; selection.mode = nil }
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
                Text(title).font(.pageTitle(title.count > 9 ? 24 : 30)).foregroundStyle(palette.titleStyle).lineLimit(1).minimumScaleFactor(0.5)
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
                        Label("Plan", systemImage: "calendar.badge.clock").tag(FoodLogView.LogStyle.plan)
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
        .background { Color.pageBackground.ignoresSafeArea(edges: .top) }
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
            )
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
        // Calories gets a wider column (its number is longest), so none of the four has to shrink.
        GeometryReader { geo in
        let unit = (geo.size.width - 36) / 4
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
                                       : "\(number(conv(v)))/\(number(conv(goal)))")
                            .liveNumber(v).foregroundStyle(remaining && v > goal ? palette.warn : .primary)
                    }
                    .font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.85)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.12))
                            Capsule().fill(frac > 1.05 ? palette.warn : m.color).frame(width: g.size.width * min(frac, 1))
                                .animation(Motion.pick(Motion.smooth), value: frac)
                        }
                    }
                    .frame(height: 4)
                }
                .frame(width: unit * (m == .calories ? 1.15 : 0.95), alignment: .leading)
            }
        }
        }
        .frame(height: 30)
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
    @ObservedObject private var sel = FoodSelection.shared
    @State private var targetHour: Int?

    init(day: String, energy: EnergyUnit, style: FoodLogView.LogStyle, showEmptyHours: Bool, selected: Binding<Set<String>>,
         open: @escaping (FoodLogView.LogSheet) -> Void) {
        _entries = Query(filter: #Predicate<FoodEntry> { $0.day == day }, sort: \FoodEntry.time)
        self.day = day; self.energy = energy; self.style = style; self.showEmptyHours = showEmptyHours; _selected = selected; self.open = open
    }

    private func toggle(_ e: FoodEntry) {
        guard sel.mode == nil else { return }                       // choosing a destination: taps on foods do nothing
        if selected.isEmpty { sel.sourceDay = day }
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
                .overlay(RoundedRectangle(cornerRadius: Radius.l).stroke(selected.contains(e.syncID) ? palette.accent : .clear, lineWidth: 2))
        }
    }

    var body: some View {
        Group {
            if style == .timeline { timeline } else if style == .plan { PlanDayView(day: day, energy: energy) } else { meals }
        }
        .sensoryFeedback(.success, trigger: entries.count) { old, new in new > old }
    }

    // MARK: Timeline

    private var timeline: some View {
        let cal = Calendar.current
        let byHour = Dictionary(grouping: entries) { cal.component(.hour, from: $0.time) }
        let now = day == dayKey() ? cal.component(.hour, from: Date()) : 0
        let lo = min(6, byHour.keys.min() ?? 6), hi = 23                // the whole evening, up to midnight
        let hours = showEmptyHours || sel.mode != nil ? Array(sel.mode != nil ? min(lo, 5)...max(hi, 23) : lo...hi) : byHour.keys.sorted()
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
                if let m = sel.mode {
                    // Paste the selected foods at this hour.
                    Button {
                        let t = cal.date(bySettingHour: h, minute: 0, second: 0, of: date(fromKey: day)) ?? Date()
                        let c = ctx.entries(on: sel.sourceDay).filter { sel.ids.contains($0.syncID) }
                        if m == .copy { ctx.copyEntries(c, to: day, at: t) } else { ctx.moveEntries(c, to: day, at: t) }
                        sel.clear()
                    } label: {
                        Image(systemName: m == .copy ? "doc.on.clipboard.fill" : "arrowshape.turn.up.left.fill")
                            .font(.subheadline.weight(.bold)).frame(width: 34, height: 34)
                            .background(Color.raisedBackground, in: Circle()).foregroundStyle(.primary)
                    }
                    .pressable()
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel(m == .copy ? "Copy here" : "Move here")
                } else {
                    Button { open(.add(cal.date(bySettingHour: h, minute: 0, second: 0, of: date(fromKey: day)))) } label: {
                        Image(systemName: "plus").font(.subheadline.weight(.bold)).frame(width: 34, height: 34)
                            .background(Color.raisedBackground, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
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
                                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.s))
                        }
                }
            }
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { ids, _ in move(ids, to: h) } isTargeted: { targetHour = $0 ? h : (targetHour == h ? nil : targetHour) }
    }

    private var emptyState: some View {
        EmptyState(icon: "fork.knife", title: day == dayKey() ? "Nothing logged yet today" : "Nothing logged",
                   message: "Tap + by an hour, or search for a food below.",
                   action: ("Log a food", { open(.add(nil)) }))
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

#endif
