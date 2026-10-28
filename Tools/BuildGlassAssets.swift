// Rebuilds the main screen's glass images from the two source photos.
//
//   swiftc -O Tools/BuildGlassAssets.swift -o /tmp/buildglass
//   /tmp/buildglass <full-glass-photo.jpg> <empty-glass-photo.jpg> <output-folder>
//
// Both photos must be 896×1200 and pixel-aligned (same camera, same glass position).
// Then copy splash_photo.jpg, glass_background.jpg, glass_water.jpg, glass_surface.png and
// glass_words.png into the matching image sets in DRINK MORE WATER/Assets.xcassets.
// The measurements below (text lines, surface rows) must match `GlassArt` in WaterGlassView.swift.

import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Builds the main-screen glass assets from two pixel-aligned 896×1200 photos:
//   full  = the splash photo (water + "DRINK MORE WATER")
//   empty = the same glass, empty
// Everything is expressed in "photo" coordinates; the photo sits unscaled in the middle of a
// 2400×1800 canvas (photo origin = (752, 300)), so all layers line up with the background.

let fullPath = CommandLine.arguments[1], emptyPath = CommandLine.arguments[2], outDir = CommandLine.arguments[3]
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

struct Bitmap {
    var w: Int, h: Int, px: [Float]   // RGBA, 0...1, row 0 = top
    init(w: Int, h: Int) { self.w = w; self.h = h; px = [Float](repeating: 0, count: w * h * 4) }
    init(_ img: CGImage) {
        w = img.width; h = img.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        px = bytes.map { Float($0) / 255 }
    }
    subscript(x: Int, y: Int, c: Int) -> Float {
        get { px[(y * w + x) * 4 + c] }
        set { px[(y * w + x) * 4 + c] = newValue }
    }
    func cgImage() -> CGImage {
        var bytes = px.map { UInt8(max(0, min(255, ($0 * 255).rounded()))) }
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }
    func crop(x: Int, y: Int, w cw: Int, h ch: Int) -> Bitmap {
        var out = Bitmap(w: cw, h: ch)
        for yy in 0..<ch { for xx in 0..<cw { for c in 0..<4 { out[xx, yy, c] = self[x + xx, y + yy, c] } } }
        return out
    }
}

func load(_ path: String) -> CGImage {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}
func save(_ img: CGImage, _ name: String, jpeg: Bool) {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    let type = jpeg ? UTType.jpeg.identifier : UTType.png.identifier
    let dest = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary : nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(name) \(img.width)x\(img.height)")
}

/// Separable box blur (3 passes ≈ gaussian) of a single-channel buffer.
func blur(_ src: [Float], w: Int, h: Int, radius r: Int) -> [Float] {
    var a = src, b = src
    for _ in 0..<3 {
        for y in 0..<h {   // horizontal
            var acc: Float = 0; var n: Float = 0
            for x in -r...r where x >= 0 && x < w { acc += a[y * w + x]; n += 1 }
            for x in 0..<w {
                b[y * w + x] = acc / n
                let add = x + r + 1, rem = x - r
                if add < w { acc += a[y * w + add]; n += 1 }
                if rem >= 0 { acc -= a[y * w + rem]; n -= 1 }
            }
        }
        for x in 0..<w {   // vertical
            var acc: Float = 0; var n: Float = 0
            for y in -r...r where y >= 0 && y < h { acc += b[y * w + x]; n += 1 }
            for y in 0..<h {
                a[y * w + x] = acc / n
                let add = y + r + 1, rem = y - r
                if add < h { acc += b[add * w + x]; n += 1 }
                if rem >= 0 { acc -= b[rem * w + x]; n -= 1 }
            }
        }
    }
    return a
}

let full = Bitmap(load(fullPath)), empty = Bitmap(load(emptyPath))
precondition(full.w == empty.w && full.h == empty.h)

