import SwiftData
import SwiftUI

// The dashboard below the top widgets: sections (Nutrition, Insights & Analytics, Habits),
// each with items you choose and order. Saved per device (AppStorage "dashLayout").

struct DashLayout: Codable, Equatable {
    var sections: [Section]

    struct Section: Codable, Equatable, Identifiable {
        var kind: Kind
        var items: [String]                     // in order; only these are shown
        var remaining: [String] = []            // nutrition items shown as "remaining" rather than "consumed"
        var id: String { kind.rawValue }
    }

    enum Kind: String, Codable, CaseIterable {
        case nutrition, insights, habits
        var label: String { ["Nutrition", "Insights & Analytics", "Habits"][Self.allCases.firstIndex(of: self)!] }
        var addLabel: String { ["Add or Remove Nutrients", "Add or Remove Insights", "Add or Remove Habits"][Self.allCases.firstIndex(of: self)!] }
        /// Everything this section can show, in the default order.
        var all: [String] {
            switch self {
            case .nutrition: return ["macros", "calories", "protein", "fat", "carbs", "fiber", "sugar", "satFat", "sodium", "water"] + Micro.all.map(\.key)
            case .insights: return ["expenditure", "weight", "scale", "nutritionTrend", "energyBalance", "goal", "proteinMeals", "strength", "week", "training", "activity"]
            case .habits: return ["supplements", "score", "weighIn", "foodLogging"]
            }
        }
    }

    static let standard = DashLayout(sections: [
        Section(kind: .nutrition, items: ["macros", "calories", "fiber", "sodium"]),
        Section(kind: .insights, items: ["expenditure", "weight", "scale", "nutritionTrend", "energyBalance", "goal", "proteinMeals", "strength", "training", "week", "activity"]),
        Section(kind: .habits, items: ["supplements", "score", "weighIn", "foodLogging"]),
    ])

    static func load(_ s: String) -> DashLayout {
        guard let d = s.data(using: .utf8), var l = try? JSONDecoder().decode(DashLayout.self, from: d), l.sections.count == 3 else { return standard }
        // New items reach layouts saved before they existed (until you save your own layout).
        if !UserDefaults.standard.bool(forKey: "dashAddedSupplements") || !UserDefaults.standard.bool(forKey: "dashAddedScale") {
            for (kind, item, at) in [(Kind.habits, "supplements", 0), (Kind.insights, "proteinMeals", 4), (Kind.insights, "strength", 5),
                                     (Kind.insights, "scale", 2), (Kind.insights, "nutritionTrend", 3)] {
                if let i = l.sections.firstIndex(where: { $0.kind == kind }), !l.sections[i].items.contains(item) {
                    l.sections[i].items.insert(item, at: min(at, l.sections[i].items.count))
                }
            }
        }
        return l
    }

    var json: String { (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "" }
}

/// Names, icons and colours for every dashboard item.
enum DashItem {
    static func label(_ id: String) -> String {
        if let m = Micro.all.first(where: { $0.key == id }) { return m.label }
        return ["macros": "Macros", "calories": "Calories", "protein": "Protein", "fat": "Fat", "carbs": "Carbs", "fiber": "Fibre",
                "sugar": "Sugar", "satFat": "Saturated fat", "sodium": "Sodium", "water": "Water",
                "expenditure": "Expenditure", "weight": "Weight Trend", "energyBalance": "Energy Balance", "goal": "Goal Progress",
                "week": "Last 7 days", "training": "Training this week", "activity": "Water & activity",
                "score": "Habit score", "weighIn": "Weigh-In", "foodLogging": "Food Logging", "supplements": "Supplements", "proteinMeals": "Protein per meal", "strength": "Strength retention",
                "scale": "Scale Weight", "nutritionTrend": "Calories & Macros"][id] ?? id
    }

    static func color(_ id: String) -> Color {
        switch id {
        case "calories", "expenditure": return Macro.calories.color
        case "protein": return Macro.protein.color
        case "fat", "satFat", "energyBalance": return Macro.fat.color
        case "carbs", "fiber", "foodLogging", "goal": return Macro.carbs.color
        case "water", "activity": return Color.waterTone
        case "weight", "weighIn": return Color.weightTone
        case "sugar", "sodium", "cholesterol": return Color.alertTone
        default: return Color.extraTone
        }
    }

