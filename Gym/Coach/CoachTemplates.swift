import Foundation

// Messages written straight from the snapshot: used when no model is reachable or a model's message
// fails validation. Always valid by construction (Tests/coacheval checks every scenario).

enum CoachTemplates {
    static func message(_ s: CoachSnapshot) -> CoachMessage {
        if s.safety.stepBack { return stepBack(s) }
        switch s.moment {
        case .morning: return morning(s)
        case .nudge: return nudge(s)
        case .postWorkout: return postWorkout(s)
        case .checkIn: return checkIn(s)
        case .event: return event(s)
        }
    }

    static func stepBack(_ s: CoachSnapshot) -> CoachMessage {
        CoachMessage(headline: "Take a step back today",
                     body: "Your recent logs show some very low days. Eat regular meals today and don't chase the targets. If eating has been feeling hard, it's worth talking to a doctor or someone you trust.",
                     action: nil)
    }

    static func morning(_ s: CoachSnapshot) -> CoachMessage {
        var parts: [String] = ["Today: \(s.today.kcalTarget) kcal with \(s.today.proteinTarget) g protein."]
        if !s.today.special.isEmpty { parts.append("It's a \(s.today.special.joined(separator: " and ")).") }
        if let m = s.nextMeal, !m.foods.isEmpty { parts.append("Next on the plan, \(m.time): \(m.foods.prefix(3).joined(separator: ", ")).") }
        if s.checkIn.due { parts.append("Your weekly check-in is ready.") }
        else if let f = s.flags.first { parts.append(f) }
        else if s.expenditure.settling { parts.append("The expenditure estimate is still settling; steady weigh-ins will tighten it.") }
        else if s.weighInsLast7 < 4 { parts.append("Weigh in tomorrow morning: \(s.weighInsLast7) of 7 days so far makes the trend less sure.") }
        return CoachMessage(headline: s.checkIn.due ? "Check-in day" : "Good morning", body: parts.joined(separator: " "),
                            action: s.checkIn.due ? .init(kind: .openCheckIn, label: "Open check-in") : nil)
    }

    static func nudge(_ s: CoachSnapshot) -> CoachMessage {
        let food = s.frequentProteinFoods.first.map { " One of your usual options: \($0)." } ?? ""
        return CoachMessage(headline: "Protein is behind",
                            body: "\(s.today.proteinLeft) g of protein to go with about \(s.today.mealsLeftToday) meal\(s.today.mealsLeftToday == 1 ? "" : "s") left.\(food)",
                            action: .init(kind: .logFood, label: "Log food"))
    }

    static func postWorkout(_ s: CoachSnapshot) -> CoachMessage {
        guard let w = s.lastWorkout else { return CoachMessage(headline: "Session saved", body: "Your workout is logged.") }
        var b = "\(w.sets) sets of \(w.name)."
        if w.prs > 0 { b += " \(w.prs) personal record\(w.prs == 1 ? "" : "s")." }
        if let v = w.volumeChangePct { b += v >= 0 ? " Volume up \(v)% on last time." : " Volume down \(abs(v))% on last time." }
        if let f = s.flags.first { b += " " + f }
        return CoachMessage(headline: w.prs > 0 ? "New records" : "Session done", body: b)
    }

    static func checkIn(_ s: CoachSnapshot) -> CoachMessage {
        let c = s.checkIn
        let why = c.lastReason.map { " " + $0 } ?? ""
        switch c.lastAction {
        case "no change"?: return CoachMessage(headline: "No change this week", body: "The engine kept \(c.lastFrom ?? s.today.kcalTarget) kcal.\(why)",
                                               action: .init(kind: .openCheckIn, label: "See why"))
        case "proposed"?: return CoachMessage(headline: "A new proposal", body: "The engine proposes \(c.lastTo ?? 0) kcal (from \(c.lastFrom ?? 0)).\(why) Accept or edit it in the check-in.",
                                              action: .init(kind: .openProposal, label: "Review proposal"))
        case let a?: return CoachMessage(headline: a == "reported" ? "Your week in numbers" : "Targets updated",
                                         body: "\(c.lastFrom ?? 0) → \(c.lastTo ?? 0) kcal.\(why)", action: .init(kind: .openCheckIn, label: "See why"))
        case nil: return CoachMessage(headline: "Check-in ready", body: "Your weekly check-in is ready.", action: .init(kind: .openCheckIn, label: "Open check-in"))
        }
    }