// MARK: 1. Lift the words off the water.
// Text region (measured): x 284...606, y 487...798. Work in a padded box around it.
let tx = 270, ty = 470, tw = 360, th = 350
// Text mask: within each measured text line, the letters are near-white (min channel ≳ 0.75),
// while the water and the glass's vertical highlights behind them stay below ≈ 0.65.
let lines: [(y0: Int, y1: Int, x0: Int, x1: Int)] = [(479, 581, 289, 601), (594, 693, 302, 590), (702, 802, 277, 613)]
var mask = [Float](repeating: 0, count: tw * th)
for line in lines { for y in line.y0...line.y1 { for x in line.x0...line.x1 {
    if min(full[x, y, 0], full[x, y, 1], full[x, y, 2]) > 0.62 { mask[(y - ty) * tw + (x - tx)] = 1 }
} } }
// Grow it by ~3 px so the anti-aliased edges are included.
var grown = blur(mask, w: tw, h: th, radius: 2).map { $0 > 0.02 ? Float(1) : 0 }
grown = blur(grown, w: tw, h: th, radius: 1).map { $0 > 0.02 ? Float(1) : 0 }
// Water behind the letters, interpolated from the non-letter pixels: first vertically (the glass's
// highlights are vertical streaks, so this continues them through the letters), then a small 2-D
// pass for anything left.
var background = full
for c in 0..<3 {
    var value = [Float](repeating: 0, count: tw * th), weight = [Float](repeating: 0, count: tw * th)
    for y in 0..<th { for x in 0..<tw where grown[y * tw + x] == 0 {
        value[y * tw + x] = full[tx + x, ty + y, c]; weight[y * tw + x] = 1 } }
    // vertical normalised average (radius 45)
    var fill = [Float](repeating: 0, count: tw * th), fw = [Float](repeating: 0, count: tw * th)
    let r = 80
    for x in 0..<tw {
        for y in 0..<th where grown[y * tw + x] == 1 {
            var acc: Float = 0, n: Float = 0
            for yy in max(0, y - r)...min(th - 1, y + r) where weight[yy * tw + x] > 0 {
                let wgt = 1 / Float(1 + abs(yy - y)); acc += value[yy * tw + x] * wgt; n += wgt }
            if n > 0 { fill[y * tw + x] = acc / n; fw[y * tw + x] = 1 }
        }
    }
    // light horizontal smoothing of the filled values to hide column-to-column noise
    let sm = blur(fill, w: tw, h: th, radius: 1), smw = blur(fw, w: tw, h: th, radius: 1)
    for y in 0..<th { for x in 0..<tw where grown[y * tw + x] == 1 {
        let v = smw[y * tw + x] > 0.001 ? sm[y * tw + x] / smw[y * tw + x] : full[tx + x, ty + y, c]
        background[tx + x, ty + y, c] = max(0, min(1, v))
    } }
}
// Text matte from the red channel: full = α·white + (1-α)·background.
var words = Bitmap(w: tw, h: th)
for y in 0..<th { for x in 0..<tw {
    var a: Float = 0
    if grown[y * tw + x] == 1 {
        let f = full[tx + x, ty + y, 0], bg = background[tx + x, ty + y, 0]
        a = max(0, min(1, (f - bg) / max(0.05, 1 - bg)))
        if a < 0.04 { a = 0 }
    }
    // premultiplied white
    words[x, y, 0] = a; words[x, y, 1] = a; words[x, y, 2] = a; words[x, y, 3] = a
} }

// MARK: 2. Water without words, and without its own surface (the app draws the surface).
// Below the photo's surface (row 412 on) this is the real water. Above it, where the photo has air,
// the water is synthesised: the empty glass plus how the water changes each column (measured just
// below the surface, rows 420...470), so the glass's highlights look the same all the way up.
let surfaceBottom = 412, blendRows = 8
var columnDelta = [Float](repeating: 0, count: full.w * 3)
for x in 0..<full.w { for c in 0..<3 {
    var acc: Float = 0
    for y in 420...470 { acc += full[x, y, c] - empty[x, y, c] }
    columnDelta[x * 3 + c] = acc / 51
} }
// Smooth across columns so JPEG noise doesn't become vertical stripes.
for c in 0..<3 {
    var col = [Float](repeating: 0, count: full.w)
    for x in 0..<full.w { col[x] = columnDelta[x * 3 + c] }
    let sm = blur(col, w: full.w, h: 1, radius: 2)
    for x in 0..<full.w { columnDelta[x * 3 + c] = sm[x] }
}
var water = full
for y in 0..<full.h { for x in 0..<full.w { for c in 0..<3 {
    let fromFull: Float = y >= surfaceBottom ? 1 : (y <= surfaceBottom - blendRows ? 0 : Float(y - (surfaceBottom - blendRows)) / Float(blendRows))
    let base = (x >= tx && x < tx + tw && y >= ty && y < ty + th) ? background[x, y, c] : full[x, y, c]
    let synthetic = max(0, min(1, empty[x, y, c] + columnDelta[x * 3 + c]))
    water[x, y, c] = base * fromFull + synthetic * (1 - fromFull)
} } }

