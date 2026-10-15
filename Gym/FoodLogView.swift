import SwiftData
import SwiftUI

/// One day of eating: a week strip, the day's rings, then meals (or a timeline).
struct FoodLogView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @State private var day = dayKey()
    @AppStorage("foodLogStyle") private var style: LogStyle = .meals
    @State private var sheet: LogSheet? = {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "searchQuery") != nil { return .add(nil) }      // testing only
        #endif
        return nil
    }()

    enum LogStyle: String, CaseIterable { case meals, timeline }

    enum LogSheet: Identifiable {
        case add(Date?), quickAdd(Date?), copy
        case edit(FoodEntry)
        var id: String {
            switch self {
            case .add(let t): return "add\(t?.timeIntervalSince1970 ?? 0)"
            case .quickAdd(let t): return "quick\(t?.timeIntervalSince1970 ?? 0)"
            case .copy: return "copy"
            case .edit(let e): return "edit-\(e.persistentModelID.hashValue)"
            }
        }
    }

    var body: some View {
        #if os(iOS)
        PhoneFoodLog()
        #else
        macBody
        #endif
    }

    private var macBody: some View {
        let energy = profiles.first?.energy ?? .kcal
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isPhone { header }
                WeekStrip(day: $day)
                DayLog(day: day, energy: energy, target: ctx.dayTargets(on: day),
                       style: $style) { sheet = $0 }
            }
            .padding(pagePadding)
            .frame(maxWidth: isPhone ? 820 : 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .debugScrollAnchor()
        .pageBackground()
        .navigationTitle("Food log")
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #else
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Copy yesterday") { _ = ctx.copyEntries(from: addDays(day, -1), to: day) }
                    Button("Copy from a day…") { sheet = .copy }
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                Button { sheet = .quickAdd(nil) } label: { Label("Quick add", systemImage: "bolt") }
                Button { sheet = .add(nil) } label: { Label("Add food", systemImage: "plus") }
                    .keyboardShortcut("n")
            }
        }
        #endif
        .sheet(item: $sheet) { s in
            switch s {
            case .add(let t): FoodLogger(day: day, time: t)
            case .quickAdd(let t): QuickAddView(day: day, entry: nil, at: t)
            case .copy: CopyDayView(target: day)
            case .edit(let e):
                if e.isQuickAdd { QuickAddView(day: day, entry: e) } else { EntryEditor(entry: e) }
            }
        }
    }
}