    /// The little picture beside each item in the customize screen.
    @ViewBuilder static func glyph(_ id: String) -> some View {
        let c = color(id)
        ZStack {
            RoundedRectangle(cornerRadius: Radius.s).fill(Color.raisedBackground)
            switch id {
            case "macros":
                HStack(alignment: .bottom, spacing: Space.xxs) {
                    ForEach([(Macro.protein.color, 9.0), (Macro.fat.color, 14.0), (Macro.carbs.color, 11.0)], id: \.1) { Capsule().fill($0.0).frame(width: 4, height: $0.1) }
                }
            case "expenditure", "weight":
                Image(systemName: "chart.line.uptrend.xyaxis").font(.label).foregroundStyle(c)
            case "energyBalance", "week", "training":
                Image(systemName: "chart.bar.fill").font(.note).foregroundStyle(c)
            case "goal":
                HStack(spacing: Space.xxs) { Capsule().fill(c).frame(width: 14, height: 4); Capsule().fill(Color.extraTone).frame(width: 5, height: 4) }
            case "weighIn", "foodLogging", "score":
                HStack(spacing: Space.xxs) { ForEach(0..<3, id: \.self) { _ in Circle().fill(c).frame(width: 5, height: 5) } }
            default:
                Capsule().fill(c).frame(width: 22, height: 5)
            }
        }
        .frame(width: 34, height: 26)
    }
}

/// Customize Dashboard: move sections, reorder items, add or remove them, consumed or remaining.
struct CustomizeDashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("dashLayout") private var saved = ""
    @State private var layout = DashLayout.standard
    @State private var adding: DashLayout.Kind?

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(layout.sections.enumerated()), id: \.element.id) { i, section in
                    Section {
                        ForEach(section.items, id: \.self) { id in row(i, id) }
                            .onMove { layout.sections[i].items.move(fromOffsets: $0, toOffset: $1) }
                            .onDelete { layout.sections[i].items.remove(atOffsets: $0) }
                        Button { adding = section.kind } label: {
                            Text(section.kind.addLabel).font(.bodyEmphasis).frame(maxWidth: .infinity).padding(.vertical, Space.s)
                                .background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: Radius.m))
                        }
                        .buttonStyle(.plain)
                    } header: {
                        HStack {
                            Text(section.kind.label).font(.subsectionTitle).foregroundStyle(.primary).textCase(nil)
                            Spacer()
                            Button { move(i, -1) } label: { Image(systemName: "arrow.up") }.disabled(i == 0).accessibilityLabel("Move section up")
                            Button { move(i, 1) } label: { Image(systemName: "arrow.down") }.disabled(i == layout.sections.count - 1).accessibilityLabel("Move section down")
                        }
                        .buttonStyle(.borderless).font(.bodyEmphasis)
                    }
                }
                Section {
                    Button("Reset to defaults") { layout = .standard }
                }
            }
            .themedList()
            #if os(iOS)
            .environment(\.editMode, .constant(.active))         // drag handles always showing
            #endif
            .navigationTitle("Customize Dashboard")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { saved = layout.json; UserDefaults.standard.set(true, forKey: "dashAddedSupplements"); UserDefaults.standard.set(true, forKey: "dashAddedScale"); dismiss() } }
            }
            .sheet(item: $adding) { kind in
                AddRemoveItemsView(kind: kind, selected: Binding(
                    get: { layout.sections.first { $0.kind == kind }?.items ?? [] },
                    set: { v in if let i = layout.sections.firstIndex(where: { $0.kind == kind }) { layout.sections[i].items = v } }))
            }
            .onAppear { layout = DashLayout.load(saved) }
        }
        .appStyle()
        #if os(macOS)
        .frame(width: 460, height: 640)
        #endif
    }

    private func row(_ i: Int, _ id: String) -> some View {
        HStack(spacing: Space.m) {
            DashItem.glyph(id)
            Text(DashItem.label(id))
            Spacer()
            if layout.sections[i].kind == .nutrition && id != "macros" {
                let rem = layout.sections[i].remaining.contains(id)
                Menu {
                    Button("Consumed") { layout.sections[i].remaining.removeAll { $0 == id } }
                    Button("Remaining") { if !rem { layout.sections[i].remaining.append(id) } }
                } label: {
                    HStack(spacing: Space.xs) { Text(rem ? "Remaining" : "Consumed"); Image(systemName: "chevron.down").font(.note) }
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
            #if os(macOS)
            Button { layout.sections[i].items.removeAll { $0 == id } } label: { Image(systemName: "minus.circle").accessibilityLabel("Remove card") }.buttonStyle(.borderless)
            #endif
        }
    }

    private func move(_ i: Int, _ by: Int) {
        animate { layout.sections.swapAt(i, i + by) }
    }
}

extension DashLayout.Kind: Identifiable { var id: String { rawValue } }

/// Tick what a section shows.
struct AddRemoveItemsView: View {
    let kind: DashLayout.Kind
    @Binding var selected: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(kind.all, id: \.self) { id in
                    Toggle(isOn: Binding(get: { selected.contains(id) }, set: { on in
                        if on { if !selected.contains(id) { selected.append(id) } } else { selected.removeAll { $0 == id } }
                    })) {
                        HStack(spacing: Space.m) { DashItem.glyph(id); Text(DashItem.label(id)) }
                    }
                }
            }
            .themedList()
            .navigationTitle(kind.addLabel)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .appStyle()
        #if os(macOS)
        .frame(width: 380, height: 560)
        #endif
    }
}

