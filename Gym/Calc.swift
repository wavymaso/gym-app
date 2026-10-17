import Foundation

// The numbers behind the macro side: starting expenditure, calorie and macro
// targets, and units. Plain Swift (no SwiftUI or SwiftData) so it can be tested alone.

// MARK: - Choices

enum Sex: String, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "Male" : "Female" }
}

enum Activity: String, CaseIterable, Identifiable {
    case sedentary, light, moderate, active, veryActive
    var id: String { rawValue }

    var label: String {
        switch self {
        case .sedentary: return "Sedentary"
        case .light: return "Lightly active"
        case .moderate: return "Moderately active"
        case .active: return "Very active"
        case .veryActive: return "Extremely active"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: return "Desk job, little walking, no training"
        case .light: return "On your feet some of the day, or training 1–3 times a week"
        case .moderate: return "Training 3–5 times a week, or an active job"
        case .active: return "Hard training 6–7 times a week, or a physical job"
        case .veryActive: return "Physical job and hard daily training"
        }
    }

    /// Multiplier on resting energy (BMR) for the starting estimate.
    var factor: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }
}

enum GoalType: String, CaseIterable, Identifiable {
    case lose, maintain, gain
    var id: String { rawValue }
    var label: String { self == .lose ? "Lose weight" : self == .gain ? "Gain weight" : "Maintain weight" }
    var sign: Double { self == .lose ? -1 : self == .gain ? 1 : 0 }

    /// Rates as % of body weight per week.
    var rates: [Double] {
        switch self {
        case .lose: return [0.25, 0.5, 0.75, 1.0]
        case .maintain: return [0]
        case .gain: return [0.1, 0.25, 0.5]
        }
    }

    var defaultRate: Double { self == .lose ? 0.5 : self == .gain ? 0.25 : 0 }

    func rateLabel(_ r: Double) -> String {
        switch (self, r) {
        case (.lose, ..<0.3): return "Gentle"
        case (.lose, ..<0.6): return "Moderate"
        case (.lose, ..<0.8): return "Fast"
        case (.lose, _): return "Very fast"
        case (.gain, ..<0.15): return "Lean"
        case (.gain, ..<0.3): return "Moderate"
        case (.gain, _): return "Fast"
        default: return "Maintain"
        }
    }
}

enum DietStyle: String, CaseIterable, Identifiable {
    case balanced, lowFat, lowCarb, keto
    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced: return "Balanced"
        case .lowFat: return "Low fat"
        case .lowCarb: return "Low carb"
        case .keto: return "Keto"
        }
    }

    var detail: String {
        switch self {
        case .balanced: return "About 30% of calories from fat, the rest from carbs"
        case .lowFat: return "About 20% from fat, more room for carbs"
        case .lowCarb: return "About 20% from carbs, the rest from fat"
        case .keto: return "Carbs kept to 30 g a day"
        }
    }
}

enum ProteinLevel: String, CaseIterable, Identifiable {
    case low, moderate, high, extraHigh
    var id: String { rawValue }
    var label: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .extraHigh: return "Extra high"
        }
    }
    /// Grams per kg of body weight.
    var gramsPerKg: Double {
        switch self {
        case .low: return 1.6
        case .moderate: return 2.0
        case .high: return 2.4
        case .extraHigh: return 2.8
        }
    }
}

// MARK: - Energy and targets

/// Energy in a kg of body weight change (mostly fat, some lean and water).
let kcalPerKg = 7700.0

/// Ways to estimate resting energy before there's any data.
enum BMREquation: String, CaseIterable, Identifiable {
    case mifflin, katch, harris
    var id: String { rawValue }
    var label: String { ["Mifflin–St Jeor", "Katch–McArdle", "Harris–Benedict (revised)"][Self.allCases.firstIndex(of: self)!] }
    var detail: String {
        ["The most accurate general formula. Recommended.",
         "Uses your lean mass, so it needs a body fat %. Best if you're quite lean or very muscular.",
         "The classic formula, revised in 1984. Tends to run a little high."][Self.allCases.firstIndex(of: self)!]
    }
    static var current: BMREquation { BMREquation(rawValue: UserDefaults.standard.string(forKey: "bmrEquation") ?? "") ?? .mifflin }
}

/// Resting energy (Mifflin–St Jeor by default).
func bmr(sex: Sex, weightKg: Double, heightCm: Double, age: Int, equation: BMREquation = .mifflin, bodyFat: Double? = nil) -> Double {
    switch equation {
    case .mifflin:
        return 10 * weightKg + 6.25 * heightCm - 5 * Double(age) + (sex == .male ? 5 : -161)
    case .katch:
        guard let bf = bodyFat, bf > 2, bf < 70 else { return bmr(sex: sex, weightKg: weightKg, heightCm: heightCm, age: age) }
        return 370 + 21.6 * weightKg * (1 - bf / 100)
    case .harris:
        return sex == .male ? 88.362 + 13.397 * weightKg + 4.799 * heightCm - 5.677 * Double(age)
                            : 447.593 + 9.247 * weightKg + 3.098 * heightCm - 4.330 * Double(age)
    }
}

