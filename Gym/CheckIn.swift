import SwiftData
import SwiftUI

// The weekly check-in screens. The rules (when it's due, what it suggests) are in Progress.swift.

struct CheckInView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]

    var body: some View {
        let energy = profiles.first?.energy ?? .kcal
        let unit = profiles.first?.weight ?? .kg
        NavigationStack {
            ScrollView {
                if let s = ctx.checkInSummary() {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How your week went").font(.title2.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)], spacing: 12) {
                            tile("Trend weight", unit.format(s.trendKg), s.weekChangeKg.map { "\(signed(unit, $0)) this week" } ?? "")
                            tile("Average intake", s.avgIntake.map { energy.format($0) } ?? "–", "\(s.trackedDays) of 7 days logged")
                            tile("Expenditure", energy.format(s.expenditure), "Was \(energy.format(ctx.targets()?.expenditure ?? s.expenditure))")
                        }
                        if s.trackedDays < 4 {
                            Label("Only \(s.trackedDays) days logged this week, so the estimate barely moved. Logging most days makes check-ins accurate.",
                                  systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
                        }
                        if let p = s.proposed {
                            Text("Targets for the week ahead").font(.title2.bold()).padding(.top, 8)
                            Card(title: "Now → suggested", systemImage: "target") {
                                compare(.calories, s.current, p, energy)
                                compare(.protein, s.current, p, energy)
                                compare(.fat, s.current, p, energy)
                                compare(.carbs, s.current, p, energy)
                            }
                            HStack {
                                Button("Keep current targets") { ctx.finishCheckIn(apply: nil, expenditure: s.expenditure); dismiss() }
                                Spacer()
                                Button("Apply new targets") { ctx.finishCheckIn(apply: p, expenditure: s.expenditure); dismiss() }
                                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                            }
                            .controlSize(.large)
                        } else {
                            Text("You set your own targets, so nothing changes automatically. Adjust them in Strategy if you want.")
                                .foregroundStyle(.secondary)
                            Button("Done") { ctx.finishCheckIn(apply: nil, expenditure: s.expenditure); dismiss() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(pagePadding)
                } else {
                    ContentUnavailableView("Nothing to check in yet", systemImage: "calendar",
                                           description: Text("Log your weight first."))
                }
            }
            .navigationTitle("Weekly check-in")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } } }
        }
        .environment(\.locale, appLocale)       // sheets don't inherit it on the Mac
        #if os(macOS)
        .frame(width: 580, height: 640)
        #endif
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
            .formStyle(.grouped)
            .navigationTitle("Your own targets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(fromMacros < 800) }
            }
        }
        .environment(\.locale, appLocale)       // sheets don't inherit it on the Mac
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
        ctx.activeProgram?.mode = "manual"
        ctx.insert(TargetSet(targets: t, expenditure: exp, reason: "manual"))
        try? ctx.save()
        dismiss()
    }
}
