import SwiftData
import SwiftUI

/// "Why?": a decision opened up: what went in, the rules that fired, and the evidence behind them.
struct WhyView: View {
    let record: CheckInRecord
    var liveKcal: Double? = nil

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(headline).font(.cardTitle)
                    if let live = liveKcal, live != record.output.kcal {
                        Text("Shadow mode: the current coaching set \(number(live)) kcal; this is what the new engine would do.")
                            .font(.secondaryText).foregroundStyle(.secondary)
                    }
                }
            }
            Section("What went in") {
                row("Trend weight", "\(number(record.input.trendKg, digits: 1)) ± \(number(record.input.trendSD, digits: 1)) kg")
                row("Rate", "\(signedKg(record.input.observedRateKgWeek)) kg/week (goal \(record.input.phase) \(number(record.input.targetRatePct, digits: 2))%)")
                row("Expenditure", "\(number(record.input.expenditure)) ± \(number(record.input.expenditureSD)) kcal")
                row("Logged", "\(record.input.loggedDays) of 7 days · \(record.input.weighIns) weigh-ins")
                if let a = record.input.avgIntake { row("Average intake", "\(number(a)) kcal") }
                row("Phase", "\(record.input.phase.capitalized), week \(record.input.weeksInPhase + 1)")
            }
            Section("What it decided") {
                row("Calories", "\(number(record.input.currentTargets.kcal)) → \(number(record.output.kcal))")
                row("Protein", "\(number(record.output.protein)) g")
                row("Fat", "\(number(record.output.fat)) g")
                row("Carbs", "\(number(record.output.carbs)) g")
                if let raw = record.raw { row("The numbers alone said", "\(number(raw.kcal)) kcal").foregroundStyle(.secondary) }
            }
            Section("Why") {
                ForEach(Array(record.reasons.enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(r.rule.capitalized).font(.secondaryText.weight(.semibold))
                        Text(r.detail).font(.secondaryText).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Section("Evidence") {
                ForEach(record.evidence, id: \.self) { id in
                    if let e = Evidence.entry(id) { EvidenceRow(entry: e) }
                }
            }
        }
        .themedList()
        .navigationTitle("Why")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var headline: String {
        switch record.action {
        case "no change": return "No change this week"
        case "proposed": return "Proposed: \(number(record.output.kcal)) kcal"
        case "reported": return "Manual program: reported only"
        default: return "\(record.output.kcal > record.input.currentTargets.kcal ? "Up" : "Down") to \(number(record.output.kcal)) kcal"
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundStyle(.secondary).monospacedDigit().multilineTextAlignment(.trailing) }
    }
    private func signedKg(_ v: Double) -> String { (v > 0 ? "+" : v < 0 ? "−" : "") + number(abs(v), digits: 2) }
}

struct EvidenceRow: View {
    let entry: EvidenceEntry
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(entry.description).font(.secondaryText).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(entry.grade.rawValue).font(.label).padding(.horizontal, Space.s).padding(.vertical, Space.xxs)
                    .background(Color.raisedBackground, in: Capsule())
                    .accessibilityLabel("Evidence grade \(entry.grade.rawValue)")
            }
            ForEach(entry.sources, id: \.citation) { s in
                if s.link.hasPrefix("https"), let u = URL(string: s.link) { Link(s.citation, destination: u).font(.fine) }
                else { Text(s.citation).font(.fine).foregroundStyle(.secondary) }
            }
            if !entry.population.isEmpty, entry.population != "—" { Text("Studied in: \(entry.population)").font(.fine).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, Space.xxs)
    }
}

/// All past engine decisions, newest first.
struct DecisionHistoryView: View {
    @Query(sort: \DecisionRecord.day, order: .reverse) private var records: [DecisionRecord]
    var body: some View {
        List {
            if records.isEmpty {
                Text("Each weekly check-in's decision appears here, with everything behind it.").foregroundStyle(.secondary)
            }
            ForEach(records) { r in
                if let rec = r.record {
                    NavigationLink { WhyView(record: rec) } label: {
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(date(fromKey: r.day).formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(appLocale)))
                            Text("\(rec.action.capitalized) · \(number(rec.input.currentTargets.kcal)) → \(number(rec.output.kcal)) kcal\(r.live ? "" : " · shadow")")
                                .font(.note).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .themedList()
        .navigationTitle("Coaching decisions")
    }
}

/// On the check-in: the new engine's view of the same week (shadow), with Why.
struct ShadowEngineCard: View {
    @Environment(\.modelContext) private var ctx
    let liveKcal: Double?
    @State private var record: CheckInRecord?

    var body: some View {
        Group {
            if let r = record {
                NavigationLink { WhyView(record: r, liveKcal: liveKcal) } label: {
                    HStack(spacing: Space.m) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text("New coaching engine (preview)").font(.label).foregroundStyle(.secondary).textCase(.uppercase)
                            Text(r.action == "no change" ? "Would keep \(number(r.output.kcal)) kcal" : "Would set \(number(r.output.kcal)) kcal")
                                .font(.cardTitle)
                            Text(r.reasons.last?.detail ?? "").font(.secondaryText).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Text("Why?").font(.secondaryText.weight(.semibold)).foregroundStyle(palette.accent)
                    }
                    .padding(Space.l).modifier(CardSurface())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(height: 1)            // something to attach the loading to
            }
        }
        .task { record = ctx.engineCheckIn() }
    }
}

/// The whole registry, grouped by grade.
struct EvidenceListView: View {
    var body: some View {
        List {
            Section { Text("A: meta-analysis or several trials · B: a single trial or strong study · C: expert consensus or review · D: convention, a fit to your data, or your choice.").font(.note).foregroundStyle(.secondary) }
            ForEach(["A", "B", "C", "D"], id: \.self) { g in
                Section("Grade \(g)") {
                    ForEach(Evidence.all.filter { $0.grade.rawValue == g }) { EvidenceRow(entry: $0) }
                }
            }
        }
        .themedList()
        .navigationTitle("Evidence")
    }
}


/// Maintenance as a recomp: the engine's honest advice, then your choice.
struct RecompPage: View {
    @Environment(\.modelContext) private var ctx
    @Bindable var profile: Profile
    var body: some View {
        Form {
            Section {
                Toggle("Run maintenance as a recomp", isOn: Binding(get: { profile.recomp }, set: { profile.recomp = $0; ctx.commit() }))
            } footer: {
                Text("Calories stay at maintenance; protein moves to the higher, cut-level amount; the trend should hold steady while strength and measurements improve.")
            }
            if let person = ctx.enginePerson {
                Section("Is it a good idea for you?") {
                    Text(EngineTargets.recompAdvice(person, body: ctx.engineBody).detail)
                    if let e = Evidence.entry("recomp.whenSuitable") { EvidenceRow(entry: e) }
                }
            }
        }
        .themedForm()
        .navigationTitle("Recomposition")
    }
}
