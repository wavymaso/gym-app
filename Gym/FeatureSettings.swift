import SwiftData
import SwiftUI

// Settings → Feature settings: how the weight trend and expenditure are worked out.

/// A row you tap to choose, with a radio dot (one of a list).
struct RadioRow: View {
    let title: String
    var badge: String? = nil
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.s) {
                        Text(title).font(.bodyEmphasis)
                        if let badge {
                            Text(badge).font(.label).padding(.horizontal, Space.s).padding(.vertical, Space.xs)
                                .background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: Radius.s))
                        }
                    }
                    Text(detail).font(.secondaryText).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle().stroke(selected ? palette.accent : Color.secondary.opacity(0.5), lineWidth: 2).frame(width: 24, height: 24)
                    if selected { Circle().fill(palette.accent).frame(width: 13, height: 13) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, Space.xs)
    }
}

/// More → Diagnostics → Developer: the algorithm choices, for comparing models. Users see one trend: the
/// engine's by default, and the same one is behind the expenditure and the targets. Both choices sync.
struct DeveloperView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]

    var body: some View {
        Form {
            if let p = profiles.first {
                Section {
                    ForEach([TrendAlgorithm.engine, .v1, .v2]) { a in
                        RadioRow(title: a.label, badge: a == .engine ? "Default" : nil, detail: a.detail,
                                 selected: TrendAlgorithm(rawValue: p.trendAlgorithm) ?? .engine == a) {
                            animate { p.trendAlgorithm = a == .engine ? "" : a.rawValue; trendChoice = p.trendAlgorithm; ctx.commit() }
                        }
                    }
                } header: { Text("Weight trend") } footer: {
                    Text("Shown on every screen and used for your targets (rate and protein). Synced to all your devices.")
                }
                Section {
                    ForEach(ExpenditureAlgorithm.allCases) { a in
                        RadioRow(title: a.label, badge: a == .engine ? "Default" : nil, detail: a.detail,
                                 selected: ExpenditureAlgorithm.from(p.expAlgorithm) == a) {
                            p.expAlgorithm = a == .engine ? "" : a.rawValue; ctx.commit()
                        }
                    }
                } header: { Text("Expenditure") } footer: {
                    Text("Engine (default) works from the engine trend, the same one you see. Standard (MacroFactor-style) works from the classic trend and V2 keeps its own weight estimate, so with those the trend on screen and the one behind your targets differ. For comparison only.")
                }
                Section {
                    Text("At each check-in the new coaching engine's decision is shown next to the current rules (Why → New coaching engine). It never changes targets.")
                        .foregroundStyle(.secondary)
                } header: { Text("Coaching engine preview") }
            }
        }
        .themedForm()
        .navigationTitle("Developer")
    }
}

extension TrendAlgorithm {
    var label: String { switch self { case .engine: "Engine"; case .v1: "Classic"; case .v2: "V2 (two-sided)" } }
    var detail: String {
        switch self {
        case .engine: "Tracks your true weight, its rate and water separately, so refeeds, salty days and travel don't move it. Forecasts your weight 1–4 weeks ahead best on your history (BACKTEST.md)."
        case .v1: "Smooths day-to-day swings with past weigh-ins. Matches MacroFactor's trend weight; lags about 9 days behind a real change."
        case .v2: "Robust smoothing that also looks at later weigh-ins, so past values get revised."
        }
    }
}

struct ExpenditureSettingsView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @State private var editing: Editor?

    enum Editor: String, Identifiable { case method, start, mode; var id: String { rawValue } }

    var body: some View {
        Form {
            if let p = profiles.first {
                Section("Initial estimate") {
                    editRow("Estimation method", p.expManualKcal > 0 ? "Manual · \(p.energy.format(p.expManualKcal))" : "Default (formula)") { editing = .method }
                    editRow("Calculation start date", p.expStartDay.isEmpty ? "Default (your first goal)" : date(fromKey: p.expStartDay).formatted(.dateTime.day().month(.wide).year().locale(appLocale))) { editing = .start }
                    NavigationLink {
                        BMREquationView(profile: p)
                    } label: {
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text("BMR equation")
                            Text((BMREquation(rawValue: p.bmrEquation) ?? .mifflin).label).font(.secondaryText).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    editRow("Calculation mode", p.expStaticKcal > 0 ? "Static · \(p.energy.format(p.expStaticKcal))" : "Dynamic") { editing = .mode }
                } header: {
                    Text("Expenditure calculation")
                } footer: {
                    Text("Dynamic: the coaching engine works out your expenditure from what you eat and your weight trend (the same trend you see). Static: your own fixed number.")
                }
                Section("Expenditure modifiers") {
                    Toggle(isOn: Binding(get: { p.stepInformed }, set: { p.stepInformed = $0; ctx.commit() })) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text("Step-informed updates").font(.bodyEmphasis)
                            Text("Uses your step trend (Apple Health) to move expenditure sooner when you walk more or less; your weight data confirms the rest.")
                                .font(.secondaryText).foregroundStyle(.secondary)
                        }
                    }
                    if ExpenditureAlgorithm.from(p.expAlgorithm) != .engine { Toggle(isOn: Binding(get: { p.predictiveGoal }, set: { p.predictiveGoal = $0; ctx.commit() })) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text("Predictive goal adjustment").font(.bodyEmphasis)
                            Text("When you change goal, expects expenditure to follow your new intake a little over the next two weeks (more food, more movement and digestion).")
                                .font(.secondaryText).foregroundStyle(.secondary)
                        }
                    } }
                }
            }
        }
        .themedForm()
        .navigationTitle("Expenditure")
        .sheet(item: $editing) { e in
            if let p = profiles.first { ExpenditureEditor(profile: p, editor: e).appStyle() }
        }
    }

    private func editRow(_ title: String, _ value: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title)
                Text(value).font(.secondaryText).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit", action: action).buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }
}