// MARK: - Sections on the dashboard

/// Nutrition section: macros overview and one bar per chosen nutrient, consumed or remaining.
struct NutritionSection: View {
    let items: [String]
    let remaining: [String]
    let eaten: Nutrients
    let target: Targets
    let energy: EnergyUnit
    let waterMl: Double
    let waterGoal: Double
    let sex: Sex
    var profile: Profile? = nil

    var body: some View {
        Card(title: "Nutrition", systemImage: "leaf") {
            VStack(spacing: Space.m) {
                ForEach(items, id: \.self) { id in
                    if id == "macros" { macros } else if let (v, t, unit, limit) = values(id) { bar(id, v, t, unit, limit) }
                }
            }
        }
    }

    private var macros: some View {
        HStack(spacing: Space.s) {
            ForEach([Macro.protein, .fat, .carbs], id: \.self) { m in
                let v = m.value(eaten.targets), t = m.value(target)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(m.label).font(.label).foregroundStyle(.secondary)
                    Text("\(number(v))/\(number(t)) g").font(.numberSmall).monospacedDigit()
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(m.color.opacity(0.16))
                            Capsule().fill(m.color).frame(width: max(6, g.size.width * min(1, t > 0 ? v / t : 0))).opacity(v > 0 ? 1 : 0)
                        }
                    }
                    .frame(height: 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// (amount, target, unit, is a limit) for a nutrient, or nil if unknown.
    private func values(_ id: String) -> (Double?, Double, String, Bool)? {
        switch id {
        case "calories": return (eaten.kcal, target.kcal, energy.rawValue, false)
        case "protein": return (eaten.protein, target.protein, "g", false)
        case "fat": return (eaten.fat, target.fat, "g", false)
        case "carbs": return (eaten.carbs, target.carbs, "g", false)
        case "fiber", "sugar", "satFat", "sodium":
            let t = nutrientTarget(id, kcal: target.kcal, sex: sex, profile: profile)
            let v: Double? = ["fiber": eaten.fiber, "sugar": eaten.sugar, "satFat": eaten.satFat, "sodium": eaten.sodium][id] ?? nil
            return (v, t.value, id == "sodium" ? "mg" : "g", t.limit)
        case "water": return (waterMl, waterGoal, "ml", false)
        default:
            guard let m = Micro.all.first(where: { $0.key == id }) else { return nil }
            return (eaten.micros?[m.key], nutrientTarget(m.key, kcal: target.kcal, sex: sex, profile: profile).value, m.unit, m.isLimit)
        }
    }

    private func bar(_ id: String, _ v: Double?, _ t: Double, _ unit: String, _ limit: Bool) -> some View {
        let c = DashItem.color(id)
        let showLeft = remaining.contains(id)
        let amount = id == "calories" ? (v ?? 0).map { energy.fromKcal($0) } : v
        let targ = id == "calories" ? energy.fromKcal(t) : t
        let text: String = {
            guard let a = amount else { return "no data" }
            if showLeft { return a <= targ ? "\(number(targ - a, digits: targ < 10 ? 1 : 0)) \(unit) left" : "\(number(a - targ, digits: targ < 10 ? 1 : 0)) \(unit) over" }
            return "\(number(a, digits: targ < 10 ? 1 : 0)) / \(limit ? "max " : "")\(number(targ, digits: targ < 10 ? 1 : 0)) \(unit)"
        }()
        let p = (v ?? 0) / max(t, 0.0001)
        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(DashItem.label(id)).font(.secondaryEmphasis)
                Spacer()
                Text(text).font(.secondaryText).monospacedDigit().foregroundStyle(limit && p > 1 ? palette.warn : .secondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(c.opacity(0.16))
                    Capsule().fill(limit && p > 1 ? palette.warn : c)
                        .frame(width: max(6, g.size.width * min(1, showLeft ? max(0, 1 - p) : p))).opacity(v == nil ? 0 : 1)
                }
            }
            .frame(height: 7)
        }
    }
}

