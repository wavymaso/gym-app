import SwiftData
import SwiftUI

/// The weekly check-in questions: six taps (1–5) and an optional note, under 30 seconds.
struct CheckInQuestionsView: View {
    @Binding var answers: CheckInAnswers

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("How was your week?").font(.title2.bold())
            ForEach(CheckInQuestions.questions, id: \.key) { q in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(q.label).font(.secondaryText.weight(.semibold))
                        Spacer()
                        Text("1 \(q.low) · 5 \(q.high)").font(.fine).foregroundStyle(.secondary)
                    }
                    HStack(spacing: Space.s) {
                        ForEach(1...5, id: \.self) { n in
                            let on = value(q.key) == n
                            Button { set(q.key, n); Haptics.tick() } label: {
                                Text("\(n)").font(.numberSmall).frame(maxWidth: .infinity, minHeight: 36)
                                    .background(on ? AnyShapeStyle(palette.accentFill) : AnyShapeStyle(palette.stroke.opacity(0.35)), in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                                    .foregroundStyle(on ? palette.onAccent : Color.primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(q.label) \(n) of 5")
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
            }
            if answers.hunger >= Int(Evidence.value("checkin.q.hunger.high")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("When are you hungriest?").font(.secondaryText.weight(.semibold))
                    Picker("When are you hungriest?", selection: $answers.hungriest) {
                        Text("Not sure").tag(MealBand?.none)
                        ForEach(MealBand.allCases, id: \.self) { b in Text(b.label).tag(MealBand?.some(b)) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
            }
            TextField("Anything else? (optional)", text: $answers.note, axis: .vertical)
                .lineLimit(1...3).textFieldStyle(.roundedBorder)
        }
    }

    private func value(_ k: String) -> Int {
        switch k { case "hunger": answers.hunger; case "energy": answers.energy; case "sleep": answers.sleep
        case "training": answers.training; case "stress": answers.stress; default: answers.difficulty }
    }
    private func set(_ k: String, _ n: Int) {
        switch k { case "hunger": answers.hunger = n; case "energy": answers.energy = n; case "sleep": answers.sleep = n
        case "training": answers.training = n; case "stress": answers.stress = n; default: answers.difficulty = n }
    }
}

/// What your answers suggest: each a proposal you accept or decline. Nothing changes until you accept.
struct CheckInProposalsView: View {
    @Environment(\.modelContext) private var ctx
    @Binding var answers: CheckInAnswers
    let proposals: [CheckInProposal]
    @State private var breakSheet = false
    @State private var confirmMaintenance = false

    var body: some View {
        if !proposals.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Suggestions from your answers").font(.title3.bold())
                ForEach(proposals) { p in
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text(p.title).font(.cardTitle)
                        Text(p.detail).font(.secondaryText).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if let grade = p.evidence.compactMap({ Evidence.entry($0)?.grade }).first {
                            Text("Evidence: grade \(grade.rawValue)\(grade == .D ? " (a convention, not tested)" : "")").font(.fine).foregroundStyle(.tertiary)
                        }
                        if let d = answers.decisions[p.id] {
                            Label(d ? "Accepted" : "Declined", systemImage: d ? "checkmark.circle.fill" : "xmark.circle").font(.fine.weight(.semibold))
                                .foregroundStyle(d ? palette.good : Color.secondary)
                        } else {
                            HStack {
                                Button("Accept") { accept(p) }.buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent)
                                Button("No thanks") { answers.decisions[p.id] = false; Haptics.tick() }.buttonStyle(.bordered)
                            }
                            .font(.secondaryText.weight(.semibold))
                        }
                    }
                    .padding(Space.l).modifier(CardSurface())
                }
            }
            .sheet(isPresented: $breakSheet) { if let prof = ctx.profile { NavigationStack { DietBreakSheet(profile: prof) }.appStyle() } }
            .confirmationDialog("Start a maintenance phase now?", isPresented: $confirmMaintenance, titleVisibility: .visible) {
                Button("Start maintenance (4 weeks)") { ctx.startMaintenancePhase(); answers.decisions["maintenance"] = true; Haptics.success() }
                Button("Not now", role: .cancel) {}
            } message: { Text("Calories go to your expenditure for 4 weeks; then your planned phases continue.") }
        }
    }

    private func accept(_ p: CheckInProposal) {
        guard let prof = ctx.profile else { return }
        var s = prof.planner
        switch p.kind {
        case .moveCalories: s.hungerBand = answers.hungriest
        case .highVolume: s.highVolume = true
        case .carbsToTraining: s.trainingCarbBoost = true; s.carbs.dayShift = max(s.carbs.dayShift, 0.5)
        case .dietBreak: breakSheet = true; answers.decisions[p.id] = true; return
        case .maintenance: confirmMaintenance = true; return
        }
        prof.planner = s; ctx.commit()
        answers.decisions[p.id] = true; Haptics.success()
    }
}

extension ModelContext {
    /// A maintenance phase now (4 weeks), before the phases you planned.
    func startMaintenancePhase() {
        guard let p = profile else { return }
        p.phases.insert(PhaseStep(goal: GoalType.maintain.rawValue, ratePercent: 0, weeks: 4), at: 0)
        startNextPhase()
    }

    /// The check-in's proposals from these answers (the weeks before and this week's plan adherence included).
    func checkInProposals(_ a: CheckInAnswers) -> [CheckInProposal] {
        guard let p = profile else { return [] }
        return CheckInQuestions.proposals(a, history: checkInAnswers(), onCut: activeProgram?.goalValue == .lose, carbShiftOn: p.planner.trainingCarbBoost,
                                          adherence: weekAdherence().asPlannedShare, inBreak: p.inDietBreak(dayKey()))
    }
}
