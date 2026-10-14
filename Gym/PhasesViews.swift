import SwiftData
import SwiftUI

/// Your scales: name the others; their offsets from the main one are worked out from your weigh-ins.
struct ScalesSheet: View {
    let profile: Profile
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var offsets: [String: Double] = [:]
    @State private var newName = ""

    var body: some View {
        let unit = profile.weight
        let estimated = ctx.estimatedScaleOffsets()
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Main scale", value: "reference")
                    ForEach(offsets.keys.sorted(), id: \.self) { name in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(name).font(.headline)
                                Spacer()
                                Stepper("\(offsets[name]! >= 0 ? "+" : "−")\(number(abs(unit.fromKg(offsets[name]!)), digits: 1)) \(unit.rawValue)",
                                        value: Binding(get: { unit.fromKg(offsets[name] ?? 0) }, set: { offsets[name] = unit.toKg($0) }), in: -5...5, step: 0.1)
                                    .fixedSize()
                            }
                            if let e = estimated[name] {
                                Button("Use what your weigh-ins say: \(e >= 0 ? "+" : "−")\(number(abs(unit.fromKg(e)), digits: 2)) \(unit.rawValue)") { offsets[name] = e }
                                    .font(.caption)
                            } else {
                                Text("After 3 weigh-ins on it the app can work out its offset.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { idx in let keys = offsets.keys.sorted(); for i in idx { offsets[keys[i]] = nil } }
                    HStack {
                        TextField("Another scale (Madrid, gym…)", text: $newName)
                        Button("Add") { offsets[newName.trimmingCharacters(in: .whitespaces)] = 0; newName = "" }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || newName.contains("=") || newName.contains(";"))
                    }
                } footer: {
                    Text("Two scales rarely agree: 0,5–1 kg apart is normal. Tag each weigh-in with its scale (the picker appears when you weigh in) and the trend adds each one's offset, so a trip home doesn't look like a real jump.")
                }
            }
            .themedForm()
            .navigationTitle("Scales")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { profile.scaleOffsetMap = offsets; ctx.commit(); dismiss() } }
            }
        }
        .appStyle()
        .onAppear { offsets = profile.scaleOffsetMap }
    }
}

/// Plan the phases: when this one ends, and what comes next.
struct PhasePlanSheet: View {
    let profile: Profile
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var endKind = 0                 // 0 none, 1 date, 2 weight
    @State private var endDate = Date().addingTimeInterval(86400 * 56)
    @State private var endKg = ""
    @State private var queue: [PhaseStep] = []
    @State private var adding = PhaseStep(goal: GoalType.maintain.rawValue, ratePercent: 0, weeks: 4)
    @State private var addUntilWeight = false
    @State private var addKg = ""