extension FoodLogView {
    /// The phone's page header: FOOD LOG, and the day's actions as round buttons.
    var header: some View {
        HStack(alignment: .center) {
            Text("FOOD LOG").font(.pageTitle(30)).foregroundStyle(palette.titleStyle).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(GlowStyle.on || palette.glass
                                 ? AnyShapeStyle(LinearGradient(colors: [.primary, palette.accent], startPoint: .leading, endPoint: .trailing))
                                 : AnyShapeStyle(.primary))
            Spacer()
            Menu {
                Button("Copy yesterday", systemImage: "doc.on.doc") { _ = ctx.copyEntries(from: addDays(day, -1), to: day) }
                Button("Copy from a day…", systemImage: "calendar") { sheet = .copy }
            } label: { roundIcon("doc.on.doc") }
            .menuStyle(.button).buttonStyle(.plain)
            Button { sheet = .add(nil) } label: { roundIcon("plus") }.buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    func roundIcon(_ name: String) -> some View {
        Image(systemName: name).font(.headline).frame(width: 44, height: 44).modifier(GlassCapsule())
    }
}

/// Monday to Sunday around the chosen day, each with a little calorie ring.
struct WeekStrip: View {
    @Binding var day: String
    @Query private var entries: [FoodEntry]
    @Query(sort: \TargetSet.fromDay, order: .reverse) private var targetSets: [TargetSet]
    @Query private var profiles: [Profile]
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
        VStack(spacing: 10) {
            HStack {
                Text(title).font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                if day != dayKey() {
                    Button("Today") { animate { day = dayKey() } }.buttonStyle(.bordered).controlSize(.small)
                }
                Button { move(-7) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                Button { move(7) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
            }
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    let d = addDays(monday, i)
                    let base = targetSets.first { $0.fromDay <= d }?.targets
                    let t = base.map { b in profiles.first.map { $0.adjust(b, on: d) } ?? b }?.kcal ?? 0
                    Button { animate(Motion.snappy) { day = d } } label: {
                        VStack(spacing: 6) {
                            Text(date(fromKey: d).formatted(.dateTime.weekday(.narrow).locale(appLocale)))
                                .font(.caption2.weight(.semibold)).foregroundStyle(d == day ? .primary : .secondary)
                            ZStack {
                                Ring(progress: t > 0 ? (kcal[d] ?? 0) / t : 0, color: Macro.calories.color, lineWidth: 3.5)
                                Text(date(fromKey: d).formatted(.dateTime.day().locale(appLocale)))
                                    .font(.caption.weight(.bold)).monospacedDigit()
                                    .foregroundStyle(d == dayKey() && d != day ? palette.accent : .primary)
                            }
                            .frame(width: 34, height: 34)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                            .stroke(d == day ? Color.primary.opacity(0.85) : .clear, lineWidth: 2))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(d > dayKey() ? 0.45 : 1)
                }
            }
            .padding(6)
            .modifier(CardSurface(cornerRadius: Radius.l))
            .capType()
        }
    }

    private var title: String {
        let d = date(fromKey: day)
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(appLocale))
    }

    private func move(_ n: Int) { animate(Motion.snappy) { day = addDays(day, n) } }
}

/// The day's rings and entries (its own view so the query follows the chosen day).
struct DayLog: View {
    @Environment(\.modelContext) private var ctx
    @Query private var entries: [FoodEntry]
    let day: String
    let energy: EnergyUnit
    let target: Targets?
    @Binding var style: FoodLogView.LogStyle
    let open: (FoodLogView.LogSheet) -> Void

    @State private var savingMeal: (Meal, [FoodEntry])?
    @AppStorage("showEmptyHours") private var showEmptyHours = true
    @State private var mealName = ""

    init(day: String, energy: EnergyUnit, target: Targets?, style: Binding<FoodLogView.LogStyle>, open: @escaping (FoodLogView.LogSheet) -> Void) {
        _entries = Query(filter: #Predicate<FoodEntry> { $0.day == day }, sort: \FoodEntry.time)
        self.day = day; self.energy = energy; self.target = target; _style = style; self.open = open
    }

    var body: some View {
        let total = entries.reduce(Nutrients.zero) { $0 + $1.nutrients }
        if isPhone {
            summary(total)
                .sensoryFeedback(.success, trigger: entries.count) { old, new in new > old }
            log
            if !entries.isEmpty { NutrientPanel(total: total, entries: entries) }
            DayNoteCard(day: day)
        } else {
            // The Mac: the day's food on the left, its totals and nutrients beside it.
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) { log }
                    .frame(maxWidth: .infinity)
                VStack(spacing: 16) {
                    summary(total)
                    DayNoteCard(day: day)
                    if !entries.isEmpty { NutrientPanel(total: total, entries: entries) }
                }
                .frame(width: 360)
            }
            .sensoryFeedback(.success, trigger: entries.count) { old, new in new > old }
        }

    }

