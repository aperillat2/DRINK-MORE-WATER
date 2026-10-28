import CoreGraphics

/// Describes the fractional bounds of the glass mask where 0 = bottom and 1 = top.
public struct WaterMaskBounds {
    public let emptyFraction: CGFloat
    public let fullFraction: CGFloat

    public init(emptyFraction: CGFloat, fullFraction: CGFloat) {
        self.emptyFraction = emptyFraction
        self.fullFraction = fullFraction
    }

    /// The main screen's photo glass: 0 and 1 are `GlassArt.emptyLevelY` and `fullLevelY`
    /// (the splash photo's water line).
    public static let photoGlass = WaterMaskBounds(emptyFraction: 0, fullFraction: 1)

    /// Calibrated for the widget's `glass_mask` artwork.
    public static let glass = WaterMaskBounds(
        emptyFraction: 1.0 - 0.8799630655586334,
        fullFraction: 1.0 - 0.198522622345337
    )
}