    var body: some View {
        let unit = profile.weight
        NavigationStack {
            Form {
                Section {
                    Picker("Ends", selection: $endKind) { Text("No end").tag(0); Text("On a date").tag(1); Text("At a weight").tag(2) }
                        .pickerStyle(.segmented)
                    if endKind == 1 { DatePicker("Date", selection: $endDate, in: Date()..., displayedComponents: .date) }
                    if endKind == 2 {
                        HStack { TextField("Trend weight", text: $endKg); Text(unit.rawValue).foregroundStyle(.secondary) }
                    }
                } header: { Text("This phase · \(ctx.activeProgram?.goalValue.label ?? "")") }
                Section {
                    if queue.isEmpty { Text("Nothing planned: when this phase ends you'll be offered 4 weeks at maintenance.").foregroundStyle(.secondary) }
                    ForEach(Array(queue.enumerated()), id: \.element.id) { i, s in
                        Label(s.describe(unit), systemImage: "\(i + 1).circle.fill")
                    }
                    .onDelete { queue.remove(atOffsets: $0) }
                    .onMove { queue.move(fromOffsets: $0, toOffset: $1) }
                } header: { Text("Then") }
                Section {
                    Picker("Goal", selection: $adding.goal) { ForEach(GoalType.allCases) { Text($0.label).tag($0.rawValue) } }
                        .onChange(of: adding.goal) { _, g in adding.ratePercent = GoalType(rawValue: g)?.rates.dropFirst().first ?? 0 }
                    if adding.goalValue != .maintain {
                        Picker("Rate", selection: $adding.ratePercent) {
                            ForEach(adding.goalValue.rates, id: \.self) { r in Text("\(number(r, digits: 2))% a week · \(adding.goalValue.rateLabel(r))").tag(r) }
                        }
                    }
                    Toggle("Until a weight", isOn: $addUntilWeight)
                    if addUntilWeight { HStack { TextField("Trend weight", text: $addKg); Text(unit.rawValue).foregroundStyle(.secondary) } }
                    else { Stepper("For \(adding.weeks) week\(adding.weeks == 1 ? "" : "s")", value: $adding.weeks, in: 1...52) }
                    Button("Add to the plan") {
                        var s = adding; s.id = UUID()
                        if addUntilWeight { s.untilKg = parseNumber(addKg).map(unit.toKg); s.weeks = 0 }
                        queue.append(s)
                    }
                    .disabled(addUntilWeight && parseNumber(addKg) == nil)
                } header: { Text("Add a phase") } footer: {
                    Text("Sensible for a natural lifter: cut 0,5–1% a week, then a few weeks at maintenance before bulking at about 0,5–1% a month (0,1–0,25% a week). When a phase ends, the check-in offers the next one.")
                }
            }
            .themedForm()
            .navigationTitle("Phase plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
        .appStyle()
        .onAppear(perform: load)
    }

    private func load() {
        queue = profile.phases
        if profile.phaseEnd.hasPrefix("day:") { endKind = 1; endDate = date(fromKey: String(profile.phaseEnd.dropFirst(4))) }
        if profile.phaseEnd.hasPrefix("kg:"), let kg = Double(profile.phaseEnd.dropFirst(3)) { endKind = 2; endKg = number(profile.weight.fromKg(kg), digits: 1) }
    }

    private func save() {
        switch endKind {
        case 1: profile.phaseEnd = "day:\(dayKey(endDate))"
        case 2: profile.phaseEnd = parseNumber(endKg).map { "kg:\(profile.weight.toKg($0))" } ?? ""
        default: profile.phaseEnd = ""
        }
        profile.phases = queue
        ctx.commit()
        dismiss()
    }
}

/// Shadow mode: the coach calculates each check-in but leaves your targets alone; compare it with
/// your own judgement before you trust it. And a replay of what it would have said lately.
struct ShadowSheet: View {
    let profile: Profile
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var replay: [ShadowEntry] = []
    @State private var loading = false

    var body: some View {
        let energy = profile.energy, unit = profile.weight
        NavigationStack {
            List {
                Section {
                    Toggle("Shadow mode", isOn: Binding(get: { profile.shadowMode }, set: { profile.shadowMode = $0; ctx.commit() }))
                } footer: {
                    Text("Check-ins still run and show what they'd change, but your targets stay as they are; each one is logged here. Turn it off once you trust it.")
                }
                if !profile.shadowEntries.isEmpty {
                    Section("Logged check-ins") { ForEach(profile.shadowEntries.reversed()) { row($0, energy, unit) } }
                }
                Section {
                    if loading { ProgressView() }
                    ForEach(replay) { row($0, energy, unit) }
                    if replay.isEmpty && !loading {
                        Button("Replay the last 12 weeks") {
                            loading = true
                            DispatchQueue.main.async { replay = ctx.replayCheckIns(weeks: 12); loading = false }
                        }
                    }
                } header: { Text("Replay") } footer: {
                    Text("What the coach would have set at each check-in day, from the data as it stood then. Targets: what you had; Coach: its smoothed suggestion (the raw number in brackets).")
                }
            }
            .themedList()
            .navigationTitle("Shadow coach")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .appStyle()
        #if os(macOS)
        .frame(width: 520, height: 620)
        #endif
    }

    private func row(_ e: ShadowEntry, _ energy: EnergyUnit, _ unit: WeightUnit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(date(fromKey: e.day).formatted(.dateTime.day().month(.abbreviated).locale(appLocale))).font(.headline)
                Spacer()
                if let w = e.weekChangeKg { Text("\(signed(unit, w))/wk").font(.caption).foregroundStyle(.secondary) }
            }
            HStack(spacing: 14) {
                Text("Targets \(energy.format(e.currentKcal))")
                let d = e.proposedKcal - e.currentKcal
                Text("Coach \(energy.format(e.proposedKcal))").fontWeight(.semibold)
                    .foregroundStyle(abs(d) < 10 ? Color.primary : d > 0 ? palette.good : palette.warn)
                Text("(\(energy.format(e.rawKcal)))").foregroundStyle(.secondary)
            }
            .font(.callout).monospacedDigit()
            Text("Expenditure \(energy.format(e.expenditure))").font(.caption).foregroundStyle(.secondary)
        }
    }
}
