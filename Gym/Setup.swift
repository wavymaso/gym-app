import SwiftData
import SwiftUI

/// Answers collected during setup (and when changing your goal).
@Observable final class SetupDraft {
    var weightUnit: WeightUnit = .kg
    var energyUnit: EnergyUnit = .kcal
    var sex: Sex = .male
    var birthDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2003, month: 1, day: 1))!
    var heightCm = 175.0
    var weightKg: Double?
    var activity: Activity = .moderate
    var goal: GoalType = .lose
    var ratePercent = GoalType.lose.defaultRate
    var diet: DietStyle = .balanced
    var protein: ProteinLevel = .moderate

    var expenditure: Double {
        startingExpenditure(sex: sex, weightKg: weightKg ?? 70, heightCm: heightCm, age: age(born: birthDate), activity: activity)
    }

    var targets: Targets {
        makeTargets(expenditure: expenditure, weightKg: weightKg ?? 70, sex: sex, goal: goal, ratePercent: ratePercent,
                    diet: diet, protein: protein)
    }
}

/// First launch: a few questions, then your starting expenditure and targets.
struct SetupView: View {
    @Environment(\.modelContext) private var ctx
    @State private var draft = SetupDraft()
    @State private var step: Int = {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "setupStep")      // testing only: -setupStep 4
        #else
        return 0
        #endif
    }()
    private let steps = 7
    @State private var connecting = false

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(step + 1), total: Double(steps)).padding(.horizontal, 24).padding(.top, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case 0: UnitsStep(draft: draft)
                    case 1: AboutStep(draft: draft)
                    case 2: WeightStep(draft: draft)
                    case 3: ActivityStep(draft: draft)
                    case 4: GoalStep(draft: draft)
                    case 5: DietStep(draft: draft)
                    default: SummaryStep(draft: draft)
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(pagePadding)
                .frame(maxWidth: .infinity)
            }
            HStack {
                if step > 0 { Button("Back") { withAnimation { step -= 1 } } }
                #if os(iOS)
                if step == 0 { Button("Use my Mac's data") { connecting = true } }
                #endif
                Spacer()
                Button(step == steps - 1 ? "Start" : "Continue") {
                    if step == steps - 1 { finish() } else { withAnimation { step += 1 } }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(step == 2 && draft.weightKg == nil)
            }
            .controlSize(.large)
            .frame(maxWidth: 520)
            .padding(pagePadding)
            .frame(maxWidth: .infinity)
        }
        .pageBackground()
        #if os(iOS)
        .sheet(isPresented: $connecting) { ConnectMacView().appStyle() }
        #endif
    }

    private func finish() {
        guard let kg = draft.weightKg else { return }
        ctx.insert(Profile(sex: draft.sex, birthDate: draft.birthDate, heightCm: draft.heightCm, activity: draft.activity,
                           weightUnit: draft.weightUnit, energyUnit: draft.energyUnit))
        ctx.insert(WeightEntry(kg: kg))
        ctx.startProgram(goal: draft.goal, ratePercent: draft.ratePercent, diet: draft.diet, protein: draft.protein,
                         weightKg: kg, expenditure: draft.expenditure, sex: draft.sex, reason: "setup")
    }
}

// MARK: - Steps

private struct StepTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
}

/// A tappable option with a tick, used for every single-choice question.
struct ChoiceRow: View {
    let title: String
    var detail: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    if let detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected ? palette.accent : Color.secondary.opacity(0.5))
            }
            .padding(14)
            .contentShape(Rectangle())
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? palette.accent : .primary.opacity(0.08), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

struct UnitsStep: View {
    @Bindable var draft: SetupDraft
    var body: some View {
        StepTitle(title: "Welcome", subtitle: "A few questions to work out what you burn in a day and set your starting targets. You can change all of it later.")
        Picker("Weight", selection: $draft.weightUnit) {
            Text("Kilograms (kg)").tag(WeightUnit.kg)
            Text("Pounds (lb)").tag(WeightUnit.lb)
        }
        Picker("Energy", selection: $draft.energyUnit) {
            Text("Calories (kcal)").tag(EnergyUnit.kcal)
            Text("Kilojoules (kJ)").tag(EnergyUnit.kJ)
        }
    }
}

