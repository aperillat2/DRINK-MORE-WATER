import Foundation

/// Unit used to display and enter water amounts.
enum VolumeUnit: String, CaseIterable, Identifiable {
    case oz
    case ml

    static let mlPerOz: Double = 29.5735

    var id: String { rawValue }

    /// Short label shown next to amounts (e.g. "80 oz").
    var label: String { rawValue }

    var perTapRange: ClosedRange<Int> {
        switch self {
        case .oz: return 5...20
        case .ml: return 150...600
        }
    }

    var perTapStep: Int {
        switch self {
        case .oz: return 1
        case .ml: return 10
        }
    }

    var goalRange: ClosedRange<Int> {
        switch self {
        case .oz: return 40...200
        case .ml: return 1200...6000
        }
    }

    var goalStep: Int {
        switch self {
        case .oz: return 10
        case .ml: return 100
        }
    }

    /// Converts an amount expressed in `other` units into this unit.
    func convert(_ value: Int, from other: VolumeUnit) -> Double {
        switch (other, self) {
        case (.oz, .ml): return Double(value) * Self.mlPerOz
        case (.ml, .oz): return Double(value) / Self.mlPerOz
        default: return Double(value)
        }
    }

    /// Rounds `value` to the nearest multiple of `step` and clamps it into `range`.
    static func snap(_ value: Double, step: Int, range: ClosedRange<Int>) -> Int {
        let snapped = Int((value / Double(step)).rounded()) * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }
}