    @ViewBuilder private var log: some View {
        HStack {
            Picker("View", selection: $style.animation(.snappy)) {
                Text("Meals").tag(FoodLogView.LogStyle.meals)
                Text("Timeline").tag(FoodLogView.LogStyle.timeline)
            }
            .pickerStyle(.segmented).labelsHidden()
            if style == .timeline {
                Toggle(isOn: $showEmptyHours.animation(.snappy)) { Label("Empty hours", systemImage: "clock") }
                    .toggleStyle(.button).controlSize(.small).fixedSize()
                    .help("Show hours with nothing logged (you can drop food onto them)")
            }
        }
            .alert("Save as meal", isPresented: Binding(get: { savingMeal != nil }, set: { if !$0 { savingMeal = nil } })) {
                TextField("Name", text: $mealName)
                Button("Save") { if let (_, items) = savingMeal { ctx.saveMeal(mealName.isEmpty ? "Meal" : mealName, from: items) }; savingMeal = nil }
                Button("Cancel", role: .cancel) { savingMeal = nil }
            } message: { Text("Log these foods again in one tap, from Add food → Meals.") }
        if style == .timeline {
            if entries.isEmpty {
                ContentUnavailableView("Nothing logged", systemImage: "fork.knife",
                                       description: Text("Add a food (⌘N), a quick add, or copy another day."))
                    .padding(.top, 20)
            } else {
                timeline
            }
        } else {
            let imported = entries.filter { $0.foodKey == "import" }
            let own = entries.filter { $0.foodKey != "import" }
            if !imported.isEmpty {
                section(title: "Imported", icon: "square.and.arrow.down.fill", color: .secondary, items: imported, meal: nil)
            }
            ForEach(Meal.allCases) { m in
                section(title: m.label, icon: m.icon, color: m.color, items: own.filter { Meal(time: $0.time) == m }, meal: m)
            }
        }
    }

    // MARK: Pieces

    /// The day by hour. Drag an entry onto another hour to move it there (minutes kept).
    private var timeline: some View {
        let cal = Calendar.current
        let byHour = Dictionary(grouping: entries) { cal.component(.hour, from: $0.time) }
        let lo = min(6, byHour.keys.min() ?? 6), hi = max(23, byHour.keys.max() ?? 23)
        let hours = showEmptyHours ? Array(lo...hi) : byHour.keys.sorted()
        return VStack(spacing: 0) {
            ForEach(hours, id: \.self) { h in
                HourRow(hour: h, items: byHour[h] ?? [], energy: energy, open: { open(.edit($0)) },
                        add: { open(.add(cal.date(bySettingHour: h, minute: 0, second: 0, of: date(fromKey: day)))) },
                        drop: { ids in move(ids, to: h) })
                if h != hours.last { Divider().opacity(0.5) }
            }
        }
        .modifier(CardSurface())
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

    /// MacroFactor's day summary: four columns, consumed or remaining (tap to switch), thin bars.
    private func summary(_ total: Nutrients) -> some View {
        DaySummary(total: total, target: target, energy: energy)
    }

    private func section(title: String, icon: String, color: Color, items: [FoodEntry], meal: Meal?) -> some View {
        let n = items.reduce(Nutrients.zero) { $0 + $1.nutrients }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.callout).foregroundStyle(color)
                    .frame(width: 30, height: 30).background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    if !items.isEmpty {
                        Text("\(energy.format(n.kcal)) · P \(number(n.protein)) · F \(number(n.fat)) · C \(number(n.carbs))")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Spacer()
                if let meal {
                    Menu {
                        Button { open(.add(meal.time(on: day))) } label: { Label("Add food", systemImage: "plus") }
                        Button { open(.quickAdd(meal.time(on: day))) } label: { Label("Quick add", systemImage: "bolt") }
                        if !items.isEmpty && day != dayKey() {
                            Divider()
                            Button { copy(items, to: dayKey(), meal: meal) } label: { Label("Copy to today", systemImage: "doc.on.doc") }
                        }
                        if !items.isEmpty {
                            Button { copy(items, to: addDays(day, 1), meal: meal) } label: { Label("Copy to the next day", systemImage: "arrow.right.doc.on.clipboard") }
                            Button { savingMeal = (meal, items); mealName = meal.label } label: { Label("Save as meal…", systemImage: "square.and.arrow.down") }
                        }
                    } label: {
                        Image(systemName: "plus").font(.body.weight(.bold)).foregroundStyle(palette.accent)
                            .frame(width: 32, height: 32).background(palette.accent.opacity(0.14), in: Circle())
                    } primaryAction: {
                        open(.add(meal.time(on: day)))
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
            }
            .padding(14)
            if !items.isEmpty {
                Divider().padding(.leading, 14)
                rows(items, showTime: false, framed: false)
            }
        }
        .modifier(CardSurface())
    }

    @ViewBuilder private func rows(_ list: [FoodEntry], showTime: Bool, framed: Bool = true) -> some View {
        let content = VStack(spacing: 0) {
            ForEach(list) { e in
                EntryRow(entry: e, energy: energy, showTime: showTime)
                    .contentShape(Rectangle())
                    .onTapGesture { open(.edit(e)) }
                    .contextMenu {
                        Button("Edit…") { open(.edit(e)) }
                        Button("Duplicate") {
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
                                .disabled(Meal(time: e.time) == m)
                            }
                        }
                        Divider()
                        Button("Delete", role: .destructive) { ctx.deleteWithUndo([e], "\(e.name) removed") }
                    }
                if e.id != list.last?.id { Divider().padding(.leading, showTime ? 70 : 14) }
            }
        }
        if framed {
            content.modifier(CardSurface())
        } else {
            content
        }
    }

