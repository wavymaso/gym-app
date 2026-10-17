import Foundation
import SwiftData
import SwiftUI

// The day-by-day coach (phase 4). It builds a CoachSnapshot from the engine and your logs, decides
// whether there's anything worth saying (quiet by default), asks the model with the snapshot only,
// validates the reply against the snapshot, regenerates once, and otherwise uses the template.

extension ModelContext {
    func coachSnapshot(_ moment: CoachSnapshot.Moment) -> CoachSnapshot? {
        guard let p = profile, let g = activeProgram, let t = dayTargets(on: dayKey()) else { return nil }
        let today = dayKey()
        let eaten = entries(on: today).reduce(Nutrients.zero) { $0 + $1.nutrients }
        let hour = Calendar.current.component(.hour, from: Date())
        let mealsLeft = [11, 15, 21].filter { hour < $0 }.count
        var special: [String] = []
        let wd = Calendar(identifier: .gregorian).component(.weekday, from: Date())
        if p.highDaySet.contains(wd) { special.append("training day") }
        if p.fastDaySet.contains(wd) { special.append("fasting day") }
        if p.refeedWeekday == wd { special.append("refeed day") }
        if p.inDietBreak(today) { special.append("diet break") }
        if ramadanActive { special.append("Ramadan: iftar to suhoor counts as one day") }
        let snap = engineSnapshot()
        let tr = snap?.trend.last, ex = snap?.expenditure.last
        let rec = ((try? fetch(FetchDescriptor<DecisionRecord>(sortBy: [SortDescriptor(\.day, order: .reverse)]))) ?? []).first?.record
        let engineRec = rec ?? (moment == .checkIn ? engineCheckIn() : nil)
        let phase = g.goalValue == .lose ? "cut" : g.goalValue == .gain ? "bulk" : (p.recomp ? "recomp" : "maintain")
        let days7 = snap?.days.suffix(8).dropLast() ?? []
        // Very low intake: logged days in the last two weeks under 60% of the floor.
        let floor = snap.map { EngineTargets.floor($0.person, weight: tr?.trend ?? 75, body: $0.body).kcal } ?? 1500
        let low = (snap?.days.suffix(15).dropLast() ?? []).compactMap(\.intake).filter { $0 < floor * 0.6 }.count
        let notes = ((try? fetch(FetchDescriptor<DayNote>())) ?? []).filter { $0.day >= addDays(today, -7) }.map(\.text).joined(separator: " ").lowercased()
        let distress = ["hate myself", "can't stop", "binge", "purg", "starv", "disgusting", "worthless"].contains { notes.contains($0) }
        // Your own frequent high-protein foods.
        let foods = ((try? fetch(FetchDescriptor<Food>(predicate: #Predicate { $0.useCount > 2 }))) ?? [])
            .filter { $0.per100.protein >= 15 }.sorted { $0.useCount > $1.useCount }.prefix(3).map(\.name)
        let w = ((try? fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.end != nil }, sortBy: [SortDescriptor(\.start, order: .reverse)]))) ?? []).first
        var workout: CoachSnapshot.Workout?
        if let w, let end = w.end, Date().timeIntervalSince(end) < 6 * 3600 {
            let key = w.key
            let sets = ((try? fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.workoutKey == key && $0.done }))) ?? [])
            workout = .init(name: w.name, sets: sets.count, prs: 0, volumeChangePct: nil)
        }
        let flags = rec?.reasons.filter { ["strength drop on a fast cut", "fast gain, flat strength", "diet break", "short sleep"].contains($0.rule) }.map(\.detail) ?? []
        let used = Set((engineRec?.evidence ?? []) + ["protein.daily.gPerKg"])
        return CoachSnapshot(
            moment: moment, date: today, weekday: Date().formatted(.dateTime.weekday(.wide).locale(appLocale)), phase: phase,
            phaseWeek: daysBetween(g.startDay, today) / 7 + 1,
            today: .init(kcalTarget: Int(t.kcal.rounded()), kcalEaten: Int(eaten.kcal.rounded()), kcalLeft: Int((t.kcal - eaten.kcal).rounded()),
                         proteinTarget: Int(t.protein.rounded()), proteinEaten: Int(eaten.protein.rounded()), proteinLeft: Int((t.protein - eaten.protein).rounded()),
                         mealsLeftToday: mealsLeft, special: special),
            trend: .init(kg: ((tr?.trend ?? 0) * 10).rounded() / 10, ratePerWeek: ((tr?.ratePerWeek ?? 0) * 100).rounded() / 100, sd: ((tr?.sd ?? 0) * 10).rounded() / 10,
                         goalRatePerWeek: (weeklyChangeKg(goal: g.goalValue, ratePercent: g.ratePercent, weightKg: tr?.trend ?? 75) * 100).rounded() / 100),
            expenditure: .init(kcal: Int(ex?.kcal ?? 0), sd: Int(ex?.sd ?? 0), settling: (ex?.sd ?? 999) > 150),
            loggedDaysLast7: days7.compactMap(\.intake).count, weighInsLast7: days7.filter { !$0.weighIns.isEmpty }.count,
            checkIn: .init(due: dueCheckIn != nil, daysUntil: dueCheckIn != nil ? 0 : daysUntilCheckIn(g), lastAction: engineRec?.action,
                           lastFrom: engineRec.map { Int($0.input.currentTargets.kcal) }, lastTo: engineRec.map { Int($0.output.kcal) },
                           lastReason: engineRec?.reasons.last?.detail),
            lastWorkout: workout, flags: flags,
            waterEvent: snap?.days.suffix(3).first(where: { !$0.events.isEmpty })?.events.first.map { $0 == .tagged ? "salty day or travel" : $0.rawValue },
            frequentProteinFoods: Array(foods), safety: .init(veryLowIntakeDays: low, distressInNotes: distress),
            nextMeal: nextPlannedMeal(),
            evidence: used.sorted().compactMap { Evidence.entry($0) }.map { .init(id: $0.id, text: $0.description, grade: $0.grade.rawValue) })
    }

    /// The meal planner's next meal today that isn't eaten yet.
    func nextPlannedMeal() -> CoachSnapshot.PlannedMeal? {
        guard let r = dayPlan(dayKey()) else { return nil }
        let now = Calendar.current.component(.hour, from: Date()) * 60 + Calendar.current.component(.minute, from: Date())
        guard let s = r.plan.slots.first(where: { !$0.eaten && $0.minute >= now - 30 }) else { return nil }
        let m = s.items.reduce(Macros()) { $0 + (r.foods[$1.key]?.macros($1.grams) ?? Macros()) }
        let kind = ["meal": "meal", "preWorkout": "pre-workout meal", "postWorkout": "post-workout meal", "preSleep": "pre-bed meal"][s.kind.rawValue] ?? "meal"
        return .init(time: String(format: "%02d:%02d", (s.minute / 60) % 24, s.minute % 60), kind: kind,
                     foods: s.items.compactMap { r.foods[$0.key]?.name }, kcal: Int(m.kcal.rounded()), protein: Int(m.protein.rounded()))
    }

    private func daysUntilCheckIn(_ g: Program) -> Int {
        var d = addDays(dayKey(), 1), n = 1
        while Calendar(identifier: .gregorian).component(.weekday, from: date(fromKey: d)) != g.checkInWeekday && n < 7 { d = addDays(d, 1); n += 1 }
        return n
    }
}