/// A habit as a row of dots, one per day: done or not.
struct HabitDotsCard: View {
    let title: String
    let color: Color
    let done: Set<String>          // day keys
    var days = 14

    var body: some View {
        let range = (0..<days).map { addDays(dayKey(), $0 - days + 1) }
        let count = range.filter(done.contains).count
        var streak = 0
        for d in range.reversed() { if done.contains(d) { streak += 1 } else if d != dayKey() { break } }
        return Card(title: title, systemImage: "checkmark.circle") {
            HStack(alignment: .firstTextBaseline) {
                Text("\(count)/\(days)").font(.numberLarge).monospacedDigit()
                Text("days").foregroundStyle(.secondary)
                Spacer()
                if streak > 1 { Label("\(streak) in a row", systemImage: "flame.fill").font(.label).foregroundStyle(palette.warn) }
            }
            HStack(spacing: Space.xs) {
                ForEach(range, id: \.self) { d in
                    Circle().fill(done.contains(d) ? color : Color.raisedBackground)
                        .overlay { if d == dayKey() { Circle().stroke(color, lineWidth: 1.5) } }
                        .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }
}

/// Insight: the last 30 days of intake against targets or expenditure.
struct EnergyBalanceWidget: View {
    let intake: [String: Double]           // finished days
    let target: (String) -> Double?
    let expenditure: [String: Double]
    let energy: EnergyUnit
    @AppStorage("balanceView") private var vsExpenditure = false

    var body: some View {
        let days = (1...30).map { addDays(dayKey(), -31 + $0) }
        let logged = days.filter { intake[$0] != nil }
        let avgIn = logged.isEmpty ? 0 : logged.reduce(0) { $0 + intake[$1]! } / Double(logged.count)
        let refDays = logged.compactMap { vsExpenditure ? expenditure[$0] : target($0) }
        let avgRef = refDays.isEmpty ? 0 : refDays.reduce(0, +) / Double(refDays.count)
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text("Last 30 days").font(.cardTitle)
                Spacer()
                Picker("", selection: $vsExpenditure) { Text("Targets").tag(false); Text("Expenditure").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            HStack(alignment: .bottom, spacing: Space.xxs) {
                ForEach(days, id: \.self) { d in
                    let k = intake[d] ?? 0, ref = (vsExpenditure ? expenditure[d] : target(d)) ?? 0
                    GeometryReader { g in
                        let top = max(avgRef * 1.5, 1)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: Radius.xs).fill(Macro.calories.color.opacity(k > 0 ? 0.85 : 0)).frame(height: g.size.height * min(1, k / top))
                            Rectangle().fill(vsExpenditure ? Macro.fat.color : Color.primary.opacity(0.6)).frame(height: 2)
                                .offset(y: -g.size.height * min(1, ref / top) + 1).opacity(ref > 0 ? 1 : 0)
                        }
                        .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
                    }
                }
            }
            .frame(height: 90)
            HStack(spacing: Space.s) {
                Text(energy.format(avgIn)).font(.numberSmall)
                Text("−").foregroundStyle(.secondary)
                Text(energy.format(avgRef)).font(.numberSmall)
                Text("=").foregroundStyle(.secondary)
                Text(signedKcal(avgIn - avgRef, energy)).font(.numberSmall)
                    .foregroundStyle(vsExpenditure ? (avgIn < avgRef ? palette.good : palette.warn) : .primary)
                Spacer()
                Text(vsExpenditure ? (avgIn < avgRef ? "deficit" : "surplus") : "vs targets").font(.note).foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
    }
}
