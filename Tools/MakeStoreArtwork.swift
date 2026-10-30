// Builds the iOS 27 App Store creative assets: the product page header (3840×1646) and the
// search results image (3840×2560). Everything that matters stays inside Apple's centred safe
// areas (header x 1097–2743, y 493–1154; search x 836–3004, y 765–1795).
//
//   swiftc -O Tools/MakeStoreArtwork.swift -o /tmp/makeart
//   /tmp/makeart <splash_photo.jpg> <drop-source.png> <raw-screen.png> <output-folder> [--guides]
//
// drop-source is the old 3840×1646 header (the water drop is cut from it, as in
// MakeStoreScreenshots.swift). raw-screen is an iPhone 17 Pro screenshot (1206×2622).
// --guides also writes copies with the safe area outlined, for checking only.

import AppKit
import CoreImage

let args = CommandLine.arguments
let photoPath = args[1], dropSourcePath = args[2], screenPath = args[3], outDir = args[4]
let drawGuides = args.contains("--guides")
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let ciContext = CIContext(options: [.workingColorSpace: sRGB])

func load(_ path: String) -> CGImage {
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}
let photo = load(photoPath), dropSource = load(dropSourcePath), screen = load(screenPath)

/// Colour of one pixel of an image (x, y from the top-left), as RGB components.
func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> (CGFloat, CGFloat, CGFloat) {
    var px = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: -x, y: -(img.height - 1 - y), width: img.width, height: img.height))
    return (CGFloat(px[0]) / 255, CGFloat(px[1]) / 255, CGFloat(px[2]) / 255)
}

/// The water drop cut from the old header, on that header's plain blue.
let dropCrop = dropSource.cropping(to: CGRect(x: 3140, y: 1050, width: 360, height: 360))!
let dropBlue = pixel(dropCrop, 6, 6)

/// The drop recoloured so its surrounding blue matches `target` (the background where it will
/// sit), with a soft round mask — so it blends in without a ring. `blur` puts it out of focus.
func makeDrop(on target: (CGFloat, CGFloat, CGFloat), blur: CGFloat) -> CGImage {
    let ratio = { (t: CGFloat, s: CGFloat) in s > 0.01 ? t / s : 1 }
    let ci = CIImage(cgImage: dropCrop).applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: ratio(target.0, dropBlue.0), y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: ratio(target.1, dropBlue.1), z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: ratio(target.2, dropBlue.2), w: 0),
    ])
    let r: CGFloat = 175
    let mask = CIFilter(name: "CIRadialGradient", parameters: [
        "inputCenter": CIVector(x: 180, y: 180), "inputRadius0": r - 30, "inputRadius1": r,
        "inputColor0": CIColor.white, "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
    ])!.outputImage!.cropped(to: ci.extent)
    var out = ci.applyingFilter("CIBlendWithAlphaMask", parameters: [
        kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask,
    ]).cropped(to: ci.extent)
    // Padded by 60 px on each side so a blurred drop isn't clipped.
    out = out.transformed(by: CGAffineTransform(translationX: 60, y: 60))
    if blur > 0 { out = out.applyingGaussianBlur(sigma: blur) }
    return ciContext.createCGImage(out, from: CGRect(x: 0, y: 0, width: 480, height: 480), format: .RGBA8, colorSpace: sRGB)!
}

/// An opaque, top-left-origin drawing context.
func makeContext(_ w: Int, _ h: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    return ctx
}

/// Draws a CGImage upright into a rect given in top-left coordinates.
func drawImage(_ ctx: CGContext, _ img: CGImage, in r: CGRect) {
    ctx.saveGState()
    ctx.translateBy(x: r.minX, y: r.maxY); ctx.scaleBy(x: 1, y: -1)
    ctx.draw(img, in: CGRect(origin: .zero, size: r.size))
    ctx.restoreGState()
}

