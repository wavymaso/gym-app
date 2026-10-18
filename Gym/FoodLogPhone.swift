import SwiftData
import SwiftUI

#if os(iOS)

// The phone's food log, after MacroFactor's: a pinned header (the day, a week of day pills with a
// calorie ring each, the four macro bars) over a timeline of hours with food cards. Ours keeps the
// macro colours and an emoji per food.

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
                    if style != .plan { LargeEntriesCard(day: day, energy: energy).padding(.horizontal, Space.m).padding(.top, Space.m) }
                    DayEntries(day: day, energy: energy, style: style, showEmptyHours: showEmptyHours, selected: $selection.ids) { sheet = $0 }
                        .padding(.horizontal, Space.m).padding(.top, Space.m).padding(.bottom, Space.xl)
                } header: {
                    header(energy)
                }
            }
        }
        .debugScrollAnchor()
        .pageBackground()
        .largeTitle("Food log")
        .toolbar { headerButtons }
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
        VStack(alignment: .leading, spacing: Space.m) {
            Text(title).font(.cardTitle).foregroundStyle(.secondary)
                .onTapGesture(count: 2) { animate(Motion.snappy) { day = dayKey() } }
            DayPills(day: $day)
            MacroBarsRow(day: day, energy: energy)
        }
        .padding(.horizontal, Space.l).padding(.top, Space.s).padding(.bottom, Space.m)
        .background { Color.pageBackground.ignoresSafeArea(edges: .top) }
    }

    private var title: String {
        let d = date(fromKey: day)
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(appLocale))
    }

    @ToolbarContentBuilder private var headerButtons: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { sheet = .add(nil) } label: { Label("Search for a food", systemImage: "magnifyingglass") }
            Button { picking = true } label: { Label("Pick a day", systemImage: "calendar") }
            Button { details = true } label: { Label("Day details", systemImage: "slider.horizontal.3") }
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
            } label: { Label("More", systemImage: "ellipsis") }
        }
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
                    .accessibilityLabel(date(fromKey: d).formatted(.dateTime.weekday(.wide).day().month(.wide).locale(appLocale)) + (d == dayKey() ? ", today" : ""))
                    .accessibilityValue(t > 0 ? "\(Int(((kcal[d] ?? 0)).rounded())) of \(Int(t)) kcal" : "nothing planned")
                    .accessibilityAddTraits(d == day ? .isSelected : [])
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 30).onEnded { g in
            guard abs(g.translation.width) > abs(g.translation.height) else { return }
            animate(Motion.snappy) { day = addDays(day, g.translation.width < 0 ? 7 : -7) }
        })
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Week")
        .accessibilityAction(named: "Next week") { day = addDays(day, 7) }
        .accessibilityAction(named: "Previous week") { day = addDays(day, -7) }
        .capType()
    }

    private func pill(_ d: String, _ p: Double) -> some View {
        let selected = d == day
        let shape = Capsule()
        return VStack(spacing: Space.hairline) {
            Text(date(fromKey: d).formatted(.dateTime.day().locale(appLocale))).font(.numberMedium).monospacedDigit()
            Text(date(fromKey: d).formatted(.dateTime.weekday(.abbreviated).locale(appLocale)).prefix(2))
                .font(.note).foregroundStyle(.secondary)
            Circle().fill(d == dayKey() ? Color.primary : .clear).frame(width: 4, height: 4).padding(.top, Space.xxs)
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
        VStack(spacing: Space.s) {
            TabView(selection: $page) {
                row(eaten, t, remaining: false).tag(0)
                row(eaten, t, remaining: true).tag(1)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .frame(height: 30)
            HStack(spacing: Space.s) {
                ForEach(0..<2, id: \.self) { i in Circle().fill(Color.primary.opacity(i == page ? 0.8 : 0.25)).frame(width: 6, height: 6) }
            }
        }
        .capType()
    }

    private func row(_ eaten: Targets, _ t: Targets?, remaining: Bool) -> some View {
        // Calories gets a wider column (its number is longest), so none of the four has to shrink.
        GeometryReader { geo in
        let unit = (geo.size.width - 36) / 4
        HStack(spacing: Space.m) {
            ForEach(Macro.allCases, id: \.self) { m in
                let v = m.value(eaten), goal = t.map { m.value($0) } ?? 0
                let conv: (Double) -> Double = { m == .calories ? energy.fromKcal($0) : $0 }
                let frac = goal > 0 ? v / goal : 0
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.xs) {
                        if m == .calories { Image(systemName: "flame.fill").foregroundStyle(m.color) }
                        else { Text(m.short).fontWeight(.heavy).foregroundStyle(m.color) }
                        Text(remaining ? (goal - v >= 0 ? "\(number(conv(goal - v))) left" : "\(number(conv(v - goal))) over")
                                       : "\(number(conv(v)))/\(number(conv(goal)))")
                            .liveNumber(v).foregroundStyle(remaining && v > goal ? palette.warn : .primary)
                    }
                    .font(.label).lineLimit(1).minimumScaleFactor(0.85)
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(m.label)
                .accessibilityValue(remaining ? (goal - v >= 0 ? "\(number(conv(goal - v))) left" : "\(number(conv(v - goal))) over")
                                    : "\(number(conv(v))) of \(number(conv(goal)))")
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
    @State private var nextPlanned: (minute: Int, name: String, kcal: Double)?
    @Environment(\.dynamicTypeSize) private var dynamicSize
    @AppStorage("phoneLogStyle") private var storedStyle: FoodLogView.LogStyle = .timeline

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
        HStack(spacing: Space.m) {
            if !selected.isEmpty {
                Image(systemName: selected.contains(e.syncID) ? "checkmark.circle.fill" : "circle").font(.sectionTitle)
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
        let lo = min(6, byHour.keys.min() ?? 6), hi = 23                // the whole evening, up to midnight
        let full = showEmptyHours || sel.mode != nil
        // The full hourly view (the default, like MacroFactor's), or compact (⋯ → Show empty hours
        // off): the hours you logged and the next planned meal, the gaps as thin "+ add" rows.
        let planHour = nextPlanned.map { $0.minute / 60 }
        let hours = full ? Array(sel.mode != nil ? min(lo, 5)...max(hi, 23) : lo...hi) : Array(Set(byHour.keys).union(planHour.map { [$0] } ?? [])).sorted()
        return VStack(alignment: .leading, spacing: Space.l) {
            if entries.isEmpty && !full && nextPlanned == nil {
                emptyState
            }
            ForEach(Array(hours.enumerated()), id: \.element) { i, h in
                if !full, i > 0, h - hours[i - 1] > 1 { gapRow(after: hours[i - 1]) }
                if !full, h == planHour, byHour[h] == nil, let p = nextPlanned { plannedRow(p) }
                else { hourBlock(h, (byHour[h] ?? []).sorted { $0.time < $1.time }) }
            }
            if !full, let last = hours.last, last < 23 { gapRow(after: last) }
        }
        .background(alignment: .leading) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 2).padding(.leading, Space.xxl).padding(.vertical, Space.l)
        }
        .task(id: "\(day)|\(dataVersion)|\(entries.count)") { nextPlanned = upcomingMeal() }
    }

    /// The next planned meal not yet eaten (today and later days only), from the plan.
    private func upcomingMeal() -> (minute: Int, name: String, kcal: Double)? {
        guard day >= dayKey(), let r = ctx.dayPlan(day) else { return nil }
        let cal = Calendar.current
        let now = day == dayKey() ? cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date()) : 0
        guard let s = r.plan.slots.first(where: { !$0.eaten && $0.minute >= now - 30 && !$0.items.isEmpty }) else { return nil }
        let kcal = s.items.reduce(0.0) { $0 + (r.foods[$1.key]?.macros($1.grams).kcal ?? 0) }
        let name: String
        switch s.kind { case .meal: name = s.band.label; case .preWorkout: name = "Before training"; case .postWorkout: name = "After training"; case .preSleep: name = "Before bed" }
        return (s.minute, name, kcal)
    }

    /// A gap between logged hours, as one thin row: tap to log at the hour after.
    private func gapRow(after h: Int) -> some View {
        let cal = Calendar.current
        return Button { open(.add(cal.date(bySettingHour: min(h + 1, 23), minute: 0, second: 0, of: date(fromKey: day)))) } label: {
            HStack(spacing: Space.s) {
                Image(systemName: "plus").font(.label)
                Text("Add").font(.label)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, Space.m).frame(minWidth: 62).frame(height: 24)
            .background(Color.raisedBackground.opacity(0.6), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a food after \(String(format: "%02d:00", h))")
    }

    /// The next planned meal, faint, on its hour: tap to see the plan.
    private func plannedRow(_ p: (minute: Int, name: String, kcal: Double)) -> some View {
        Button { animate(Motion.smooth) { storedStyle = .plan } } label: {
            HStack(spacing: Space.m) {
                Text(String(format: "%02d:%02d", p.minute / 60, p.minute % 60)).font(.secondaryEmphasis).monospacedDigit()
                    .padding(.horizontal, Space.m).frame(minWidth: 62).frame(height: 34)
                    .background(Color.raisedBackground, in: Capsule())
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Next planned: \(p.name)").font(.secondaryEmphasis)
                    Text("\(energy.format(p.kcal)) · see the plan").font(.note).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.label).foregroundStyle(.tertiary)
            }
            .padding(.trailing, Space.m).padding(.vertical, Space.xs)
            .background(RoundedRectangle(cornerRadius: Radius.l).strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next planned meal: \(p.name) at \(String(format: "%02d:%02d", p.minute / 60, p.minute % 60)), \(energy.format(p.kcal))")
        .accessibilityHint("Opens the plan")
    }

    private func hourBlock(_ h: Int, _ items: [FoodEntry]) -> some View {
        let n = items.reduce(Nutrients.zero) { $0 + $1.nutrients }
        let cal = Calendar.current
        return VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                let nowHour = day == dayKey() && cal.component(.hour, from: Date()) == h
                HStack(spacing: Space.xs) {
                    Text(String(format: "%02d:00", h)).font(.secondaryEmphasis).monospacedDigit()
                    if nowHour { Circle().fill(palette.accent).frame(width: 6, height: 6) }
                }
                    .padding(.horizontal, Space.m).frame(minWidth: 62).frame(height: 34)
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
                            .font(.secondaryEmphasis).frame(width: 34, height: 34)
                            .background(Color.raisedBackground, in: Circle()).foregroundStyle(.primary)
                    }
                    .pressable()
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel(m == .copy ? "Copy here" : "Move here")
                } else {
                    Button { open(.add(cal.date(bySettingHour: h, minute: 0, second: 0, of: date(fromKey: day)))) } label: {
                        Image(systemName: "plus").font(.secondaryEmphasis).frame(width: 34, height: 34).accessibilityLabel("Add a food at \(String(format: "%02d:00", h))")
                            .background(Color.raisedBackground, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 4)
                if !items.isEmpty && !dynamicSize.isAccessibilitySize { HourTotals(n: n, energy: energy) }
            }
            if !items.isEmpty && dynamicSize.isAccessibilitySize { HourTotals(n: n, energy: energy).padding(.leading, Space.s) }
            ForEach(Array(items.enumerated()), id: \.element.id) { i, e in
                let showTime = i == 0 || cal.component(.minute, from: e.time) != cal.component(.minute, from: items[i - 1].time)
                HStack(alignment: .center, spacing: Space.s) {
                    Text(showTime ? e.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(appLocale)) : "")
                        .font(.note).monospacedDigit().foregroundStyle(.secondary)
                        .lineLimit(1).fixedSize()
                        .frame(width: 62)
                        .background { if showTime { Color.pageBackground.padding(.vertical, -2) } }
                    card(e)
                        .contextMenu { menu(e) }
                        .draggable(e.syncID) {
                            Text(e.name).font(.secondaryEmphasis).padding(Space.s)
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
                   message: "Tap + by an hour, or search for a food from the top bar.",
                   action: ("Log a food", { open(.add(nil)) }))
    }

    // MARK: Meals

    private var meals: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            ForEach(Meal.allCases) { m in
                let items = entries.filter { Meal(time: $0.time) == m }
                let n = items.reduce(Nutrients.zero) { $0 + $1.nutrients }
                VStack(alignment: .leading, spacing: Space.m) {
                    HStack(spacing: Space.m) {
                        Image(systemName: m.icon).foregroundStyle(m.color).frame(width: 34, height: 34).background(m.color.opacity(0.16), in: Circle())
                        Text(m.label).font(.subsectionTitle)
                        Button { open(.add(m.time(on: day))) } label: {
                            Image(systemName: "plus").font(.secondaryEmphasis).frame(width: 30, height: 30).background(Color.raisedBackground, in: Circle()).accessibilityLabel("Add a food to \(m.label)")
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
                VStack(spacing: Space.l) {
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
                .padding(Space.l)
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
