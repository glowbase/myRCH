import Foundation
import SwiftUI

// MARK: - Percentiles

/// The percentile curves drawn on each chart.
enum Percentile: Double, CaseIterable, Identifiable {
    case p2 = 2, p5 = 5, p10 = 10, p25 = 25, p50 = 50
    case p75 = 75, p90 = 90, p95 = 95, p98 = 98

    var id: Double { rawValue }

    var label: String {
        switch self {
        case .p2: "2nd"
        case .p5: "5th"
        case .p10: "10th"
        case .p25: "25th"
        case .p50: "50th"
        case .p75: "75th"
        case .p90: "90th"
        case .p95: "95th"
        case .p98: "98th"
        }
    }

    /// z-score for this percentile of a normal distribution.
    var z: Double {
        switch self {
        case .p2: -2.054
        case .p5: -1.645
        case .p10: -1.282
        case .p25: -0.674
        case .p50: 0
        case .p75: 0.674
        case .p90: 1.282
        case .p95: 1.645
        case .p98: 2.054
        }
    }

    var color: Color {
        switch self {
        case .p98: Color(red: 0.20, green: 0.55, blue: 0.90)
        case .p95: Color(red: 0.85, green: 0.20, blue: 0.60)
        case .p90: Color(red: 0.40, green: 0.65, blue: 0.20)
        case .p75: Color(red: 0.60, green: 0.30, blue: 0.80)
        case .p50: Color(red: 0.10, green: 0.60, blue: 0.72)
        case .p25: Color(red: 0.90, green: 0.50, blue: 0.10)
        case .p10: Color(red: 0.40, green: 0.35, blue: 0.85)
        case .p5: Color(red: 0.10, green: 0.55, blue: 0.45)
        case .p2: Color(red: 0.90, green: 0.35, blue: 0.30)
        }
    }

    /// The 50th line is drawn heavier so the median stands out.
    var isMedian: Bool { self == .p50 }
}

// MARK: - Reference curves

/// A reference curve expressed as a median and standard deviation at each point
/// on the x axis, from which percentile curves and z-scores are derived.
///
/// IMPORTANT: the values below are **approximate sample data** for building and
/// demonstrating the UI. They are close to the WHO Child Growth Standards but
/// are not the official LMS tables, and must be replaced with real reference
/// data (or values supplied by the portal) before this is used clinically.
struct GrowthReference {
    struct Knot {
        let x: Double
        let median: Double
        let sd: Double
    }

    let knots: [Knot]

    /// Linearly interpolates the median and SD at an arbitrary x.
    func stats(at x: Double) -> (median: Double, sd: Double)? {
        guard let first = knots.first, let last = knots.last, x >= first.x, x <= last.x else { return nil }
        for (lower, upper) in zip(knots, knots.dropFirst()) where x <= upper.x {
            let span = upper.x - lower.x
            let t = span == 0 ? 0 : (x - lower.x) / span
            return (lower.median + (upper.median - lower.median) * t,
                    lower.sd + (upper.sd - lower.sd) * t)
        }
        return (last.median, last.sd)
    }

    /// The value on a given percentile curve at x.
    func value(at x: Double, percentile: Percentile) -> Double? {
        guard let stats = stats(at: x) else { return nil }
        return stats.median + percentile.z * stats.sd
    }

    /// Where a measured value sits, as a percentile from 0–100.
    func percentile(of value: Double, at x: Double) -> Double? {
        guard let stats = stats(at: x), stats.sd > 0 else { return nil }
        let z = (value - stats.median) / stats.sd
        return normalCDF(z) * 100
    }

    var xRange: ClosedRange<Double> {
        guard let first = knots.first, let last = knots.last else { return 0...1 }
        return first.x...last.x
    }

    private func normalCDF(_ z: Double) -> Double {
        0.5 * (1 + erf(z / 2.0.squareRoot()))
    }
}

// MARK: - Metrics

/// The four charts offered, matching the portal's measurement types.
enum GrowthMetric: String, CaseIterable, Identifiable {
    case lengthForAge, weightForAge, weightForLength, bmiForAge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lengthForAge: "Length for Age"
        case .weightForAge: "Weight for Age"
        case .weightForLength: "Weight for Length"
        case .bmiForAge: "BMI for Age"
        }
    }

    /// x axis is age in months except for weight-for-length.
    var isAgeBased: Bool { self != .weightForLength }

    func xLabel(metric unit: GrowthUnit) -> String {
        isAgeBased ? "Age (months)" : "Length (\(unit.lengthLabel))"
    }

    func yLabel(metric unit: GrowthUnit) -> String {
        switch self {
        case .lengthForAge: "Length (\(unit.lengthLabel))"
        case .weightForAge, .weightForLength: "Weight (\(unit.massLabel))"
        case .bmiForAge: "BMI (kg/m²)"
        }
    }
}