struct CoachEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var day: String
    var moment: CoachSnapshot.Moment
    var message: CoachMessage
}

@MainActor final class Coach: ObservableObject {
    static let shared = Coach()
    @Published private(set) var entries: [CoachEntry] = {
        guard UserDefaults.standard.integer(forKey: "coachNoteVersion") >= 3 else {
            UserDefaults.standard.removeObject(forKey: "coachEntries"); UserDefaults.standard.removeObject(forKey: "coachNote")
            UserDefaults.standard.set(3, forKey: "coachNoteVersion"); return []
        }
        return UserDefaults.standard.data(forKey: "coachEntries").flatMap { try? JSONDecoder().decode([CoachEntry].self, from: $0) } ?? []
    }()
    @Published private(set) var working = false

    var today: [CoachEntry] { entries.filter { $0.day == dayKey() } }
    static var maxPerDay: Int { max(1, UserDefaults.standard.object(forKey: "coachMaxPerDay") as? Int ?? 2) }
    static var allowGemini: Bool { UserDefaults.standard.bool(forKey: "coachAllowGemini") }

    /// Speak if there's something worth saying now (or `force` a morning brief).
    func refresh(_ ctx: ModelContext, force: Bool = false) async {
        guard !working else { return }
        let done = Set(today.map(\.moment))
        guard let probe = ctx.coachSnapshot(.morning) else { return }
        let justTrained = probe.lastWorkout != nil
        var moment = CoachSchedule.moment(hour: Calendar.current.component(.hour, from: Date()), alreadyToday: done, max: Coach.maxPerDay,
                                          s: probe, justTrained: justTrained, recentWaterJump: probe.waterEvent != nil)
        if moment == nil, force { moment = .morning }
        guard let m = moment, let snap = ctx.coachSnapshot(m) else { return }
        working = true
        defer { working = false }
        let msg = await Coach.write(snap)
        entries.append(CoachEntry(day: dayKey(), moment: m, message: msg))
        entries = entries.filter { $0.day >= addDays(dayKey(), -14) }
        if let d = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(d, forKey: "coachEntries") }
    }

    /// The model, validated; one retry with the problems listed; then the template.
    static func write(_ s: CoachSnapshot) async -> CoachMessage {
        if s.safety.stepBack { return CoachTemplates.message(s) }      // never left to a model
        var prompt = CoachPrompt.make(s)
        for _ in 0..<2 {
            guard let r = try? await PhotoAI.askCoach(prompt, allowGemini: allowGemini), var m = CoachValidator.parse(r.text) else { break }
            let problems = CoachValidator.check(m, s)
            if problems.isEmpty { m.source = r.by; return m }
            Log.ai.notice("Coach message rejected: \(problems.map(\.kind).joined(separator: ", "), privacy: .public)")
            prompt += "\n\nYour previous reply was rejected: " + problems.map { "\($0.kind) (\($0.detail))" }.joined(separator: "; ") + ". Fix it."
        }
        return CoachTemplates.message(s)
    }
}

