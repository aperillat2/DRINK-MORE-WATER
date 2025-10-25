import CoreGraphics

/// Describes the fractional bounds of the glass mask where 0 = bottom and 1 = top.
public struct WaterMaskBounds {
    public let emptyFraction: CGFloat
    public let fullFraction: CGFloat

    public init(emptyFraction: CGFloat, fullFraction: CGFloat) {
        self.emptyFraction = emptyFraction
        self.fullFraction = fullFraction
    }
}