/// The starting estimate of what you burn in a day, before there's any logged data.
func startingExpenditure(sex: Sex, weightKg: Double, heightCm: Double, age: Int, activity: Activity,
                         equation: BMREquation = .mifflin, bodyFat: Double? = nil) -> Double {
    roundTo(bmr(sex: sex, weightKg: weightKg, heightCm: heightCm, age: age, equation: equation, bodyFat: bodyFat) * activity.factor, 10)
}

/// Kilograms per week for a goal and rate (% of body weight), signed: negative = losing.
func weeklyChangeKg(goal: GoalType, ratePercent: Double, weightKg: Double) -> Double {
    goal.sign * ratePercent / 100 * weightKg
}

struct Targets: Equatable, Codable {
    var kcal: Double
    var protein: Double
    var fat: Double
    var carbs: Double
}

/// Lowest daily calories the app will suggest.
func calorieFloor(_ sex: Sex) -> Double { sex == .male ? 1500 : 1200 }

/// Daily calories and macros for a goal, from the current expenditure.
/// How you train: sets how much protein is worth eating.
enum TrainingType: String, CaseIterable, Identifiable {
    case none, aerobic, resistance
    var id: String { rawValue }
    var label: String { ["None", "Mostly cardio", "Lifting"][Self.allCases.firstIndex(of: self)!] }
    var proteinFactor: Double { [0.75, 0.85, 1.0][Self.allCases.firstIndex(of: self)!] }
}

/// What, beyond weight, the targets depend on (all optional: without it, the simple rules apply).
struct BodyInfo {
    var leanKg: Double?                   // from a body-fat reading or tape estimate
    var heightCm: Double = 0
    var training: TrainingType = .resistance
    var floorKcal: Double? = nil          // your own calorie floor
    var guardrails = true                 // coached: calorie floor and fat minimum
}

extension ProteinLevel {
    /// Grams per kg of lean mass (lifting; less for cardio or no training).
    var gramsPerLeanKg: Double { [2.0, 2.4, 2.8, 3.2][Self.allCases.firstIndex(of: self)!] }
}

/// Protein for a level: by lean mass when known; otherwise by body weight, capped at the
/// weight you'd be at a BMI of 27 so a heavier person isn't told to eat for their fat mass.
func proteinGrams(_ level: ProteinLevel, weightKg: Double, body: BodyInfo?) -> Double {
    guard let body else { return level.gramsPerKg * weightKg }
    if let lean = body.leanKg, lean > 20 {
        // A tape or scale body-fat reading is ±3–4 points: keep the result in a sane range of body weight.
        let g = level.gramsPerLeanKg * lean * body.training.proteinFactor
        return min(max(g, 1.5 * weightKg), 2.6 * weightKg)
    }
    let h = body.heightCm / 100
    let ref = h > 1 ? min(weightKg, 27 * h * h) : weightKg
    return level.gramsPerKg * ref * body.training.proteinFactor
}

func makeTargets(expenditure: Double, weightKg: Double, sex: Sex, goal: GoalType, ratePercent: Double,
                 diet: DietStyle, protein level: ProteinLevel, body: BodyInfo? = nil) -> Targets {
    let dailyDelta = weeklyChangeKg(goal: goal, ratePercent: ratePercent, weightKg: weightKg) * kcalPerKg / 7
    let floor = body?.guardrails == false ? 800 : (body?.floorKcal ?? calorieFloor(sex))
    let kcal = roundTo(max(expenditure + dailyDelta, floor), 10)
    // Protein first, but never more than 40% of calories.
    let protein = min(roundTo(proteinGrams(level, weightKg: weightKg, body: body), 1), (kcal * 0.4 / 4).rounded(.down))
    let rest = kcal - protein * 4
    var fat: Double, carbs: Double
    switch diet {
    case .balanced, .lowFat:
        fat = min(kcal * (diet == .balanced ? 0.30 : 0.20) / 9, rest / 9)
        carbs = (rest - fat * 9) / 4
    case .lowCarb, .keto:
        carbs = min(diet == .keto ? 30 : kcal * 0.20 / 4, rest / 4)
        fat = (rest - carbs * 4) / 9
    }
    // Coached guardrail: enough fat for normal hormone function (0,5 g per kg, at least 40 g).
    if body?.guardrails == true {
        let minFat = max(40, 0.5 * weightKg)
        if fat < minFat { fat = min(minFat, rest / 9); carbs = max(0, (rest - fat * 9) / 4) }
    }
    return Targets(kcal: kcal, protein: protein, fat: max(0, fat.rounded()), carbs: max(0, carbs.rounded()))
}