/// The coach card on Strategy (and the dashboard): today's messages, newest first.
struct CoachCard: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.openPage) private var openPage
    @ObservedObject private var coach = Coach.shared
    @State private var checkingIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Label("Coach", systemImage: "figure.strengthtraining.traditional").font(.cardTitle)
                Spacer()
                if coach.working { ProgressView().controlSize(.small) }
                else {
                    Button { Task { await coach.refresh(ctx, force: true) } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
                        .accessibilityLabel("Ask the coach")
                }
            }
            if coach.today.isEmpty {
                Text(coach.working ? "Reading today…" : "Nothing to flag right now.").font(.secondaryText).foregroundStyle(.secondary)
            }
            ForEach(coach.today.reversed()) { e in
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(e.message.headline).font(.secondaryEmphasis)
                    Text(e.message.body).font(.secondaryText).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let a = e.message.action, a.kind == .openCheckIn || a.kind == .openProposal {
                        Button(a.label.isEmpty ? "Open check-in" : a.label) { checkingIn = true }.font(.secondaryEmphasis)
                    }
                    Text(e.message.source == "template" ? "From the app's rules" : "Written by \(e.message.source), checked against your numbers")
                        .font(.fine).foregroundStyle(.tertiary)
                }
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .padding(Space.l)
        .modifier(CardSurface())
        .animation(Motion.pick(Motion.smooth), value: coach.entries)
        .task { await coach.refresh(ctx) }
        .sheet(isPresented: $checkingIn) { CheckInView() }
    }
}

/// Settings → Coach.
struct CoachSettings: View {
    @AppStorage("coachMaxPerDay") private var maxPerDay = 2
    @AppStorage("coachAllowGemini") private var allowGemini = false
    var body: some View {
        Section {
            Stepper("At most \(maxPerDay) message\(maxPerDay == 1 ? "" : "s") a day", value: $maxPerDay, in: 1...4)
            Toggle("Use Gemini when the Mac can't answer", isOn: $allowGemini)
        } footer: {
            Text("The coach speaks only when there's something useful: a morning brief, a protein nudge late in the day, after a workout, on check-in day, or when the scale jumps from water. It only sees a summary of the engine's numbers (never photos or your food log), may only repeat numbers from that summary, and can't change targets. Anything it writes that breaks these rules is replaced by the app's own message.")
        }
    }
}
