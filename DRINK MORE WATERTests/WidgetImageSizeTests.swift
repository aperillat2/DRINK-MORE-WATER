import Testing
import UIKit

/// WidgetKit refuses to draw a widget that contains an image above a size limit, and shows
/// grey placeholder boxes instead (`ArchivingError.imageTooLarge`). The limit scales with the
/// widget's size on each device: observed limits are 2.2 × width by 2 × height of the small
/// widget in pixels (iPhone 17 Pro: 158 pt @3x → 1042.8 × 948; iPad Pro 13": 170 pt @2x → 748 × 680).
/// The smallest small widget on any iOS 17+ device is 141 pt @2x (iPad mini, 10.2" iPad),
/// so every widget image must fit that device's limit.
@Suite("Widget images")
struct WidgetImageSizeTests {
    /// Smallest small-widget side, in pixels, across supported devices.
    static let smallestWidgetPixels: CGFloat = 141 * 2
    static let maxWidth = smallestWidgetPixels * 2.2
    static let maxHeight = smallestWidgetPixels * 2
    static let maxArea = maxWidth * maxHeight

    /// Every image asset in the widget extension's asset catalog. Add new ones here.
    static let widgetImageNames = ["widget_glass_empty", "widget_glass_water", "widget_glass_surface", "widget_glass_words"]

    static var widgetBundle: Bundle? {
        Bundle.main.builtInPlugInsURL
            .map { $0.appendingPathComponent("DrinkMoreWaterWidgetExtension.appex") }
            .flatMap(Bundle.init(url:))
    }

    @Test func widgetExtensionIsEmbedded() {
        #expect(Self.widgetBundle != nil)
    }

    @Test(arguments: widgetImageNames)
    func imageFitsTheSmallestWidgetLimit(_ name: String) throws {
        let bundle = try #require(Self.widgetBundle)
        let image = try #require(UIImage(named: name, in: bundle, compatibleWith: nil),
                                 "\(name) is missing from the widget's asset catalog")
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        #expect(width <= Self.maxWidth, "\(name) is \(Int(width)) px wide; max is \(Int(Self.maxWidth))")
        #expect(height <= Self.maxHeight, "\(name) is \(Int(height)) px tall; max is \(Int(Self.maxHeight))")
        #expect(width * height <= Self.maxArea, "\(name) has \(Int(width * height)) px; max is \(Int(Self.maxArea))")
    }
}
