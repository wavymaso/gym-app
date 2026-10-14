import Foundation

// Trend weight and adaptive expenditure. Plain Swift, so it can be tested alone.
//
// Follows the principles MacroFactor describes publicly (its exact parameters are
// not published, so these are our own):
// - Trend weight: missing days are filled in on a straight line between weigh-ins,
//   then smoothed with an exponential moving average, so one salty dinner or a
//   heavy leg day doesn't move it much, but a real change does.
// - Expenditure: what you ate, minus the energy your weight change says you stored
//   (or used). It starts from the setup estimate and hands over to your own data
//   over about three weeks, changing a little each day.

/// How much of each new day the trend takes in (0.1 = about a 10-day memory).
let trendSmoothing = 0.1

struct DayValue: Equatable {
    var day: String
    var value: Double
}

/// Every day from the first weigh-in to `through` (or the last weigh-in): interpolated scale weight and trend.
func trendSeries(_ weights: [DayValue], through end: String? = nil) -> [(day: String, scale: Double, trend: Double, logged: Bool)] {
    let sorted = weights.sorted { $0.day < $1.day }
    guard let first = sorted.first else { return [] }
    let byDay = Dictionary(sorted.map { ($0.day, $0.value) }, uniquingKeysWith: { _, b in b })
    let last = max(end ?? sorted.last!.day, sorted.last!.day)
    var out: [(String, Double, Double, Bool)] = []
    var trend = first.value
    var prev = sorted[0]
    var nextIndex = 1
    for day in days(from: first.day, through: last) {
        let scale: Double
        if let w = byDay[day] {
            scale = w
            prev = DayValue(day: day, value: w)
            while nextIndex < sorted.count && sorted[nextIndex].day <= day { nextIndex += 1 }
        } else if nextIndex < sorted.count {
            // Between two weigh-ins: on the straight line joining them.
            let next = sorted[nextIndex]
            let span = Double(daysBetween(prev.day, next.day)), k = Double(daysBetween(prev.day, day))
            scale = prev.value + (next.value - prev.value) * k / span
        } else {
            scale = prev.value                                   // after the last weigh-in: hold it
        }
        if !out.isEmpty { trend += trendSmoothing * (scale - trend) }
        out.append((day, scale, trend, byDay[day] != nil))
    }
    return out.map { (day: $0.0, scale: $0.1, trend: $0.2, logged: $0.3) }
}

// MARK: - Expenditure

struct ExpenditureSettings {
    var window = 21                 // days of intake and weigh-ins looked at
    var minTrackedLast7 = 4         // fewer tracked days than this in the last week: hold the estimate
    var startUncertainty = 350.0    // kcal: how far off the formula estimate might be
    var dailyDrift = 25.0           // kcal: how much your real expenditure can change in a day
    var overlap = 6.0               // each day's window shares most of its data with yesterday's: count it less
    var maxDailyChange = 75.0       // kcal
}

struct ExpenditurePoint: Equatable {
    var day: String
    var kcal: Double
    var paused: Bool                // not enough food logged lately: held at the previous value
    var confidence: Double          // 0 = starting estimate only, 1 = your data only
}

/// Daily expenditure from `start` through `end`.
/// - intake: kcal per tracked day (days with nothing logged are left out, not counted as zero).
/// - weights: scale weigh-ins.
func expenditureSeries(start: String, end: String, initial: Double, intake: [String: Double], weights: [DayValue],
                       settings s: ExpenditureSettings = ExpenditureSettings()) -> [ExpenditurePoint] {
    // Work in day numbers (0 = start) so long histories stay fast.
    let all = days(from: start, through: end)
    guard !all.isEmpty else { return [] }
    let index = Dictionary(uniqueKeysWithValues: all.enumerated().map { ($0.element, $0.offset) })
    var eaten = [Double?](repeating: nil, count: all.count)
    var weighed = [Double?](repeating: nil, count: all.count)
    for (d, k) in intake { if let i = index[d] { eaten[i] = k } }
    for w in weights { if let i = index[w.day] { weighed[i] = w.value } }

    // A small Kalman filter: the estimate and how sure we are of it. Each day's evidence moves it
    // in proportion to how reliable that evidence is, so a noisy first week barely does, and three
    // solid weeks take over from the formula completely.
    var est = initial
    var variance = s.startUncertainty * s.startUncertainty
    var out = [ExpenditurePoint(day: start, kcal: initial, paused: false, confidence: 0)]
    for i in 1..<all.count {
        variance += s.dailyDrift * s.dailyDrift
        let lo = max(0, i - (s.window - 1))
        let tracked = (lo...i).compactMap { eaten[$0] }
        let trackedLast7 = (max(lo, i - 6)...i).filter { eaten[$0] != nil }.count
        let last7Count = i - max(lo, i - 6) + 1
        // The rate of change is a line of best fit through the weigh-ins themselves: unlike the
        // smoothed trend it doesn't lag, and over three weeks the day-to-day water swings average out.
        let points = (lo...i).compactMap { j in weighed[j].map { (Double(j - lo), $0) } }

        // Hold the estimate if the last week is too patchy, or there aren't enough weigh-ins to compare.
        guard trackedLast7 >= min(s.minTrackedLast7, last7Count), tracked.count >= 3, points.count >= 7 else {
            out.append(ExpenditurePoint(day: all[i], kcal: est, paused: true, confidence: out.last!.confidence))
            continue
        }
        let avgIntake = tracked.reduce(0, +) / Double(tracked.count)
        let (kgPerDay, slopeError) = fit(points)
        let fromData = avgIntake - kgPerDay * kcalPerKg          // eating more than you burn shows up as gaining
        // How uncertain today's evidence is: the weight-change error in kcal, plus the intake average's.
        let intakeSpread = tracked.count > 1 ? spread(tracked) / Double(tracked.count).squareRoot() : 300
        let evidenceVariance = (pow(slopeError * kcalPerKg, 2) + intakeSpread * intakeSpread) * s.overlap
        let gain = variance / (variance + evidenceVariance)
        est += max(-s.maxDailyChange, min(s.maxDailyChange, gain * (fromData - est)))
        variance *= (1 - gain)
        let confidence = 1 - variance / (s.startUncertainty * s.startUncertainty)
        out.append(ExpenditurePoint(day: all[i], kcal: est, paused: false, confidence: max(0, min(1, confidence))))
    }
    return out
}