func roundTo(_ x: Double, _ step: Double) -> Double { (x / step).rounded() * step }

func age(born: Date, on day: Date = Date()) -> Int {
    Calendar(identifier: .gregorian).dateComponents([.year], from: born, to: day).year ?? 0
}

// MARK: - Units

enum WeightUnit: String, CaseIterable, Identifiable {
    case kg, lb
    var id: String { rawValue }
    static let lbPerKg = 2.2046226218
    func fromKg(_ kg: Double) -> Double { self == .kg ? kg : kg * Self.lbPerKg }
    func toKg(_ v: Double) -> Double { self == .kg ? v : v / Self.lbPerKg }
    func format(_ kg: Double, digits: Int = 1) -> String { "\(number(fromKg(kg), digits: digits)) \(rawValue)" }
}

enum EnergyUnit: String, CaseIterable, Identifiable {
    case kcal, kJ
    var id: String { rawValue }
    static let kJPerKcal = 4.184
    func fromKcal(_ k: Double) -> Double { self == .kcal ? k : k * Self.kJPerKcal }
    func toKcal(_ v: Double) -> Double { self == .kcal ? v : v / Self.kJPerKcal }
    func format(_ kcal: Double) -> String { "\(number(fromKcal(kcal), digits: 0)) \(rawValue)" }
}

/// 175 cm, or 5′ 9″ when you use pounds.
func formatHeight(_ cm: Double, _ unit: WeightUnit) -> String {
    if unit == .kg { return "\(Int(cm.rounded())) cm" }
    let inches = Int((cm / 2.54).rounded())
    return "\(inches / 12)′ \(inches % 12)″"
}

private let numberFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "es_ES")
    f.usesGroupingSeparator = true
    f.minimumGroupingDigits = 2                         // Spanish style: 2150, but 12.500
    return f
}()

/// "2150", "12.500", "72,4": Spanish separators, like your other apps.
func number(_ x: Double, digits: Int = 0) -> String {
    numberFormatter.minimumFractionDigits = digits
    numberFormatter.maximumFractionDigits = digits
    return numberFormatter.string(from: NSNumber(value: x)) ?? String(format: "%.\(digits)f", x)
}

/// Up to `digits` decimals, without trailing zeros: 77,5 · 46,25 · 80.
func trimmed(_ x: Double, digits: Int = 2) -> String {
    numberFormatter.minimumFractionDigits = 0
    numberFormatter.maximumFractionDigits = digits
    return numberFormatter.string(from: NSNumber(value: x)) ?? String(x)
}

/// "72,4" or "72.4" -> 72.4
func parseNumber(_ text: String) -> Double? {
    let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    return Double(t)
}

// MARK: - Days

/// English with European dates: 14/10/2026, "Wednesday 14 October", weeks from Monday.
let appLocale = Locale(identifier: "en_GB")

/// "0,5%", "0,25%", "1%".
func percent(_ x: Double) -> String { "\(number(x, digits: x == x.rounded() ? 0 : (x * 10 == (x * 10).rounded() ? 1 : 2)))%" }

/// The calendar day of a moment, where you are now (the zone is read each time, so it follows travel).
func dayKey(_ d: Date) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = NSTimeZone.default
    let c = cal.dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
}

/// Today, the day you're logging into: before the day-start hour (Settings → Food log, default
/// midnight) it's still yesterday, for late dinners and nights out.
func dayKey() -> String { todayKey(now: Date()) }

func todayKey(now: Date) -> String {
    let start = dayStartHour
    return dayKey(start > 0 ? now.addingTimeInterval(-Double(start) * 3600) : now)
}

/// 0 (midnight) to 6. During Ramadan mode at least 5: iftar to suhoor is one day.
var dayStartHour: Int {
    let set = min(max(UserDefaults.standard.integer(forKey: "dayStartHour"), 0), 6)
    return ramadanActive ? max(set, 5) : set
}

/// Ramadan mode: on until a calendar day (it switches itself off).
var ramadanActive: Bool {
    guard let until = UserDefaults.standard.string(forKey: "ramadanUntil") else { return false }
    return dayKey(Date()) <= until
}
func date(fromKey k: String) -> Date {
    let p = k.split(separator: "-").compactMap { Int($0) }
    guard p.count == 3 else { return Date() }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = NSTimeZone.default
    return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) ?? Date()
}

/// "+0,35 kg", "−0,20 kg".
func signed(_ unit: WeightUnit, _ kg: Double) -> String {
    let v = unit.fromKg(kg)
    return (v > 0.005 ? "+" : v < -0.005 ? "−" : "") + "\(number(abs(v), digits: 2)) \(unit.rawValue)"
}
