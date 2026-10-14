import Foundation
import SwiftData

// Body measurements and progress photos, on the Weight page. Both sync like everything else;
// photos stay on your own devices (stored in the app, sent only to your Mac).

/// What you can measure, in cm (shown in inches when you use pounds).
enum BodySite: String, CaseIterable, Identifiable {
    case waist, chest, hips, neck, armL, armR, thighL, thighR, calf
    var id: String { rawValue }
    var label: String {
        switch self {
        case .waist: return "Waist"
        case .chest: return "Chest"
        case .hips: return "Hips"
        case .neck: return "Neck"
        case .armL: return "Left arm"
        case .armR: return "Right arm"
        case .thighL: return "Left thigh"
        case .thighR: return "Right thigh"
        case .calf: return "Calf"
        }
    }
    var hint: String {
        switch self {
        case .waist: return "At the navel, relaxed"
        case .chest: return "Across the nipples"
        case .hips: return "Widest point of the glutes"
        case .neck: return "Just below the Adam's apple"
        case .armL, .armR: return "Flexed, widest point"
        case .thighL, .thighR: return "Widest point, standing"
        case .calf: return "Widest point"
        }
    }
    /// Smaller is the usual goal (for the colour of the change).
    var smallerIsBetter: Bool? { self == .waist ? true : (self == .hips || self == .neck ? nil : false) }
}

@Model final class Measurement {
    var syncID: String = ""
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var day: String
    var site: String
    var cm: Double

    init(day: String, site: BodySite, cm: Double) { self.day = day; self.site = site.rawValue; self.cm = cm }
}

@Model final class ProgressPhoto {
    var syncID: String = ""
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)
    var day: String
    var pose: String                         // front | side | back
    @Attribute(.externalStorage) var jpeg: Data
    var createdAt: Date = Date()

    init(day: String, pose: String, jpeg: Data) { self.day = day; self.pose = pose; self.jpeg = jpeg }
}

enum Pose: String, CaseIterable, Identifiable {
    case front, side, back
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Length in the unit that goes with your weight unit.
extension WeightUnit {
    var lengthUnit: String { self == .lb ? "in" : "cm" }
    func fromCm(_ cm: Double) -> Double { self == .lb ? cm / 2.54 : cm }
    func toCm(_ v: Double) -> Double { self == .lb ? v * 2.54 : v }
    func formatLength(_ cm: Double) -> String { "\(number(fromCm(cm), digits: 1)) \(lengthUnit)" }
}

/// US Navy body-fat estimate (Hodgdon & Beckett), from tape measurements; nil without what it needs.
func navyBodyFat(sex: Sex, heightCm: Double, waist: Double?, neck: Double?, hips: Double?) -> Double? {
    guard let waist, let neck, heightCm > 0 else { return nil }
    let bf: Double
    switch sex {
    case .male:
        guard waist - neck > 0 else { return nil }
        bf = 495 / (1.0324 - 0.19077 * log10(waist - neck) + 0.15456 * log10(heightCm)) - 450
    case .female:
        guard let hips, waist + hips - neck > 0 else { return nil }
        bf = 495 / (1.29579 - 0.35004 * log10(waist + hips - neck) + 0.22100 * log10(heightCm)) - 450
    }
    return bf.isFinite && bf > 2 && bf < 70 ? bf : nil
}

extension ModelContext {
    /// Save one day's measurements (replacing that day's earlier ones for the same sites).
    func saveMeasurements(_ values: [BodySite: Double], day: String) {
        let existing = (try? fetch(FetchDescriptor<Measurement>(predicate: #Predicate { $0.day == day }))) ?? []
        for (site, cm) in values where cm > 0 {
            if let m = existing.first(where: { $0.site == site.rawValue }) { m.cm = cm } else { insert(Measurement(day: day, site: site, cm: cm)) }
        }
        commit()
    }
}
