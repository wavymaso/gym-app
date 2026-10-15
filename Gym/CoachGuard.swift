import Foundation

// Until the full grounding validator (Phase 4): the AI may not state any number at all. Numbers in
// the coaching note come only from the app's own templates (the same figures shown on Today).

enum CoachGuard {
    /// True if the AI's text contains no numbers (digits, or number words with units) and no unit claims.
    static func isNumberFree(_ text: String) -> Bool {
        if text.rangeOfCharacter(from: .decimalDigits) != nil { return false }
        let lower = text.lowercased()
        let banned = ["kcal", "calories a day", "grams", " g of", " g protein", " kg", "percent", "%"]
        if banned.contains(where: { lower.contains($0) }) { return false }
        let numberWords = ["hundred", "thousand", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
        return !numberWords.contains { lower.contains($0) }
    }
}
