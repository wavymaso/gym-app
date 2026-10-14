import Foundation
import SwiftData

// Supplements you take (creatine, vitamin D, …): tick them off each day, keep the streak.
// Both sync like everything else.

@Model final class Supplement {
    var syncID: String = ""
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var key: String = UUID().uuidString
    var name: String
    var dose: String
    var emoji: String
    var timing: String                       // morning | pre | post | evening | any
    var order: Int
    var active: Bool = true

    init(name: String, dose: String, emoji: String, timing: String = "any", order: Int) {
        self.name = name; self.dose = dose; self.emoji = emoji; self.timing = timing; self.order = order
    }
}

@Model final class SupplementTake {
    var syncID: String = ""
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var day: String
    var supplementKey: String

    init(day: String, supplementKey: String) { self.day = day; self.supplementKey = supplementKey }
}

enum SupplementTiming: String, CaseIterable, Identifiable {
    case morning, pre, post, evening, any
    var id: String { rawValue }
    var label: String { ["Morning", "Pre-workout", "Post-workout", "Evening", "Any time"][Self.allCases.firstIndex(of: self)!] }
}

/// Common ones, to add in a tap.
let supplementSuggestions: [(String, String, String, String)] = [
    ("Creatine", "5 g", "💪", "any"), ("Vitamin D", "2000 IU", "☀️", "morning"), ("Omega-3", "2 g", "🐟", "morning"),
    ("Multivitamin", "1 tablet", "💊", "morning"), ("Magnesium", "300 mg", "🌙", "evening"), ("Caffeine", "200 mg", "☕️", "pre"),
    ("Electrolytes", "1 serving", "🧂", "pre"), ("Zinc", "15 mg", "🛡️", "evening"), ("Ashwagandha", "600 mg", "🌿", "evening"),
    ("Citrulline", "6 g", "🍉", "pre"), ("Beta-alanine", "3,2 g", "⚡️", "pre"), ("Melatonin", "1 mg", "😴", "evening"),
]

extension ModelContext {
    var supplements: [Supplement] {
        (try? fetch(FetchDescriptor<Supplement>(predicate: #Predicate { $0.active }, sortBy: [SortDescriptor(\.order)]))) ?? []
    }

    func takes(on day: String) -> [SupplementTake] {
        (try? fetch(FetchDescriptor<SupplementTake>(predicate: #Predicate { $0.day == day }))) ?? []
    }

    func toggleTake(_ s: Supplement, on day: String) {
        let key = s.key
        if let t = ((try? fetch(FetchDescriptor<SupplementTake>(predicate: #Predicate { $0.day == day && $0.supplementKey == key }))) ?? []).first {
            delete(t)
        } else {
            insert(SupplementTake(day: day, supplementKey: key))
        }
        commit()
    }

    /// Days in a row taken, counting back from today (or yesterday, if today isn't ticked yet).
    func streak(_ s: Supplement) -> Int {
        let key = s.key
        let days = Set(((try? fetch(FetchDescriptor<SupplementTake>(predicate: #Predicate { $0.supplementKey == key }))) ?? []).map(\.day))
        var d = days.contains(dayKey()) ? dayKey() : addDays(dayKey(), -1)
        var n = 0
        while days.contains(d) { n += 1; d = addDays(d, -1) }
        return n
    }
}