    static func event(_ s: CoachSnapshot) -> CoachMessage {
        CoachMessage(headline: "That jump is water",
                     body: "The scale moved after a \(s.waterEvent ?? "water event"). That's expected water, and the trend has already accounted for it: it stays at \(String(format: "%.1f", s.trend.kg)) kg.")
    }
}

enum CoachPrompt {
    static func make(_ s: CoachSnapshot) -> String {
        """
        You are a knowledgeable natural-bodybuilding coach writing one short message for the app's coach card.
        Moment: \(s.moment.rawValue).

        RULES (a validator rejects any message that breaks them):
        - Use ONLY numbers that appear in the SNAPSHOT below, written the same way. No other numbers, no calculations.
        - Never set, suggest or change a calorie or macro target. If something should change, point to the weekly check-in or the engine's proposal.
        - Cite evidence only by the ids in "evidence", and describe it only with its text. Do not add findings.
        - Direct, specific, short: headline at most 8 words, body at most 3 sentences. No markdown.
        - No praise for eating little, no guilt for going over. Explain uncertainty honestly when "settling" is true.
        - If safety.veryLowIntakeDays is 4 or more or safety.distressInNotes is true: do not push any goal; suggest stepping back gently and, if appropriate, talking to a doctor. Never diagnose.
        - PRIORITY: if safety says step back, that is the whole message. Otherwise, if "flags" is not empty, the message is about the first flag
          (say what it means in plain words). Evidence is optional support, never the main point.
        - Moments: morning = today's targets plus one useful note; nudge = only if protein is well behind, suggest one of frequentProteinFoods;
          postWorkout = how it went vs last time; checkIn = explain the engine's decision (lastAction, lastReason) in plain words, including uncertainty; if lastAction is "proposed", say it's a proposal to review, accept or edit in the check-in;
          event = the scale jump is expected water and the engine has accounted for it.
        - If nextMeal is present you may mention it (time, foods, its kcal and protein), never other quantities.

        Reply with JSON only: {"headline":"","body":"","action":{"kind":"openCheckIn|openProposal|logFood|startWorkout|weighIn|none","label":""},"evidence":[]}

        SNAPSHOT:
        \(s.json())
        """
    }
}

/// When the coach speaks: quiet by default.
enum CoachSchedule {
    /// The moment worth a message now, if any.
    static func moment(hour: Int, alreadyToday: Set<CoachSnapshot.Moment>, max perDay: Int, s: CoachSnapshot,
                       justTrained: Bool, recentWaterJump: Bool) -> CoachSnapshot.Moment? {
        guard alreadyToday.count < perDay else { return nil }
        if s.checkIn.due, s.checkIn.lastAction != nil, !alreadyToday.contains(.checkIn) { return .checkIn }
        if justTrained, !alreadyToday.contains(.postWorkout) { return .postWorkout }
        if recentWaterJump, !alreadyToday.contains(.event) { return .event }
        if (5..<12).contains(hour), !alreadyToday.contains(.morning) { return .morning }
        // Nudge only when it adds value: protein well behind with little of the day left.
        if hour >= 16, !alreadyToday.contains(.nudge), s.today.proteinTarget > 0,
           Double(s.today.proteinLeft) > Double(s.today.proteinTarget) * 0.35, s.today.mealsLeftToday <= 2 { return .nudge }
        return nil
    }
}