    /// Copy a meal's entries to another day, at the same times.
    private func copy(_ items: [FoodEntry], to target: String, meal: Meal) {
        let cal = Calendar.current
        for e in items {
            let hm = cal.dateComponents([.hour, .minute], from: e.time)
            let t = cal.date(bySettingHour: hm.hour ?? 12, minute: hm.minute ?? 0, second: 0, of: date(fromKey: target)) ?? e.time
            ctx.insert(FoodEntry(day: target, time: t, name: e.name, brand: e.brand, foodKey: e.foodKey, amount: e.amount, unit: e.unit,
                                 grams: e.grams, nutrients: e.nutrients))
        }
        ctx.commit()
    }
}

/// "Protein ▬▬▬▬░░ 76/188" on one line.
struct CompactMacroBar: View {
    let macro: Macro
    let eaten: Double
    let target: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(macro.label).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6).frame(width: 52, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(macro.color.opacity(0.16))
                    Capsule().fill(macro.color).frame(width: max(8, g.size.width * min(1, target > 0 ? eaten / target : 0)))
                        .opacity(eaten > 0 ? 1 : 0)
                }
            }
            .frame(height: 8)
            HStack(spacing: 0) {
                Text(number(eaten)).fontWeight(.semibold)
                Text("/\(number(target))").foregroundStyle(.secondary)
            }
            .font(.caption).monospacedDigit().frame(width: 64, alignment: .trailing)
        }
    }
}