/// Least-squares slope and its standard error.
func fit(_ p: [(Double, Double)]) -> (slope: Double, error: Double) {
    let n = Double(p.count)
    guard n >= 3 else { return (0, .infinity) }
    let m = slope(p)
    let mx = p.reduce(0) { $0 + $1.0 } / n, my = p.reduce(0) { $0 + $1.1 } / n
    let sxx = p.reduce(0) { $0 + ($1.0 - mx) * ($1.0 - mx) }
    let residuals = p.reduce(0) { $0 + pow($1.1 - (my + m * ($1.0 - mx)), 2) }
    return (m, (residuals / (n - 2) / sxx).squareRoot())
}

func spread(_ xs: [Double]) -> Double {
    let mean = xs.reduce(0, +) / Double(xs.count)
    return (xs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(max(1, xs.count - 1))).squareRoot()
}

/// Least-squares slope of y over x.
func slope(_ p: [(Double, Double)]) -> Double {
    let n = Double(p.count)
    guard n >= 2 else { return 0 }
    let mx = p.reduce(0) { $0 + $1.0 } / n, my = p.reduce(0) { $0 + $1.1 } / n
    let sxx = p.reduce(0) { $0 + ($1.0 - mx) * ($1.0 - mx) }
    guard sxx > 0 else { return 0 }
    return p.reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / sxx
}

/// Trend change per week over the last `days` days (kg; negative = losing).
func weeklyTrendChange(_ series: [(day: String, scale: Double, trend: Double, logged: Bool)], days n: Int = 14) -> Double? {
    let recent = series.suffix(n)
    guard recent.count >= 7 else { return nil }
    return slope(recent.enumerated().map { (Double($0.offset), $0.element.trend) }) * 7
}

// MARK: - Day arithmetic (on "yyyy-MM-dd" keys)

// Day keys ("2026-10-14") as plain numbers: days since 1970-01-01 (Hinnant's civil
// calendar algorithm). No DateFormatter, so long series stay fast.

/// "2026-10-14" → days since 1970-01-01.
func dayNumber(_ key: String) -> Int {
    var y = 0, m = 0, d = 0, field = 0
    for c in key.utf8 {
        if c == 45 { field += 1; continue }                    // "-"
        let v = Int(c) - 48
        guard v >= 0 && v <= 9 else { continue }
        switch field { case 0: y = y * 10 + v; case 1: m = m * 10 + v; default: d = d * 10 + v }
    }
    let yy = m <= 2 ? y - 1 : y
    let era = (yy >= 0 ? yy : yy - 399) / 400
    let yoe = yy - era * 400
    let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146097 + doe - 719468
}

/// Days since 1970-01-01 → "2026-10-14".
func dayKey(number z0: Int) -> String {
    let z = z0 + 719468
    let era = (z >= 0 ? z : z - 146096) / 146097
    let doe = z - era * 146097
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let d = doy - (153 * mp + 2) / 5 + 1
    let m = mp + (mp < 10 ? 3 : -9)
    let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
    func two(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }
    return "\(y)-\(two(m))-\(two(d))"
}

func addDays(_ day: String, _ n: Int) -> String { dayKey(number: dayNumber(day) + n) }

func daysBetween(_ a: String, _ b: String) -> Int { dayNumber(b) - dayNumber(a) }

func days(from a: String, through b: String) -> [String] {
    guard a <= b else { return [] }
    let start = dayNumber(a)
    return (start...dayNumber(b)).map { dayKey(number: $0) }
}
