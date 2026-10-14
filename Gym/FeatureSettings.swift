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
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(.body.weight(.semibold))
                        if let badge {
                            Text(badge).font(.caption.weight(.semibold)).padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
        .padding(.vertical, 4)
    }
}

struct WeightTrendSettingsView: View {
    @AppStorage("trendAlgorithm") private var algorithm = TrendAlgorithm.v2.rawValue

    var body: some View {
        Form {
            Section {
                RadioRow(title: "Weight Trend V2", badge: "Recommended",
                         detail: "Robust smoothing that also looks at later weigh-ins, so past values get revised and the trend lags less. Outliers like a salty dinner barely move it.",
                         selected: algorithm == TrendAlgorithm.v2.rawValue) { set(.v2) }
                RadioRow(title: "Weight Trend V1",
                         detail: "Simple and reliable smoothing that only looks at past weigh-ins.",
                         selected: algorithm == TrendAlgorithm.v1.rawValue) { set(.v1) }
            } header: {
                Text("Trend algorithm")
            } footer: {
                Text("In tests on simulated weigh-ins, V2 was about 3× closer to the true weight and showed changes sooner. Your expenditure isn't affected: it works from the weigh-ins themselves.")
            }
        }
        .themedForm()
        .navigationTitle("Weight Trend")
    }

    private func set(_ a: TrendAlgorithm) { withAnimation { algorithm = a.rawValue }; dataVersion += 1 }
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text("BMR equation")
                            Text((BMREquation(rawValue: p.bmrEquation) ?? .mifflin).label).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    editRow("Calculation mode", p.expStaticKcal > 0 ? "Static · \(p.energy.format(p.expStaticKcal))" : "Dynamic") { editing = .mode }
                    ForEach([ExpenditureAlgorithm.joint, .standard, .responsive, .stable]) { a in
                        RadioRow(title: a.label, badge: a == .joint ? "Recommended" : nil, detail: a.detail,
                                 selected: (ExpenditureAlgorithm(rawValue: p.expAlgorithm) ?? .joint) == a) {
                            p.expAlgorithm = a == .joint ? "" : a.rawValue; ctx.commit()
                        }
                    }
                } header: {
                    Text("Expenditure calculation")
                } footer: {
                    Text("V2 was 15% more accurate than V1 on average and 32% more accurate on the current day, over 300 simulated people with patchy logging and water swings (Tests/expsim).")
                }
                Section("Expenditure modifiers") {
                    Toggle(isOn: Binding(get: { p.stepInformed }, set: { p.stepInformed = $0; ctx.commit() })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Step-informed updates").font(.body.weight(.semibold))
                            Text("Uses your step trend (Apple Health) to move expenditure sooner when you walk more or less; your weight data confirms the rest.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: Binding(get: { p.predictiveGoal }, set: { p.predictiveGoal = $0; ctx.commit() })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Predictive goal adjustment").font(.body.weight(.semibold))
                            Text("When you change goal, expects expenditure to follow your new intake a little over the next two weeks (more food, more movement and digestion).")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
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
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(value).font(.callout).foregroundStyle(.secondary)
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
                        .font(.callout).foregroundStyle(.secondary)
                case .start:
                    Picker("Start", selection: $custom) { Text("Default (your first goal)").tag(false); Text("A date").tag(true) }.pickerStyle(.inline).labelsHidden()
                    if custom { DatePicker("From", selection: $day, in: ...Date(), displayedComponents: .date) }
                    Text("A fresh start for the calculation (after a long break, say), without losing any data.").font(.callout).foregroundStyle(.secondary)
                case .mode:
                    Picker("Mode", selection: $custom) { Text("Dynamic").tag(false); Text("Static").tag(true) }.pickerStyle(.inline).labelsHidden()
                    if custom { amountField }
                    Text(custom ? "A fixed number: weekly check-ins won't change your targets. Switch back any time; the dynamic estimate keeps running underneath."
                                : "Worked out from your weight and intake, updated every day. Recommended.")
                        .font(.callout).foregroundStyle(.secondary)
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
