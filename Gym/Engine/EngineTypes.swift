import Foundation

// The Coaching Engine: plain Swift, no UI, no database, no network. Same inputs → same outputs.
// The app (and tools/engine) turn logged data into these inputs; everything the engine decides
// comes back with the reasons and registry entries behind it.

/// A day, as a number (0 = the first day of the input). Consecutive days, no gaps.
struct EngineDay: Equatable {
    var key: String                   // yyyy-MM-dd (for records and display only)
    var weighIns: [Double] = []       // kg, already corrected to the main scale
    var intake: Double? = nil         // kcal, nil = not logged (or half-logged): unknown, never imputed as 0
    var events: Set<WaterEvent> = []
    var steps: Double? = nil
}

/// Things that move the scale through water, not tissue.
enum WaterEvent: String, CaseIterable, Codable {
    case refeed, dietBreakStart, dietBreakEnd, highSodium, travel, creatineStart, illness, tagged
    /// How much water can jump (kg sd) and how many days it lingers.
    var size: Double {
        switch self {
        case .creatineStart: return 0.75        // registry water.creatine.litres (≈ kg)
        case .refeed, .dietBreakStart, .dietBreakEnd: return 0.8
        case .highSodium, .travel, .tagged: return 0.6
        case .illness: return 1.0
        }
    }
}

struct BodyComposition: Equatable {
    var bodyFatPercent: Double?       // measured or estimated; nil = unknown
    var assumedBodyFatPercent = 20.0  // registry body.fallbackBodyFat (grade D) when unknown
    func fatMass(weight: Double) -> Double { weight * (bodyFatPercent ?? assumedBodyFatPercent) / 100 }
    func leanMass(weight: Double) -> Double { weight - fatMass(weight: weight) }
    var isEstimated: Bool { bodyFatPercent == nil }
}

/// Why the engine did something: a rule, in words, and the registry entries it used.
struct EngineReason: Equatable, Codable {
    var rule: String
    var detail: String
    var evidence: [String] = []
}
