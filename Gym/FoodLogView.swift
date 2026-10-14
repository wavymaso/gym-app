import SwiftData
import SwiftUI

/// One day of eating: totals against your targets, then a timeline of what you ate.
struct FoodLogView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @State private var day = dayKey()
    @State private var sheet: LogSheet? = {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "searchQuery") != nil { return .add }      // testing only
        #endif
        return nil
    }()

    enum LogSheet: Identifiable {
        case add, quickAdd, copy
        case edit(FoodEntry)
        var id: String {
            switch self {
            case .add: return "add"
            case .quickAdd: return "quick"
            case .copy: return "copy"
            case .edit(let e): return "edit-\(e.persistentModelID.hashValue)"
            }
        }
    }

    var body: some View {
        let energy = profiles.first?.energy ?? .kcal
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DayPicker(day: $day)
                DayEntries(day: day, energy: energy, target: ctx.targets(on: day)) { sheet = .edit($0) }
            }
            .padding(pagePadding)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.pageBackground)
        .navigationTitle("Food log")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Copy yesterday") {
                        let y = dayKey(Calendar.current.date(byAdding: .day, value: -1, to: date(fromKey: day))!)
                        _ = ctx.copyEntries(from: y, to: day)
                    }
                    Button("Copy from a day…") { sheet = .copy }
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                Button { sheet = .quickAdd } label: { Label("Quick add", systemImage: "bolt") }
                Button { sheet = .add } label: { Label("Add food", systemImage: "plus") }
                    .keyboardShortcut("n")
            }
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .add: AddFoodView(mode: .log(day: day))
            case .quickAdd: QuickAddView(day: day, entry: nil)
            case .copy: CopyDayView(target: day)
            case .edit(let e):
                if e.isQuickAdd { QuickAddView(day: day, entry: e) } else { EntryEditor(entry: e) }
            }
        }
    }
}

/// ‹ Wednesday 14 October › with a Today button.
struct DayPicker: View {
    @Binding var day: String

    var body: some View {
        HStack(spacing: 8) {
            Button { move(-1) } label: { Image(systemName: "chevron.left") }
            Text(label).font(.title2.bold()).frame(minWidth: isPhone ? nil : 230).lineLimit(1).minimumScaleFactor(0.7)
            Button { move(1) } label: { Image(systemName: "chevron.right") }
            Spacer()
            DatePicker("Day", selection: Binding(get: { date(fromKey: day) }, set: { day = dayKey($0) }), displayedComponents: .date)
                .labelsHidden()
            if day != dayKey() { Button("Today") { day = dayKey() } }
        }
        .buttonStyle(.borderless)
    }

    private var label: String {
        let d = date(fromKey: day)
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(appLocale))
    }

    private func move(_ n: Int) {
        day = dayKey(Calendar.current.date(byAdding: .day, value: n, to: date(fromKey: day))!)
    }
}

/// The day's totals and timeline (its own view so the query follows the chosen day).
struct DayEntries: View {
    @Environment(\.modelContext) private var ctx
    @Query private var entries: [FoodEntry]
    let energy: EnergyUnit
    let target: TargetSet?
    let open: (FoodEntry) -> Void

    init(day: String, energy: EnergyUnit, target: TargetSet?, open: @escaping (FoodEntry) -> Void) {
        _entries = Query(filter: #Predicate<FoodEntry> { $0.day == day }, sort: \FoodEntry.time)
        self.energy = energy; self.target = target; self.open = open
    }

    var body: some View {
        let total = entries.reduce(Nutrients.zero) { $0 + $1.nutrients }
        Card(title: "Totals", systemImage: "chart.bar") {
            if let t = target?.targets {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(number(energy.fromKcal(total.kcal))).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("/ \(energy.format(t.kcal))").font(.title3).foregroundStyle(.secondary)
                    Spacer()
                    let left = t.kcal - total.kcal
                    Text(left >= 0 ? "\(energy.format(left)) left" : "\(energy.format(-left)) over")
                        .foregroundStyle(left >= 0 ? Color.secondary : Macro.protein.color)
                }
                adaptiveStack {
                    ForEach([Macro.protein, .fat, .carbs], id: \.self) { m in
                        MacroBar(macro: m, eaten: m.value(total.targets), target: m.value(t), energy: energy)
                    }
                }
            } else {
                Text("\(energy.format(total.kcal)) eaten").font(.title2.bold())
            }
        }
        if entries.isEmpty {
            ContentUnavailableView("Nothing logged", systemImage: "fork.knife",
                                   description: Text("Add a food (⌘N), a quick add, or copy another day."))
                .padding(.top, 30)
        } else {
            VStack(spacing: 0) {
                ForEach(entries) { e in
                    EntryRow(entry: e, energy: energy)
                        .contentShape(Rectangle())
                        .onTapGesture { open(e) }
                        .contextMenu {
                            Button("Edit…") { open(e) }
                            Button("Duplicate") {
                                ctx.insert(FoodEntry(day: e.day, time: e.time, name: e.name, brand: e.brand, foodKey: e.foodKey,
                                                     amount: e.amount, unit: e.unit, grams: e.grams, nutrients: e.nutrients))
                                ctx.commit()
                            }
                            Divider()
                            Button("Delete", role: .destructive) { ctx.delete(e); ctx.commit() }
                        }
                    if e.id != entries.last?.id { Divider().padding(.leading, 70) }
                }
            }
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.06)))
        }
    }
}

struct EntryRow: View {
    let entry: FoodEntry
    let energy: EnergyUnit

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(entry.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(appLocale)))
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
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
