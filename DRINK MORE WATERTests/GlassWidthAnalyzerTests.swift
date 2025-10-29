import CoreGraphics
import Foundation
import Testing
@testable import DRINK_MORE_WATER

@Suite("GlassWidthAnalyzer")
struct GlassWidthAnalyzerTests {
    @Test("precomputes width fractions for mask image")
    func precomputesWidthFractions() throws {
        let width = 8
        let height = 4
        let filledColumnsPerRow = [8, 4, 0, 6]

        let image = try makeMaskImage(width: width, height: height, filledColumnsPerRow: filledColumnsPerRow)
        let analyzer = GlassWidthAnalyzer(maskImage: image)

        for (row, filled) in filledColumnsPerRow.enumerated() {
            let yFraction = CGFloat(row) / CGFloat(height - 1)
            let expected = CGFloat(filled) / CGFloat(width)
            let actual = analyzer.widthFraction(atYFraction: yFraction)
            #expect(actual != nil)
            if let actual {
                #expect(abs(actual - expected) <= 0.0001)
            }
        }
    }

    @Test("clamps yFraction requests outside of bounds")
    func clampsOutOfBoundsRequests() throws {
        let width = 5
        let height = 2
        let filled = [5, 2]

        let image = try makeMaskImage(width: width, height: height, filledColumnsPerRow: filled)
        let analyzer = GlassWidthAnalyzer(maskImage: image)

        let below = analyzer.widthFraction(atYFraction: -1)
        let above = analyzer.widthFraction(atYFraction: 2)
        let expectedBottom = CGFloat(filled.first!) / CGFloat(width)
        let expectedTop = CGFloat(filled.last!) / CGFloat(width)

        #expect(below != nil)
        #expect(above != nil)
        if let below {
            #expect(abs(below - expectedBottom) <= 0.0001)
        }
        if let above {
            #expect(abs(above - expectedTop) <= 0.0001)
        }
    }
}

private extension GlassWidthAnalyzerTests {
    func makeMaskImage(width: Int, height: Int, filledColumnsPerRow: [Int]) throws -> CGImage {
        precondition(filledColumnsPerRow.count == height)

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            let filled = max(0, min(width, filledColumnsPerRow[row]))
            for column in 0..<filled {
                let index = (row * width + column) * 4
                pixels[index + 3] = 255 // alpha channel
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw MaskImageError.creationFailed
        }

        return image
    }
}

private enum MaskImageError: Error {
    case creationFailed
}