/// Display units. BMI is always kg/m², as it is in the portal.
enum GrowthUnit: String, CaseIterable, Identifiable {
    case metric, imperial

    var id: String { rawValue }
    var title: String { self == .metric ? "cm/kg" : "in/lb" }
    var lengthLabel: String { self == .metric ? "cm" : "in" }
    var massLabel: String { self == .metric ? "kg" : "lb" }

    func length(_ cm: Double) -> Double { self == .metric ? cm : cm / 2.54 }
    func mass(_ kg: Double) -> Double { self == .metric ? kg : kg * 2.2046226 }
}

// MARK: - Data sets

/// A reference data set, e.g. WHO girls 0–2 years.
struct GrowthDataSet: Identifiable, Hashable {
    let id: String
    let name: String
    let source: String

    static func == (lhs: GrowthDataSet, rhs: GrowthDataSet) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static let whoGirls0to2 = GrowthDataSet(
        id: "who-girls-0-2", name: "WHO Girls (0–2 years)",
        source: "WHO Child Growth Standards")
    static let whoBoys0to2 = GrowthDataSet(
        id: "who-boys-0-2", name: "WHO Boys (0–2 years)",
        source: "WHO Child Growth Standards")

    static let all: [GrowthDataSet] = [.whoGirls0to2, .whoBoys0to2]

    /// The reference curve for a metric within this data set.
    func reference(for metric: GrowthMetric) -> GrowthReference {
        let isGirls = id == GrowthDataSet.whoGirls0to2.id
        switch metric {
        case .lengthForAge: return isGirls ? .girlsLengthForAge : .boysLengthForAge
        case .weightForAge: return isGirls ? .girlsWeightForAge : .boysWeightForAge
        case .weightForLength: return isGirls ? .girlsWeightForLength : .boysWeightForLength
        case .bmiForAge: return isGirls ? .girlsBMIForAge : .boysBMIForAge
        }
    }
}

// MARK: - Approximate WHO-style reference data (sample values — see note above)

extension GrowthReference {
    /// Length (cm) by age in months.
    static let girlsLengthForAge = GrowthReference(knots: [
        .init(x: 0, median: 49.1, sd: 1.9), .init(x: 1, median: 53.7, sd: 2.0),
        .init(x: 2, median: 57.1, sd: 2.1), .init(x: 3, median: 59.8, sd: 2.2),
        .init(x: 4, median: 62.1, sd: 2.3), .init(x: 5, median: 64.0, sd: 2.3),
        .init(x: 6, median: 65.7, sd: 2.4), .init(x: 7, median: 67.3, sd: 2.5),
        .init(x: 8, median: 68.7, sd: 2.5), .init(x: 9, median: 70.1, sd: 2.6),
        .init(x: 10, median: 71.5, sd: 2.7), .init(x: 11, median: 72.8, sd: 2.7),
        .init(x: 12, median: 74.0, sd: 2.8), .init(x: 15, median: 77.5, sd: 2.9),
        .init(x: 18, median: 80.7, sd: 3.0), .init(x: 21, median: 83.7, sd: 3.1),
        .init(x: 24, median: 86.4, sd: 3.2)
    ])

    static let boysLengthForAge = GrowthReference(knots: [
        .init(x: 0, median: 49.9, sd: 1.9), .init(x: 1, median: 54.7, sd: 2.0),
        .init(x: 2, median: 58.4, sd: 2.1), .init(x: 3, median: 61.4, sd: 2.2),
        .init(x: 4, median: 63.9, sd: 2.3), .init(x: 5, median: 65.9, sd: 2.3),
        .init(x: 6, median: 67.6, sd: 2.4), .init(x: 7, median: 69.2, sd: 2.5),
        .init(x: 8, median: 70.6, sd: 2.5), .init(x: 9, median: 72.0, sd: 2.6),
        .init(x: 10, median: 73.3, sd: 2.7), .init(x: 11, median: 74.5, sd: 2.7),
        .init(x: 12, median: 75.7, sd: 2.8), .init(x: 15, median: 79.1, sd: 2.9),
        .init(x: 18, median: 82.3, sd: 3.0), .init(x: 21, median: 85.1, sd: 3.1),
        .init(x: 24, median: 87.8, sd: 3.2)
    ])