struct AboutStep: View {
    @Bindable var draft: SetupDraft
    var body: some View {
        StepTitle(title: "About you", subtitle: "Used for your starting expenditure estimate. After a couple of weeks of logging, the app works it out from your own data instead.")
        Picker("Sex", selection: $draft.sex) {
            ForEach(Sex.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        DatePicker("Date of birth", selection: $draft.birthDate, in: ...Date(), displayedComponents: .date)
        HeightField(heightCm: $draft.heightCm, unit: draft.weightUnit)
    }
}

/// Height in cm, or feet and inches when you use pounds.
struct HeightField: View {
    @Binding var heightCm: Double
    let unit: WeightUnit
    @State private var cm = ""
    @State private var feet = ""
    @State private var inches = ""

    var body: some View {
        LabeledContent("Height") {
            HStack {
                if unit == .kg {
                    TextField("", text: $cm, prompt: Text("175")).frame(width: 70)
                    Text("cm").foregroundStyle(.secondary)
                } else {
                    TextField("", text: $feet, prompt: Text("5")).frame(width: 44)
                    Text("ft").foregroundStyle(.secondary)
                    TextField("", text: $inches, prompt: Text("9")).frame(width: 44)
                    Text("in").foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.trailing)
            .labelsHidden()
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
        }
        .onAppear {
            cm = number(heightCm)
            let total = Int((heightCm / 2.54).rounded())
            feet = "\(total / 12)"; inches = "\(total % 12)"
        }
        .onChange(of: cm) { _, v in if unit == .kg, let x = parseNumber(v), (100...250).contains(x) { heightCm = x } }
        .onChange(of: feet) { _, _ in feetChanged() }
        .onChange(of: inches) { _, _ in feetChanged() }
    }

    private func feetChanged() {
        guard unit == .lb, let f = parseNumber(feet) else { return }
        let i = parseNumber(inches) ?? 0
        let total = (f * 12 + i) * 2.54
        if (100...250).contains(total) { heightCm = total }
    }
}

struct WeightStep: View {
    @Bindable var draft: SetupDraft
    @State private var text = ""
    var body: some View {
        StepTitle(title: "Your weight", subtitle: "Today's scale weight. From here on, log it most mornings: the app smooths out the day-to-day swings into a trend.")
        LabeledContent("Weight") {
            HStack {
                TextField("", text: $text, prompt: Text(draft.weightUnit == .kg ? "72,5" : "160"))
                    .multilineTextAlignment(.trailing).frame(width: 90)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Text(draft.weightUnit.rawValue).foregroundStyle(.secondary)
            }
        }
        .onAppear { if let kg = draft.weightKg { text = number(draft.weightUnit.fromKg(kg), digits: 1) } }
        .onChange(of: text) { _, v in
            let kg = parseNumber(v).map(draft.weightUnit.toKg)
            draft.weightKg = kg.flatMap { (25...350).contains($0) ? $0 : nil }
        }
    }
}

struct ActivityStep: View {
    @Bindable var draft: SetupDraft
    var body: some View {
        StepTitle(title: "How active are you?", subtitle: "A typical week, training included. A rough answer is fine: it only sets the starting point.")
        ForEach(Activity.allCases) { a in
            ChoiceRow(title: a.label, detail: a.detail, selected: draft.activity == a) { draft.activity = a }
        }
    }
}

struct GoalStep: View {
    @Bindable var draft: SetupDraft
    var body: some View {
        StepTitle(title: "Your goal", subtitle: "Rates are a share of your body weight per week, so they scale with you.")
        Picker("Goal", selection: $draft.goal) {
            ForEach(GoalType.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .onChange(of: draft.goal) { _, g in draft.ratePercent = g.defaultRate }
        if draft.goal != .maintain {
            ForEach(draft.goal.rates, id: \.self) { r in
                let kg = abs(weeklyChangeKg(goal: draft.goal, ratePercent: r, weightKg: draft.weightKg ?? 70))
                ChoiceRow(title: draft.goal.rateLabel(r),
                          detail: "\(percent(r)) a week · about \(draft.weightUnit.format(kg, digits: 2)) a week",
                          selected: draft.ratePercent == r) { draft.ratePercent = r }
            }
        } else {
            Text("Targets are set to what you burn, so your trend weight stays level.").foregroundStyle(.secondary)
        }
    }
}

struct DietStep: View {
    @Bindable var draft: SetupDraft
    var body: some View {
        StepTitle(title: "Diet and protein", subtitle: "How your calories are split. Protein is set first, then fat and carbs share the rest.")
        ForEach(DietStyle.allCases) { d in
            ChoiceRow(title: d.label, detail: d.detail, selected: draft.diet == d) { draft.diet = d }
        }
        Text("Protein").font(.headline).padding(.top, 8)
        Picker("Protein", selection: $draft.protein) {
            ForEach(ProteinLevel.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        let grams = draft.protein.gramsPerKg * (draft.weightKg ?? 70)
        Text("\(number(draft.protein.gramsPerKg, digits: 1)) g per kg of body weight · about \(number(grams)) g a day")
            .font(.callout).foregroundStyle(.secondary)
    }
}

struct SummaryStep: View {
    var draft: SetupDraft
    var body: some View {
        StepTitle(title: "Your plan", subtitle: "These are starting points. Each week the app checks your intake against your weight trend and adjusts.")
        Card(title: "Estimated expenditure", systemImage: "flame") {
            Text(draft.energyUnit.format(draft.expenditure)).font(.title.bold()).monospacedDigit()
            Text("What you burn in a typical day, from your answers.").font(.callout).foregroundStyle(.secondary)
        }
        Card(title: "Daily targets", systemImage: "target") {
            TargetsGrid(targets: draft.targets, energy: draft.energyUnit)
        }
    }
}

/// Calories big, then protein / fat / carbs in their colours.
struct TargetsGrid: View {
    let targets: Targets
    let energy: EnergyUnit
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(energy.format(targets.kcal)).font(.title.bold()).monospacedDigit()
            HStack(spacing: 24) {
                ForEach([Macro.protein, .fat, .carbs], id: \.self) { m in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(number(m.value(targets))) g").font(.title3.weight(.semibold)).monospacedDigit()
                        Label(m.label, systemImage: "circle.fill").labelStyle(DotLabel(color: m.color))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct DotLabel: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 7, height: 7); configuration.title }
    }
}
