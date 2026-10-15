import Foundation

// Trend weight as a state-space model (Kalman filter): true mass, its rate of change, and water.
// - Missing days: the model just predicts forward (uncertainty grows).
// - Several weigh-ins in a day: their mean, trusted more (noise / n).
// - Outliers: a surprise beyond a few sd counts less (robust update).
// - Water events (refeed, travel, creatine…): the water term is allowed to jump, so the scale jump
//   lands there instead of in the trend.
// Output per day: trend (mass without water), rate per week, and the trend's uncertainty (sd).

/// Defaults tuned on the first two thirds of the user's history for 1–4 week forecasts (Tests/backtest TREND=1 TUNE=1).
struct TrendSettings: Equatable {
    var massNoise = 0.01          // kg/day sd: unexplained change in true mass
    var rateNoise = 0.005         // kg/day² sd: how quickly the rate itself can change
    var waterSD = 0.3             // kg: typical size of day-to-day water swings
    var waterPersistence = 0.6    // how much of today's water is still there tomorrow
    var scaleNoise = 0.2          // kg sd of a single weigh-in on top of water
    var outlierZ = 3.0
    var maxTissuePerDay = 0.25    // kg: true tissue can't change faster (≈ a 2 000 kcal imbalance); more is water
    var maxWater = 2.0            // kg: the most water the scale can plausibly carry above or below the trend
}

struct TrendPoint: Equatable {
    var day: String
    var trend: Double             // kg
    var ratePerWeek: Double       // kg/week
    var sd: Double                // kg (1 sd)
    var water: Double             // kg the model attributes to water today
    var weighed: Bool
}

enum EngineTrend {
    static func run(_ days: [EngineDay], _ s: TrendSettings = TrendSettings()) -> [TrendPoint] {
        guard let firstIdx = days.firstIndex(where: { !$0.weighIns.isEmpty }) else { return [] }
        let m0 = days[firstIdx].weighIns.reduce(0, +) / Double(days[firstIdx].weighIns.count)
        var x = [m0, 0.0, 0.0]                                     // mass, rate (kg/day), water
        var P: [[Double]] = [[0.5, 0, 0], [0, 0.01, 0], [0, 0, s.waterSD * s.waterSD]]
        let phi = s.waterPersistence
        var out: [TrendPoint] = []
        var lastWeighed = firstIdx - 1
        for i in firstIdx..<days.count {
            let d = days[i]
            if i > firstIdx {
                // Predict
                x = [x[0] + x[1], x[1], phi * x[2]]
                let F = [[1.0, 1, 0], [0, 1, 0], [0, 0, phi]]
                var wq = s.waterSD * s.waterSD * (1 - phi * phi)
                for e in d.events { wq += e.size * e.size }
                P = add(mul(mul(F, P), transpose(F)), [[s.massNoise * s.massNoise, 0, 0], [0, s.rateNoise * s.rateNoise, 0], [0, 0, wq]])
            }
            if !d.weighIns.isEmpty {
                let y = d.weighIns.reduce(0, +) / Double(d.weighIns.count)
                var R = s.scaleNoise * s.scaleNoise / Double(d.weighIns.count)
                let innov = y - (x[0] + x[2])
                let S0 = P[0][0] + 2 * P[0][2] + P[2][2] + R
                let z = abs(innov) / S0.squareRoot()
                if z > s.outlierZ { R *= pow(z / s.outlierZ, 2) }
                let S = P[0][0] + 2 * P[0][2] + P[2][2] + R
                let K = (0..<3).map { (P[$0][0] + P[$0][2]) / S }
                for k in 0..<3 { x[k] += K[k] * innov }
                // Physiology: tissue can't move more than this per day since the last weigh-in; the
                // rest of the jump is water, up to what water can plausibly hold (then it's mass after all).
                let move = K[0] * innov
                let limit = s.maxTissuePerDay * Double(i - lastWeighed)
                if abs(move) > limit {
                    var excess = move - (move > 0 ? limit : -limit)
                    let room = s.maxWater - abs(x[2])
                    excess = excess > 0 ? min(excess, max(room, 0)) : max(excess, -max(room, 0))
                    x[0] -= excess; x[2] += excess
                }
                lastWeighed = i
                let HP = (0..<3).map { c in P[0][c] + P[2][c] }
                for a in 0..<3 { for b in 0..<3 { P[a][b] -= K[a] * HP[b] } }
            }
            out.append(TrendPoint(day: d.key, trend: x[0], ratePerWeek: x[1] * 7, sd: max(P[0][0], 0).squareRoot(),
                                  water: x[2], weighed: !d.weighIns.isEmpty))
        }
        return out
    }
}

fileprivate func mul(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
    (0..<a.count).map { i in (0..<b[0].count).map { j in (0..<b.count).reduce(0.0) { $0 + a[i][$1] * b[$1][j] } } }
}
fileprivate func add(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] { zip(a, b).map { zip($0, $1).map(+) } }
fileprivate func transpose(_ a: [[Double]]) -> [[Double]] { (0..<a[0].count).map { j in a.map { $0[j] } } }
