import CoreGraphics

/// Describes the fractional bounds of the glass mask where 0 = bottom and 1 = top.
public struct WaterMaskBounds {
    public let emptyFraction: CGFloat
    public let fullFraction: CGFloat

    public init(emptyFraction: CGFloat, fullFraction: CGFloat) {
        self.emptyFraction = emptyFraction
        self.fullFraction = fullFraction
    }

    /// Calibrated for the `glass_mask` artwork (shared by the app and the widget).
    public static let glass = WaterMaskBounds(
        emptyFraction: 1.0 - 0.8799630655586334,
        fullFraction: 1.0 - 0.198522622345337
    )
}