    /// Weight (kg) by age in months.
    static let girlsWeightForAge = GrowthReference(knots: [
        .init(x: 0, median: 3.2, sd: 0.40), .init(x: 1, median: 4.2, sd: 0.52),
        .init(x: 2, median: 5.1, sd: 0.62), .init(x: 3, median: 5.8, sd: 0.70),
        .init(x: 4, median: 6.4, sd: 0.76), .init(x: 5, median: 6.9, sd: 0.81),
        .init(x: 6, median: 7.3, sd: 0.86), .init(x: 7, median: 7.6, sd: 0.90),
        .init(x: 8, median: 7.9, sd: 0.94), .init(x: 9, median: 8.2, sd: 0.98),
        .init(x: 10, median: 8.5, sd: 1.01), .init(x: 11, median: 8.7, sd: 1.05),
        .init(x: 12, median: 8.9, sd: 1.08), .init(x: 15, median: 9.6, sd: 1.17),
        .init(x: 18, median: 10.2, sd: 1.26), .init(x: 21, median: 10.9, sd: 1.35),
        .init(x: 24, median: 11.5, sd: 1.44)
    ])

    static let boysWeightForAge = GrowthReference(knots: [
        .init(x: 0, median: 3.3, sd: 0.41), .init(x: 1, median: 4.5, sd: 0.54),
        .init(x: 2, median: 5.6, sd: 0.65), .init(x: 3, median: 6.4, sd: 0.73),
        .init(x: 4, median: 7.0, sd: 0.79), .init(x: 5, median: 7.5, sd: 0.84),
        .init(x: 6, median: 7.9, sd: 0.89), .init(x: 7, median: 8.3, sd: 0.93),
        .init(x: 8, median: 8.6, sd: 0.97), .init(x: 9, median: 8.9, sd: 1.01),
        .init(x: 10, median: 9.2, sd: 1.05), .init(x: 11, median: 9.4, sd: 1.08),
        .init(x: 12, median: 9.6, sd: 1.12), .init(x: 15, median: 10.3, sd: 1.21),
        .init(x: 18, median: 10.9, sd: 1.30), .init(x: 21, median: 11.5, sd: 1.39),
        .init(x: 24, median: 12.2, sd: 1.48)
    ])

    /// Weight (kg) by length (cm).
    static let girlsWeightForLength = GrowthReference(knots: [
        .init(x: 45, median: 2.5, sd: 0.25), .init(x: 50, median: 3.4, sd: 0.32),
        .init(x: 55, median: 4.5, sd: 0.41), .init(x: 60, median: 6.0, sd: 0.53),
        .init(x: 65, median: 7.2, sd: 0.63), .init(x: 70, median: 8.5, sd: 0.74),
        .init(x: 75, median: 9.6, sd: 0.85), .init(x: 80, median: 10.9, sd: 0.97),
        .init(x: 85, median: 12.1, sd: 1.10), .init(x: 90, median: 13.5, sd: 1.24)
    ])

    static let boysWeightForLength = GrowthReference(knots: [
        .init(x: 45, median: 2.4, sd: 0.25), .init(x: 50, median: 3.3, sd: 0.32),
        .init(x: 55, median: 4.5, sd: 0.42), .init(x: 60, median: 6.2, sd: 0.55),
        .init(x: 65, median: 7.4, sd: 0.65), .init(x: 70, median: 8.7, sd: 0.76),
        .init(x: 75, median: 9.9, sd: 0.87), .init(x: 80, median: 11.1, sd: 0.99),
        .init(x: 85, median: 12.4, sd: 1.12), .init(x: 90, median: 13.8, sd: 1.26)
    ])

    /// BMI (kg/m²) by age in months.
    static let girlsBMIForAge = GrowthReference(knots: [
        .init(x: 0, median: 13.3, sd: 1.30), .init(x: 1, median: 14.6, sd: 1.32),
        .init(x: 2, median: 15.8, sd: 1.36), .init(x: 3, median: 16.4, sd: 1.38),
        .init(x: 6, median: 16.9, sd: 1.40), .init(x: 9, median: 16.6, sd: 1.38),
        .init(x: 12, median: 16.4, sd: 1.36), .init(x: 18, median: 16.1, sd: 1.34),
        .init(x: 24, median: 15.7, sd: 1.32)
    ])

    static let boysBMIForAge = GrowthReference(knots: [
        .init(x: 0, median: 13.4, sd: 1.30), .init(x: 1, median: 14.9, sd: 1.33),
        .init(x: 2, median: 16.3, sd: 1.37), .init(x: 3, median: 16.9, sd: 1.39),
        .init(x: 6, median: 17.3, sd: 1.41), .init(x: 9, median: 17.0, sd: 1.39),
        .init(x: 12, median: 16.8, sd: 1.37), .init(x: 18, median: 16.3, sd: 1.35),
        .init(x: 24, median: 16.0, sd: 1.33)
    ])
}
