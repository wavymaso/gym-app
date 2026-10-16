import SwiftData
import SwiftUI

// The weekly check-in screens. The rules (when it's due, what it suggests) are in Progress.swift.

struct CheckInView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]
    @AppStorage("fastCheckIn") private var fast = false
    @State private var estimates: [String: String] = [:]
    @State private var refresh = 0
    @State private var confirmBig = false

    var body: some View {
        let energy = profiles.first?.energy ?? .kcal
        let unit = profiles.first?.weight ?? .kg
        NavigationStack {
            ScrollView {
                if let s = ctx.checkInSummary() {
                    VStack(alignment: .leading, spacing: 16) {
                        if ctx.phaseDone, let p = profiles.first { phaseCard(p) }
                        if !fast { WeeklyReview().arrive(0) }
                        Text(fast ? "How your week went" : "The numbers").font(.title2.bold()).arrive(1)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)], spacing: 12) {
                            tile("Trend weight", unit.format(s.trendKg), s.weekChangeKg.map { "\(signed(unit, $0)) this week" } ?? "")
                            tile("Average intake", s.avgIntake.map { energy.format($0) } ?? "–", "\(s.trackedDays) of 7 days logged")
                            tile("Expenditure", energy.format(s.expenditure), "Was \(energy.format(ctx.targets()?.expenditure ?? s.expenditure))")
                        }
                        .arrive(2)
                        if !fast { partialModule(energy) }
                        if s.trackedDays < 4 {
                            Label("Only \(s.trackedDays) days logged this week, so the estimate barely moved. Logging most days makes check-ins accurate.",
                                  systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
                        }
                        if let a = ctx.planAdherence() {
                            Label("Meal plan: \(a.followed) of \(a.planned) planned days eaten as planned (context only: it never changes targets by itself).",
                                  systemImage: "calendar.badge.checkmark").font(.callout).foregroundStyle(.secondary).arrive(2)
                        }
                        ShadowEngineCard(liveKcal: s.proposed?.kcal ?? s.current.kcal).arrive(3)
                        if let p = s.proposed {
                            Text("Targets for the week ahead").font(.title2.bold()).padding(.top, 8).arrive(3)
                            Card(title: "Now → suggested", systemImage: "target") {
                                compare(.calories, s.current, p, energy)
                                compare(.protein, s.current, p, energy)
                                compare(.fat, s.current, p, energy)
                                compare(.carbs, s.current, p, energy)
                                Label(s.why(unit, energy), systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                                if ctx.activeProgram?.mode == "collaborative" {
                                    Text("Collaborative: calories follow your expenditure; protein and your carb/fat split stay yours.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            HStack {
                                Button("Keep current targets") { ctx.finishCheckIn(apply: nil, expenditure: s.expenditure); Haptics.success(); dismiss() }
                                Spacer()
                                Button(profiles.first?.shadowMode == true ? "Log it (shadow)" : "Apply new targets") {
                                    if let prof = profiles.first, prof.shadowMode {
                                        prof.shadowEntries += [ShadowEntry(day: dayKey(), currentKcal: s.current.kcal, proposedKcal: p.kcal, rawKcal: s.raw?.kcal ?? p.kcal,
                                                                           expenditure: s.expenditure, weekChangeKg: s.weekChangeKg)]
                                        ctx.finishCheckIn(apply: nil, expenditure: s.expenditure); Haptics.success(); dismiss()
                                    } else if s.needsConfirmation && !confirmBig { confirmBig = true } else { ctx.finishCheckIn(apply: p, expenditure: s.expenditure); Haptics.success(); dismiss() }
                                }
                                .buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent).keyboardShortcut(.defaultAction)
                                .confirmationDialog("Expenditure moved \(energy.format(abs(s.expenditure - s.previousExpenditure))) since last time", isPresented: $confirmBig, titleVisibility: .visible) {
                                    Button("Apply anyway") { ctx.finishCheckIn(apply: p, expenditure: s.expenditure); Haptics.success(); dismiss() }
                                    Button("Keep current targets", role: .cancel) { ctx.finishCheckIn(apply: nil, expenditure: s.expenditure); Haptics.success(); dismiss() }
                                } message: {
                                    Text("Real changes are slow. A jump this big is usually a half-logged day, a missed weigh-in or water. Check last week's log first.")
                                }
                            }
                            .controlSize(.large)
                        } else {
                            Text("You set your own targets, so nothing changes automatically. Adjust them in Strategy if you want.")
                                .foregroundStyle(.secondary)
                            Button("Done") { ctx.finishCheckIn(apply: nil, expenditure: s.expenditure); Haptics.success(); dismiss() }
                                .buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent)
                        }
                    }
                    .padding(pagePadding)
                } else {
                    ContentUnavailableView("Nothing to check in yet", systemImage: "calendar",
                                           description: Text("Log your weight first."))
                }
            }
            .navigationTitle("Weekly check-in")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
                ToolbarItem {
                    Menu {
                        Toggle("Fast check-in (skip coaching)", isOn: $fast)
                    } label: { Label("Options", systemImage: "ellipsis.circle") }
                }
            }
            .id(refresh)
        }
        .appStyle()                             // sheets don't inherit these on the Mac
        #if os(macOS)
        .frame(width: 580, height: 640)
        #endif
    }

    /// The phase reached its end: offer the next one (or maintenance).
    private func phaseCard(_ p: Profile) -> some View {
        let next = p.phases.first ?? PhaseStep(goal: GoalType.maintain.rawValue, ratePercent: 0, weeks: 4)
        return Card(title: "Phase complete", systemImage: "flag.checkered") {
            Text("\(ctx.activeProgram?.goalValue.label ?? "This phase") is done (\(p.phaseEndText(p.weight) ?? "")). Next: \(next.describe(p.weight)).")
                .font(.callout)
            HStack {
                Button("Start it") { ctx.startNextPhase(); refresh += 1 }.buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent)
                Button("Keep going") { p.phaseEnd = ""; ctx.commit(); refresh += 1 }.buttonStyle(.bordered)
            }
            Text("Going from a cut straight into a surplus mostly adds fat back; a few weeks at your new maintenance first settles water, hunger and expenditure.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Coaching: days last week that look half-logged. A guess of the whole day keeps the
    /// expenditure (and next week's targets) honest; leaving them low drags both down.
    @ViewBuilder private func partialModule(_ energy: EnergyUnit) -> some View {
        let today = dayKey()
        let week = (1...7).map { addDays(today, -$0) }.reversed()
        let from = addDays(today, -7)
        let byDay = Dictionary(grouping: ((try? ctx.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.day >= from && $0.day < today }))) ?? []),
                               by: \.day).mapValues { $0.reduce(0) { $0 + $1.nutrients.kcal } }
        let partial = Set(ctx.partialDays)
        // Against that day's own target, so fasting days and refeeds aren't mistaken for gaps.
        let suspect = week.filter { d in
            guard let k = byDay[d] else { return false }
            let t = ctx.dayTargets(on: d)?.kcal ?? 0
            return partial.contains(d) || (t > 0 && k < t * 0.6)
        }
        if !suspect.isEmpty {
            Card(title: "Coach: any days half-logged?", systemImage: "questionmark.bubble") {
                Text("These look light next to your usual day. If you ate more than you logged, guess the whole day: a rough number beats a low one, which would pull your expenditure and targets down.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(suspect, id: \.self) { d in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(date(fromKey: d).formatted(.dateTime.weekday(.wide).day().locale(appLocale)))
                            Text("\(energy.format(byDay[d] ?? 0)) logged\(partial.contains(d) ? " · marked partial" : "")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        TextField("Whole day", text: Binding(get: { estimates[d] ?? "" }, set: { estimates[d] = $0 }))
                            .multilineTextAlignment(.trailing).frame(width: 90).textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        Button("Fix") {
                            if let v = parseNumber(estimates[d] ?? ""), v > 0 { ctx.estimateDay(d, totalKcal: v); estimates[d] = nil; refresh += 1 }
                        }
                        .buttonStyle(.bordered).disabled((parseNumber(estimates[d] ?? "") ?? 0) <= (byDay[d] ?? 0))
                    }
                }
                Text("They were fine? Ignore this, or turn on Fast check-in (⋯) to skip coaching.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func tile(_ title: String, _ value: String, _ note: String) -> some View {
        Card(title: title) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(note).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func compare(_ m: Macro, _ a: Targets, _ b: Targets, _ energy: EnergyUnit) -> some View {
        let fmt: (Double) -> String = { m == .calories ? energy.format($0) : "\(number($0)) g" }
        let diff = m.value(b) - m.value(a)
        return HStack {
            Label(m.label, systemImage: "circle.fill").labelStyle(DotLabel(color: m.color))
            Spacer()
            Text(fmt(m.value(a))).foregroundStyle(.secondary).monospacedDigit()
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
            Text(fmt(m.value(b))).fontWeight(.semibold).monospacedDigit()
            Text(abs(diff) < 1 ? "" : (diff > 0 ? "+" : "−") + number(abs(m == .calories ? energy.fromKcal(diff) : diff)))
                .font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
        }
    }
}

/// Your own targets, instead of coached ones.
struct ManualTargetsView: View {
    var mode = "manual"                      // or "collaborative": your macros, the app's calories
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var kcal = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var carbs = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("Protein", $protein, "g")
                    field("Fat", $fat, "g")
                    field("Carbs", $carbs, "g")
                } footer: {
                    Text("Calories from these: \(number(fromMacros)) kcal")
                }
            }
            .themedForm()
            .navigationTitle("Your own targets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(fromMacros < 800) }
            }
        }
        .appStyle()                             // sheets don't inherit these on the Mac
        #if os(macOS)
        .frame(width: 420, height: 320)
        #endif
        .onAppear {
            if let t = ctx.targets() { protein = number(t.protein); fat = number(t.fat); carbs = number(t.carbs) }
        }
    }

    private var fromMacros: Double {
        (parseNumber(protein) ?? 0) * 4 + (parseNumber(fat) ?? 0) * 9 + (parseNumber(carbs) ?? 0) * 4
    }

    private func field(_ label: String, _ text: Binding<String>, _ unit: String) -> some View {
        LabeledContent(label) {
            HStack { TextField("", text: text).multilineTextAlignment(.trailing).frame(width: 80); Text(unit).foregroundStyle(.secondary) }
        }
    }

    private func save() {
        let t = Targets(kcal: roundTo(fromMacros, 10), protein: parseNumber(protein) ?? 0, fat: parseNumber(fat) ?? 0, carbs: parseNumber(carbs) ?? 0)
        let exp = ctx.expenditureEstimates().last?.kcal ?? ctx.targets()?.expenditure ?? t.kcal
        ctx.activeProgram?.mode = mode
        ctx.insert(TargetSet(targets: t, expenditure: exp, reason: "manual"))
        ctx.commit()
        dismiss()
    }
}