/// A drop centred at (x, y) with diameter d, colour-matched to `bg` at that spot.
func drawDrop(_ ctx: CGContext, on bg: CGImage, _ x: CGFloat, _ y: CGFloat, _ d: CGFloat, blurred: Bool = false) {
    let target = pixel(bg, Int(x.clamped(0, CGFloat(bg.width - 1))), Int(y.clamped(0, CGFloat(bg.height - 1))))
    // Blur is set in the drop's own 360 px space, so it scales with the drop.
    let img = makeDrop(on: target, blur: blurred ? 9 : 0)
    let pad = d * 60 / 360
    drawImage(ctx, img, in: CGRect(x: x - d / 2 - pad, y: y - d / 2 - pad, width: d + pad * 2, height: d + pad * 2))
}

extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lo), hi) }
}

/// A soft radial blue sampled from the splash photo: its light centre fading to its darker edge.
func radialBackground(width w: Int, height h: Int, center: CGPoint) -> CGImage {
    let ctx = makeContext(w, h)
    let light = pixel(photo, 1200, 250), dark = pixel(photo, 40, 40)
    let gradient = CGGradient(colorsSpace: sRGB, colors: [
        CGColor(srgbRed: light.0, green: light.1, blue: light.2, alpha: 1),
        CGColor(srgbRed: dark.0, green: dark.1, blue: dark.2, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                           endRadius: CGFloat(max(w, h)) * 0.75, options: [.drawsAfterEndLocation])
    return ctx.makeImage()!
}

func roundedPath(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func outlineSafeArea(_ ctx: CGContext, _ r: CGRect) {
    ctx.setStrokeColor(NSColor.systemRed.cgColor); ctx.setLineWidth(6)
    ctx.setLineDash(phase: 0, lengths: [30, 18]); ctx.stroke(r); ctx.setLineDash(phase: 0, lengths: [])
}

func save(_ ctx: CGContext, _ name: String) {
    let url = URL(fileURLWithPath: "\(outDir)/\(name)")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(url.path)")
}

/// The splash photo scaled and placed so its glass lands at `glassCenter` with `glassHeight`,
/// on a background made by stretching the photo's own edges and blurring them, so the photo
/// blends into a canvas of any shape without a visible seam.
func photoBackground(width w: Int, height h: Int, glassCenter: CGPoint, glassHeight: CGFloat) -> CGImage {
    // The glass in the 2400×1800 photo: centre (1200, 890), about 980 px tall (rim to base).
    let s = glassHeight / 980
    let p = CGRect(x: (glassCenter.x - 1200 * s).rounded(), y: (glassCenter.y - 890 * s).rounded(),
                   width: (CGFloat(photo.width) * s).rounded(), height: (CGFloat(photo.height) * s).rounded())
    // Stretch the photo's outermost rows and columns out to the canvas edges (Core Image's
    // clampedToExtent() proved unreliable here), then blur that to hide the streaks.
    let stretch = makeContext(w, h)
    let pw = photo.width, phh = photo.height
    let strips: [(CGRect, CGRect)] = [
        (CGRect(x: 0, y: 0, width: 2, height: phh), CGRect(x: 0, y: p.minY, width: p.minX + 1, height: p.height)),
        (CGRect(x: pw - 2, y: 0, width: 2, height: phh), CGRect(x: p.maxX - 1, y: p.minY, width: CGFloat(w) - p.maxX + 1, height: p.height)),
        (CGRect(x: 0, y: 0, width: pw, height: 2), CGRect(x: p.minX, y: 0, width: p.width, height: p.minY + 1)),
        (CGRect(x: 0, y: phh - 2, width: pw, height: 2), CGRect(x: p.minX, y: p.maxY - 1, width: p.width, height: CGFloat(h) - p.maxY + 1)),
        (CGRect(x: 0, y: 0, width: 2, height: 2), CGRect(x: 0, y: 0, width: p.minX + 1, height: p.minY + 1)),
        (CGRect(x: pw - 2, y: 0, width: 2, height: 2), CGRect(x: p.maxX - 1, y: 0, width: CGFloat(w) - p.maxX + 1, height: p.minY + 1)),
        (CGRect(x: 0, y: phh - 2, width: 2, height: 2), CGRect(x: 0, y: p.maxY - 1, width: p.minX + 1, height: CGFloat(h) - p.maxY + 1)),
        (CGRect(x: pw - 2, y: phh - 2, width: 2, height: 2), CGRect(x: p.maxX - 1, y: p.maxY - 1, width: CGFloat(w) - p.maxX + 1, height: CGFloat(h) - p.maxY + 1)),
    ]
    for (src, dst) in strips where dst.width > 0 && dst.height > 0 {
        drawImage(stretch, photo.cropping(to: src)!, in: dst)
    }
    drawImage(stretch, photo, in: p)
    let canvas = CGRect(x: 0, y: 0, width: w, height: h)
    let stretched = CIImage(cgImage: stretch.makeImage()!)
    let extended = stretched.clampedToExtent().applyingGaussianBlur(sigma: 60).cropped(to: canvas)
    // Core Image is bottom-left origin.
    let placed = stretched.cropped(to: CGRect(x: p.minX, y: CGFloat(h) - p.maxY, width: p.width, height: p.height))
    let feather: CGFloat = 160
    let maskRect = placed.extent.insetBy(dx: feather * 1.2, dy: feather * 1.2)
    let mask = CIImage(color: .white).cropped(to: maskRect)
        .composited(over: CIImage(color: .black).cropped(to: canvas))
        .applyingGaussianBlur(sigma: feather / 2).cropped(to: canvas)
    let blended = placed.applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: extended, kCIInputMaskImageKey: mask,
    ]).cropped(to: canvas)
    return ciContext.createCGImage(blended, from: canvas, format: .RGBA8, colorSpace: sRGB)!
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// MARK: - Product page header (3840×1646)
//
// One clear idea, no words (so the one header works in every language): the hero glass,
// centred in the safe area, with drops scattered towards the edges. The bottom is left calm
// because the App Store lays the icon, name and Get button over it.

do {
    let W = 3840, H = 1646
    let safe = CGRect(x: 1097, y: 493, width: 1646, height: 661)
    let ctx = makeContext(W, H)
    let bg = photoBackground(width: W, height: H, glassCenter: CGPoint(x: safe.midX, y: safe.midY), glassHeight: 640)
    drawImage(ctx, bg, in: CGRect(x: 0, y: 0, width: W, height: H))
    // Drops: sharp ones near the glass, soft out-of-focus ones at the far edges.
    for (x, y, d, blurred) in [(560.0, 330.0, 320.0, true), (1420, 380, 130, false), (2470, 560, 190, false),
                               (3300, 360, 400, true), (2900, 1120, 110, false), (3650, 1320, 240, true)] {
        drawDrop(ctx, on: bg, x, y, d, blurred: blurred)
    }
    save(ctx, "Header 3840x1646.png")
    if drawGuides { outlineSafeArea(ctx, safe); save(ctx, "Header 3840x1646 (safe area guide).png") }
}

// MARK: - Search results (3840×2560)
//
// Shown only ~365 pt wide, so: one big headline and one big, upright phone showing the real app.

do {
    let W = 3840, H = 2560
    let safe = CGRect(x: 836, y: 765, width: 2168, height: 1030)
    let ctx = makeContext(W, H)
    // The header's photographic blue, lit from behind the phone.
    let bg = radialBackground(width: W, height: H, center: CGPoint(x: 2400, y: 1100))
    drawImage(ctx, bg, in: CGRect(x: 0, y: 0, width: W, height: H))

    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

    // Phone (right half of the safe area). The glass on its screen sits inside the safe area;
    // the top and bottom of the phone can run past it.
    let screenW: CGFloat = 860
    let screenH = screenW * CGFloat(screen.height) / CGFloat(screen.width)
    let pu = screenW / 960       // same proportions as MakeStoreScreenshots.swift
    let bezel = 30 * pu
    let phone = CGRect(x: 2540 - screenW / 2 - bezel, y: 340, width: screenW + bezel * 2, height: screenH + bezel * 2)
    let screenRect = phone.insetBy(dx: bezel, dy: bezel)
    drawDrop(ctx, on: bg, 3330, 470, 330)                // behind the phone
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 50 * pu), blur: 120 * pu, color: NSColor.black.withAlphaComponent(0.38).cgColor)
    ctx.addPath(roundedPath(phone, 150 * pu)); ctx.setFillColor(NSColor(white: 0.08, alpha: 1).cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(roundedPath(phone.insetBy(dx: 2 * pu, dy: 2 * pu), 148 * pu))
    ctx.setStrokeColor(NSColor(white: 0.42, alpha: 1).cgColor); ctx.setLineWidth(5 * pu); ctx.strokePath()
    ctx.setFillColor(NSColor(white: 0.18, alpha: 1).cgColor)
    for (bx, by, bh) in [(phone.minX - 7 * pu, 330 * pu, 110 * pu), (phone.minX - 7 * pu, 480 * pu, 170 * pu),
                         (phone.minX - 7 * pu, 680 * pu, 170 * pu), (phone.maxX, 520 * pu, 260 * pu)] {
        ctx.addPath(roundedPath(CGRect(x: bx, y: phone.minY + by, width: 7 * pu, height: bh), 3 * pu)); ctx.fillPath()
    }
    ctx.saveGState()
    ctx.addPath(roundedPath(screenRect, 122 * pu)); ctx.clip()
    drawImage(ctx, screen, in: screenRect)
    ctx.restoreGState()
    let island = CGRect(x: screenRect.midX - 150 * pu, y: screenRect.minY + 30 * pu, width: 300 * pu, height: 88 * pu)
    ctx.addPath(roundedPath(island, 44 * pu)); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()

    // Headline + subtitle, left half of the safe area, vertically centred on it.
    let textX = safe.minX + 20, textW: CGFloat = 1180
    let title = NSAttributedString(string: "One tap.\nOne glass.", attributes: [
        .font: NSFont.systemFont(ofSize: 220, weight: .heavy), .foregroundColor: NSColor.white,
        .paragraphStyle: { let p = NSMutableParagraphStyle(); p.minimumLineHeight = 236; p.maximumLineHeight = 236; return p }(),
        .kern: -4,
    ])
    let subtitle = NSAttributedString(string: "No ads. No tracking.", attributes: [
        .font: NSFont.systemFont(ofSize: 104, weight: .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.9),
    ])
    let opts: NSString.DrawingOptions = [.usesLineFragmentOrigin]
    let th = title.boundingRect(with: CGSize(width: textW, height: 2000), options: opts).height
    let sh = subtitle.boundingRect(with: CGSize(width: textW, height: 2000), options: opts).height
    let gap: CGFloat = 50
    var y = safe.midY - (th + gap + sh) / 2
    title.draw(with: CGRect(x: textX, y: y, width: textW, height: th), options: opts)
    y += th + gap
    subtitle.draw(with: CGRect(x: textX + 6, y: y, width: textW, height: sh), options: opts)

    // Drops in front, outside the safe area.
    drawDrop(ctx, on: bg, 520, 470, 280, blurred: true)
    drawDrop(ctx, on: bg, 1850, 2080, 190)
    drawDrop(ctx, on: bg, 3480, 1980, 380, blurred: true)
    NSGraphicsContext.current = nil

    save(ctx, "Search Results 3840x2560.png")
    if drawGuides { outlineSafeArea(ctx, safe); save(ctx, "Search Results 3840x2560 (safe area guide).png") }
}