struct EntryRow: View {
    let entry: FoodEntry
    let energy: EnergyUnit
    var showTime = true

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if showTime {
                Text(entry.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(appLocale)))
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.body.weight(.medium)).lineLimit(1)
                Text([entry.brand, entry.amountText].compactMap { $0 }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(energy.format(entry.nutrients.kcal)).font(.body.weight(.semibold)).monospacedDigit()
                MacroLine(n: entry.nutrients)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

/// "● 30  ● 10  ● 40" in protein / fat / carb colours.
struct MacroLine: View {
    let n: Nutrients
    var body: some View {
        HStack(spacing: 8) {
            ForEach([Macro.protein, .fat, .carbs], id: \.self) { m in
                HStack(spacing: 3) {
                    Circle().fill(m.color).frame(width: 6, height: 6)
                    Text(number(m.value(n.targets))).monospacedDigit()
                }
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}

/// Copy everything from another day into this one.
struct CopyDayView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let target: String
    @State private var source = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

    var body: some View {
        let entries = ctx.entries(on: dayKey(source))
        NavigationStack {
            Form {
                DatePicker("Copy from", selection: $source, displayedComponents: .date)
                Section("\(entries.count) entries · \(number(entries.reduce(0) { $0 + $1.nutrients.kcal })) kcal") {
                    ForEach(entries) { e in
                        LabeledContent(e.name, value: e.amountText)
                    }
                }
            }
            .themedForm()
            .navigationTitle("Copy a day")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") { _ = ctx.copyEntries(from: dayKey(source), to: target); dismiss() }
                        .disabled(entries.isEmpty || dayKey(source) == target)
                }
            }
        }
        .appStyle()                             // sheets don't inherit these on the Mac
        #if os(macOS)
        .frame(width: 460, height: 520)
        #endif
    }
}

/// One hour of the timeline: its entries, or a thin empty slot you can drop onto.
struct HourRow: View {
    let hour: Int
    let items: [FoodEntry]
    let energy: EnergyUnit
    let open: (FoodEntry) -> Void
    let add: () -> Void
    let drop: ([String]) -> Bool
    @State private var targeted = false

    var body: some View {
        let kcal = items.reduce(0) { $0 + $1.nutrients.kcal }
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: "%02d:00", hour)).font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(items.isEmpty ? .tertiary : .secondary)
                if !items.isEmpty { Text(number(energy.fromKcal(kcal))).font(.caption2).foregroundStyle(.secondary).monospacedDigit() }
            }
            .frame(width: 44, alignment: .leading)
            .padding(.top, items.isEmpty ? 0 : 10)
            if items.isEmpty {
                Rectangle().fill(.clear).frame(height: 26).frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: add)
            } else {
                VStack(spacing: 0) {
                    ForEach(items.sorted { $0.time < $1.time }) { e in
                        EntryRow(entry: e, energy: energy, showTime: false)
                            .contentShape(Rectangle())
                            .onTapGesture { open(e) }
                            .draggable(e.syncID) {
                                Text(e.name).font(.callout.weight(.semibold)).padding(8)
                                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.s))
                            }
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, items.isEmpty ? 4 : 2)
        .background(targeted ? palette.accent.opacity(0.18) : .clear)
        .dropDestination(for: String.self) { ids, _ in drop(ids) } isTargeted: { targeted = $0 }
    }
}

/// Calories, protein, fat, carbs for the day: big numbers, "of target", a thin bar. Tap to flip
/// between what you've eaten and what's left (shared with the dashboard's weekly grid).
struct DaySummary: View {
    let total: Nutrients
    let target: Targets?
    let energy: EnergyUnit
    @AppStorage("weekGridRemaining") private var remaining = false

    var body: some View {
        Button { animate(Motion.snappy) { remaining.toggle() } } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(remaining ? "Remaining" : "Consumed").font(.caption.weight(.bold)).textCase(.uppercase).tracking(0.6)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "arrow.left.arrow.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Macro.allCases, id: \.self) { m in column(m) }
                }
            }
            .padding(16)
            .modifier(CardSurface())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .capType()
    }

    private func column(_ m: Macro) -> some View {
        let eaten = m.value(total.targets), goal = target.map { m.value($0) } ?? 0
        let shown = remaining ? goal - eaten : eaten
        let conv: (Double) -> Double = { m == .calories ? energy.fromKcal($0) : $0 }
        let frac = goal > 0 ? eaten / goal : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                Text(number(conv(abs(shown)))).font(.number(m == .calories ? 22 : 20, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .liveNumber(shown).foregroundStyle(remaining && shown < 0 ? palette.warn : .primary)
                if m != .calories { Text(m.short).font(.subheadline.weight(.semibold)).foregroundStyle(m.color) }
            }
            Text(remaining && shown < 0 ? "over" : "of \(number(conv(goal)))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(m.color.opacity(0.18))
                    Capsule().fill(frac > 1.05 ? palette.warn : m.color).frame(width: g.size.width * min(frac, 1))
                        .shadow(color: GlowStyle.on ? m.color.opacity(0.7) : .clear, radius: 4)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
