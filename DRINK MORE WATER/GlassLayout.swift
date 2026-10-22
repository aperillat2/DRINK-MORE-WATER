import CoreGraphics

/// Sizing for the glass on the main screen.
enum GlassLayout {
    /// Size of the visible glass inside `WaterGlassView`'s 551×722 design canvas
    /// (measured from the artwork, plus a small margin). The glass is centered in that canvas.
    static let visibleSize = CGSize(width: 300, height: 550)

    /// Upper limit so the glass doesn't get oversized (and blurry) on iPad.
    static let maxScale: CGFloat = 1.6

    /// Scale at which the visible glass fits inside `available`.
    static func scale(toFit available: CGSize) -> CGFloat {
        guard available.width > 0, available.height > 0 else { return 1 }
        let fit = min(available.width / visibleSize.width, available.height / visibleSize.height)
        return min(fit, maxScale)
    }
}
