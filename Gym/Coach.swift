import Foundation
import SwiftData
import SwiftUI

// Today's coaching note on the Strategy tab: your last two weeks summed up, read by the AI
// (your Mac's model or Gemini), turned into a few lines on what to do today. Made once a day;
// without an AI it falls back to the app's own rules.

struct CoachNote: Codable, Equatable {
    var day: String
    var text: String
    var by: String
}

extension ModelContext {
    /// The facts the coach works from, as short plain lines.
    func coachFacts() -> String {
        guard let p = profile else { return "" }
        let unit = p.weight, today = dayKey()
        var lines: [String] = []
        let g = activeProgram
        let trend = trendSeries(weightValues, through: today)
        if let t = trend.last?.trend {
            lines.append("Trend weight \(unit.format(t)); goal \(g?.goalValue.label ?? "none") at \(number(g?.ratePercent ?? 0, digits: 2))% a week" +
                         (p.goalWeightKg.map { ", target \(unit.format($0))" } ?? ""))
        }
        if let w7 = weeklyTrendChange(trend, days: 7), let w21 = weeklyTrendChange(trend, days: 21) {
            let goal = g.map { weeklyChangeKg(goal: $0.goalValue, ratePercent: $0.ratePercent, weightKg: trend.last?.trend ?? 80) } ?? 0
            lines.append("Rate: \(signed(unit, w7)) last week, \(signed(unit, w21)) a week over 3 weeks; goal \(signed(unit, goal)) a week")
        }
        let intake = dailyIntake()
        let week = (1...7).map { addDays(today, -$0) }
        let logged = week.compactMap { intake[$0] }
        if let t = dayTargets(on: today) {
            lines.append("Today's targets: \(Int(t.kcal)) kcal, protein \(Int(t.protein)) g, fat \(Int(t.fat)) g, carbs \(Int(t.carbs)) g")
        }
        if !logged.isEmpty {
            let avg = logged.reduce(0, +) / Double(logged.count)
            let tgt = week.compactMap { dayTargets(on: $0)?.kcal }.reduce(0, +) / 7
            let prot = week.map { d in entries(on: d).reduce(0) { $0 + $1.nutrients.protein } }
            let pt = dayTargets(on: today)?.protein ?? 1
            lines.append("Last 7 days: \(logged.count)/7 logged, average \(Int(avg)) kcal vs target \(Int(tgt)), protein target hit \(prot.filter { $0 >= pt * 0.9 }.count)/7 days")
        }
        let eatenToday = entries(on: today).reduce(Nutrients.zero) { $0 + $1.nutrients }
        let hour = Calendar.current.component(.hour, from: Date())
        lines.append("So far today (\(hour):00): \(Int(eatenToday.kcal)) kcal, \(Int(eatenToday.protein)) g protein")
        if let e = expenditureEstimates().last { lines.append("Expenditure estimate \(Int(e.kcal)) kcal") }
        let from = addDays(today, -7)
        let sets = (try? fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.day >= from && $0.done }))) ?? []
        let sessions = Set(sets.map(\.day)).count
        lines.append("Training: \(sessions) sessions in 7 days" + (Set(sets.map(\.day)).contains(today) ? ", trained today" : ""))
        let counts = setsPerMuscle(sets.compactMap { s in exercise(s.exerciseKey).map { ($0.muscleValue, $0.secondaryValues, s.kindValue) } })
        let low = Muscle.allCases.filter { m in m != .cardio && m != .fullBody && volumeRange(m).lowerBound > 0 && (counts[m] ?? 0) < volumeRange(m).lowerBound }
        if sessions > 0, !low.isEmpty { lines.append("Below weekly volume: \(low.map(\.label).joined(separator: ", "))") }
        let acts = (try? fetch(FetchDescriptor<DailyActivity>(predicate: #Predicate { $0.day >= from }))) ?? []
        let sl = acts.map(\.sleepHours).filter { $0 > 1 }
        if !sl.isEmpty { lines.append("Sleep \(number(sl.reduce(0, +) / Double(sl.count), digits: 1)) h a night") }
        let steps = acts.map(\.steps).filter { $0 > 0 }
        if !steps.isEmpty { lines.append("Steps \(steps.reduce(0, +) / steps.count) a day") }
        if p.inDietBreak(today) { lines.append("On a diet break (maintenance)") }
        if p.refeedWeekday > 0, Calendar(identifier: .gregorian).component(.weekday, from: Date()) == p.refeedWeekday { lines.append("Today is the refeed day") }
        if dueCheckIn != nil { lines.append("Weekly check-in is due today") }
        lines.append("Weekday: \(Date().formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "en_GB"))))")
        return lines.joined(separator: "\n")
    }

    /// Without an AI: the same idea from fixed rules.
    func ruleNote() -> String {
        guard let t = dayTargets(on: dayKey()) else { return "Set up your goal in Strategy to get daily coaching." }
        let n = entries(on: dayKey()).reduce(Nutrients.zero) { $0 + $1.nutrients }
        var out: [String] = []
        let left = t.protein - n.protein
        out.append(left > 20 ? "Protein first: \(Int(left)) g to go today, spread over your next meals (30–50 g each)." : "Protein is on track today.")
        out.append("Aim for \(Int(t.kcal)) kcal; \(Int(max(0, t.kcal - n.kcal))) left.")
        if dueCheckIn != nil { out.append("Your weekly check-in is ready: do it today.") }
        out.append("Weigh in tomorrow morning, after the bathroom, before eating.")
        return out.joined(separator: " ")
    }
}

@MainActor final class Coach: ObservableObject {
    static let shared = Coach()
    @Published private(set) var note: CoachNote? = {
        (UserDefaults.standard.data(forKey: "coachNote")).flatMap { try? JSONDecoder().decode(CoachNote.self, from: $0) }
    }()
    @Published private(set) var working = false

    /// Today's note (made now if there isn't one yet, or when you ask for a fresh one).
    func refresh(_ ctx: ModelContext, force: Bool = false) async {
        guard force || note?.day != dayKey(), !working else { return }
        working = true
        defer { working = false }
        let prompt = """
        You are an experienced natural bodybuilding and nutrition coach. From this athlete's data, write today's coaching note:
        3 or 4 short, specific bullet points (start each with "• "), 70 words at most in total, in English, no title, no greeting.
        Cover what matters most today: eating to the targets (especially protein), training or recovery, and one thing to adjust
        based on how the trend compares with the goal. Use their real numbers. Be direct and practical, no medical claims.

        Data:
        \(ctx.coachFacts())
        """
        var n: CoachNote
        if let r = try? await PhotoAI.ask(prompt), !r.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            n = CoachNote(day: dayKey(), text: r.text.trimmingCharacters(in: .whitespacesAndNewlines), by: r.by)
        } else {
            n = CoachNote(day: dayKey(), text: ctx.ruleNote(), by: "the app's rules")
        }
        note = n
        if let d = try? JSONEncoder().encode(n) { UserDefaults.standard.set(d, forKey: "coachNote") }
    }
}

/// The card on the Strategy tab.
struct CoachCard: View {
    @Environment(\.modelContext) private var ctx
    @ObservedObject private var coach = Coach.shared
    @State private var force = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Today's coaching", systemImage: "figure.strengthtraining.traditional").font(.headline)
                Spacer()
                if coach.working { ProgressView().controlSize(.small) }
                else {
                    Button { force = true; Task { await coach.refresh(ctx, force: true); force = false } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                }
            }
            if let n = coach.note, n.day == dayKey(), !(coach.working && force) {
                Text(n.text).font(.callout).fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                    .id(n.text)
                Text("By \(n.by) · from your last two weeks").font(.caption2).foregroundStyle(.secondary)
            } else if coach.working {
                WorkingCard(title: "Reading your last two weeks…")
            } else {
                Text("Tap refresh for today's note.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .modifier(CardSurface())
        .animation(Motion.pick(Motion.smooth), value: coach.note)
        .animation(Motion.pick(Motion.smooth), value: coach.working)
        .task { await coach.refresh(ctx) }
    }
}