// MARK: 3. The water surface strip.
// Only the parts of the strip that actually differ from the empty glass (the surface's edges and
// highlights) are kept; everything else is transparent so the words behind it stay visible.
let sx = 183, sy = 330, sw = 532, sh = 88   // photo rows 330...417, x 183...714
var surfaceAlpha = [Float](repeating: 0, count: sw * sh)
for y in 0..<sh { for x in 0..<sw {
    let px = sx + x, py = sy + y
    var d: Float = 0
    for c in 0..<3 { d += abs(full[px, py, c] - empty[px, py, c]) }
    // 0 below a difference of ~0.05 (JPEG noise / faint tint), fully opaque above ~0.30
    let t = max(0, min(1, (d - 0.05) / 0.25))
    surfaceAlpha[y * sw + x] = t * t * (3 - 2 * t)
} }
surfaceAlpha = blur(surfaceAlpha, w: sw, h: sh, radius: 1)
var surface = Bitmap(w: sw, h: sh)
for y in 0..<sh { for x in 0..<sw {
    let px = sx + x, py = sy + y
    var a = surfaceAlpha[y * sw + x]
    a *= max(0, min(1, Float(py - 330) / 8))           // soft top
    a *= max(0, min(1, Float(417 - py) / 6))           // soft bottom
    a *= max(0, min(1, Float(px - 186) / 7))           // left end (meniscus meets the wall ≈ 195)
    a *= max(0, min(1, Float(711 - px) / 7))           // right end (≈ 700)
    for c in 0..<3 { surface[x, y, c] = full[px, py, c] * a }   // premultiplied
    surface[x, y, 3] = a
} }

// MARK: 4. Canvas images (photo centred in 2400×1800, edges extended smoothly).
func canvas(_ photo: CGImage) -> CGImage {
    let W: CGFloat = 2400, H: CGFloat = 1800
    let ox: CGFloat = 752, oy: CGFloat = 300   // CI origin is bottom-left; symmetric here
    let p = CIImage(cgImage: photo).transformed(by: CGAffineTransform(translationX: ox, y: oy))
    let extended = p.clampedToExtent().applyingGaussianBlur(sigma: 30)
        .cropped(to: CGRect(x: 0, y: 0, width: W, height: H))
    let feather: CGFloat = 40
    let inset = p.extent.insetBy(dx: feather, dy: feather)
    let m = CIImage(color: .white).cropped(to: inset)
        .composited(over: CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: W, height: H)))
        .applyingGaussianBlur(sigma: Double(feather) / 2.5)
        .cropped(to: CGRect(x: 0, y: 0, width: W, height: H))
    let out = p.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: extended, kCIInputMaskImageKey: m])
        .cropped(to: CGRect(x: 0, y: 0, width: W, height: H))
    return CIContext(options: [.workingColorSpace: sRGB]).createCGImage(out, from: out.extent, format: .RGBA8, colorSpace: sRGB)!
}

save(canvas(load(fullPath)), "splash_photo.jpg", jpeg: true)
save(canvas(load(emptyPath)), "glass_background.jpg", jpeg: true)
// Water layer: only the inside of the glass is needed (photo x 180...716, y 150...960).
save(water.crop(x: 180, y: 150, w: 537, h: 811).cgImage(), "glass_water.jpg", jpeg: true)
save(surface.cgImage(), "glass_surface.png", jpeg: false)
save(words.cgImage(), "glass_words.png", jpeg: false)