/// Edits one expenditure setting: the starting estimate, the start date or static/dynamic.
struct ExpenditureEditor: View {
    let profile: Profile
    let editor: ExpenditureSettingsView.Editor
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var custom = false
    @State private var text = ""
    @State private var day = Date()

    var body: some View {
        NavigationStack {
            Form {
                switch editor {
                case .method:
                    Picker("Method", selection: $custom) { Text("Default (formula)").tag(false); Text("Manual").tag(true) }.pickerStyle(.inline).labelsHidden()
                    if custom { amountField }
                    Text("Only the starting point. If you've been logging for a while, also set a recent calculation start date for it to matter now.")
                        .font(.secondaryText).foregroundStyle(.secondary)
                case .start:
                    Picker("Start", selection: $custom) { Text("Default (your first goal)").tag(false); Text("A date").tag(true) }.pickerStyle(.inline).labelsHidden()
                    if custom { DatePicker("From", selection: $day, in: ...Date(), displayedComponents: .date) }
                    Text("A fresh start for the calculation (after a long break, say), without losing any data.").font(.secondaryText).foregroundStyle(.secondary)
                case .mode:
                    Picker("Mode", selection: $custom) { Text("Dynamic").tag(false); Text("Static").tag(true) }.pickerStyle(.inline).labelsHidden()
                    if custom { amountField }
                    Text(custom ? "A fixed number: weekly check-ins won't change your targets. Switch back any time; the dynamic estimate keeps running underneath."
                                : "Worked out from your weight and intake, updated every day. Recommended.")
                        .font(.secondaryText).foregroundStyle(.secondary)
                }
            }
            .themedForm()
            .navigationTitle(["method": "Estimation method", "start": "Calculation start", "mode": "Calculation mode"][editor.rawValue] ?? "")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(custom && editor != .start && kcal == nil) }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(width: 420, height: 320)
        #endif
    }

    private var amountField: some View {
        HStack {
            TextField("kcal a day", text: $text)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Text(profile.energy.rawValue).foregroundStyle(.secondary)
        }
    }

    private var kcal: Double? { parseNumber(text).map { profile.energy == .kJ ? $0 / 4.184 : $0 }.flatMap { (800...8000).contains($0) ? $0 : nil } }

    private func load() {
        switch editor {
        case .method: custom = profile.expManualKcal > 0; if custom { text = number(profile.energy.fromKcal(profile.expManualKcal)) }
        case .start: custom = !profile.expStartDay.isEmpty; if custom { day = date(fromKey: profile.expStartDay) }
        case .mode: custom = profile.expStaticKcal > 0
            let current = ctx.expenditureEstimates().last?.kcal ?? 2500
            text = number(profile.energy.fromKcal(custom ? profile.expStaticKcal : current))
        }
    }

    private func save() {
        switch editor {
        case .method: profile.expManualKcal = custom ? (kcal ?? 0) : 0
        case .start: profile.expStartDay = custom ? dayKey(day) : ""
        case .mode: profile.expStaticKcal = custom ? (kcal ?? 0) : 0
        }
        ctx.commit()
        dismiss()
    }
}

struct BMREquationView: View {
    let profile: Profile
    @Environment(\.modelContext) private var ctx

    var body: some View {
        Form {
            Section {
                ForEach(BMREquation.allCases) { e in
                    RadioRow(title: e.label, detail: e.detail, selected: profile.bmrEquation == e.rawValue) {
                        profile.bmrEquation = e.rawValue; ctx.commit()
                    }
                }
            } footer: {
                Text("Used for the starting estimate when you set a new calculation start date. Katch–McArdle needs a body fat % on a weigh-in; without one it falls back to Mifflin–St Jeor.")
            }
        }
        .themedForm()
        .navigationTitle("BMR Equation")
    }
}
