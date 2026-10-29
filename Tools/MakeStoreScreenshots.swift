// Builds the App Store screenshots: headline + subtitle on the header's blue, a phone frame with a
// real app screen, water drops, and (optionally) feature badges.
//
//   swiftc -O Tools/MakeStoreScreenshots.swift -o /tmp/makeshots
//   /tmp/makeshots <header.png> <raw-screens-folder> <output-folder> [width height [device]]
//
// device: "iPhone" (default), "iPad" or "Duo" — sets the frame style and file names.
//
// The raw screens are iPhone 17 Pro simulator screenshots (1206×2622) named main40.png,
// main70.png, main80.png, settings.png, widgets.png and lockscreen.png.

import AppKit
import CoreImage

let args = CommandLine.arguments
let headerPath = args[1], rawDir = args[2], outDir = args[3]
let W = args.count > 5 ? Int(args[4])! : 1284
let H = args.count > 5 ? Int(args[5])! : 2778
let device = args.count > 6 ? args[6] : "iPhone"
let isPad = device == "iPad"
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func load(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}
let header = load(headerPath)!

/// Colour of one pixel of an image (x, y from the top-left).
func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> NSColor {
    var px = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: -x, y: -(img.height - 1 - y), width: img.width, height: img.height))
    return NSColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
}

// The header's plain blue (sampled to the right of the phone) — used as the background so the
// water drop cut from the header blends in seamlessly.
let blue = pixel(header, 3700, 300)

/// The isolated water drop from the header (on plain blue), with a soft round mask.
let drop: CGImage = {
    let crop = header.cropping(to: CGRect(x: 3140, y: 1050, width: 360, height: 360))!
    let ci = CIImage(cgImage: crop)
    let r: CGFloat = 175
    let mask = CIFilter(name: "CIRadialGradient", parameters: [
        "inputCenter": CIVector(x: 180, y: 180), "inputRadius0": r - 22, "inputRadius1": r,
        "inputColor0": CIColor.white, "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
    ])!.outputImage!.cropped(to: ci.extent)
    let out = ci.applyingFilter("CIBlendWithAlphaMask", parameters: [
        kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask,
    ])
    return CIContext().createCGImage(out, from: ci.extent, format: .RGBA8, colorSpace: sRGB)!
}()

struct Badge { let symbol: String; let label: String }

struct Shot {
    let file: String
    let screen: String
    let title: String
    let subtitle: String
    var tilt: CGFloat = 0          // degrees, positive = clockwise
    var badges: [Badge] = []
    /// Drops: (centre x, centre y) as fractions of the whole canvas, diameter as a fraction of
    /// one screenshot's width.
    var drops: [(CGFloat, CGFloat, CGFloat)] = []
    /// 2 = a panorama: one wide image split into two screenshots that join up side by side.
    var panels = 1
    /// Phone size (1 = standard), horizontal centre (fraction of the canvas) and top (layout units).
    var phoneScale: CGFloat = 1
    var phoneCenterX: CGFloat = 0.5
    var phoneTop: CGFloat? = nil
}

let shots: [Shot] = [
    // A two-screenshot panorama: the headline on the left, a big tilted phone across the seam.
    Shot(file: "1 Easy to use", screen: "main40", title: "Easy to use.",
         subtitle: "Tap the glass to log a drink.\nThat's it.", tilt: 14,
         drops: [(0.43, 0.07, 0.30), (0.08, 0.52, 0.20), (0.97, 0.20, 0.22), (0.92, 0.80, 0.16)],
         panels: 2, phoneScale: 1.42, phoneCenterX: 0.50, phoneTop: 820),
    Shot(file: "2 No ads", screen: "main70", title: "No ads. Ever.",
         subtitle: "Nothing between you and\nyour water.",
         drops: [(0.88, 0.07, 0.26), (0.04, 0.47, 0.15), (0.96, 0.74, 0.18)]),
    Shot(file: "3 No tracking", screen: "settings", title: "No tracking.",
         subtitle: "No accounts. Your data stays\non your device.",
         drops: [(0.90, 0.08, 0.25), (0.03, 0.55, 0.17), (0.96, 0.82, 0.15)]),
    Shot(file: "4 Beautiful design", screen: "main80", title: "Beautiful design.",
         subtitle: "Watch the glass fill as you\nreach your daily goal.",
         drops: [(0.91, 0.085, 0.24), (0.03, 0.66, 0.19), (0.96, 0.44, 0.13)]),
    Shot(file: "5 Widgets", screen: "widgets", title: "Widgets supported.",
         subtitle: "Add water right from your\nHome Screen.",
         drops: [(0.89, 0.075, 0.27), (0.04, 0.70, 0.16), (0.96, 0.52, 0.14)]),
    Shot(file: "6 Lock Screen", screen: "lockscreen", title: "Log a drink from the Lock Screen.",
         subtitle: "No need to unlock your phone.",
         drops: [(0.90, 0.08, 0.25), (0.04, 0.62, 0.17), (0.96, 0.84, 0.14)]),
]

// MARK: - Drawing

func roundedPath(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Draws text with its top-left at `origin` (in a flipped context).
@discardableResult
func drawText(_ s: String, at origin: CGPoint, font: NSFont, color: NSColor, lineHeight: CGFloat? = nil, width: CGFloat = 4000) -> CGFloat {
    let para = NSMutableParagraphStyle()
    if let lh = lineHeight { para.minimumLineHeight = lh; para.maximumLineHeight = lh }
    let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
    let rect = attr.boundingRect(with: CGSize(width: width, height: 4000), options: [.usesLineFragmentOrigin])
    attr.draw(with: CGRect(origin: origin, size: CGSize(width: width, height: rect.height)), options: [.usesLineFragmentOrigin])
    return rect.height
}

func render(_ shot: Shot) -> NSBitmapImageRep? {
    guard let screen = load("\(rawDir)/\(shot.screen).png") else {
        print("skip \(shot.file): missing \(shot.screen).png"); return nil
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W * shot.panels, pixelsHigh: H, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    // Flip so y grows downward, like the layouts above.
    ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
    // Tell AppKit (text and symbols) that this context is flipped too.
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    let w = CGFloat(W * shot.panels), h = CGFloat(H)
    let u = CGFloat(W) / 1284   // layout unit: everything is designed at 1284 wide

    // Background
    ctx.setFillColor(blue.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    if shot.panels > 1 {
        // Two big, faintly lighter circles sweeping across both panels tie them together.
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.06).cgColor)
        ctx.fillEllipse(in: CGRect(x: w * 0.30, y: -h * 0.35, width: h * 1.05, height: h * 1.05))
        ctx.fillEllipse(in: CGRect(x: -h * 0.55, y: h * 0.55, width: h * 0.95, height: h * 0.95))
    }

    func drawDrop(_ d: (CGFloat, CGFloat, CGFloat)) {
        let size = d.2 * CGFloat(W)
        let r = CGRect(x: d.0 * w - size / 2, y: d.1 * h - size / 2, width: size, height: size)
        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.maxY); ctx.scaleBy(x: 1, y: -1)   // draw image upright
        ctx.draw(drop, in: CGRect(origin: .zero, size: r.size))
        ctx.restoreGState()
    }

    // The large top drop first, so the headline sits over it.
    for d in shot.drops where d.1 < 0.2 { drawDrop(d) }   // top drop, behind the text

    // Headline + subtitle, left-aligned like the header.
    let margin = 96 * u
    var y = 150 * u
    let titleFont = NSFont.systemFont(ofSize: 132 * u, weight: .heavy)
    y += drawText(shot.title, at: CGPoint(x: margin - 6 * u, y: y), font: titleFont, color: .white,
                  lineHeight: 160 * u, width: CGFloat(W) - margin * 2)
    y += 14 * u
    let subFont = NSFont.systemFont(ofSize: 62 * u, weight: .regular)
    let subtitle = isPad ? shot.subtitle.replacingOccurrences(of: "your phone", with: "your iPad") : shot.subtitle
    y += drawText(subtitle, at: CGPoint(x: margin, y: y), font: subFont, color: NSColor.white.withAlphaComponent(0.92),
                  lineHeight: 78 * u)

    // Badges (white line icon + bold label), in a row under the subtitle.
    if !shot.badges.isEmpty {
        y += 46 * u
        var x = margin
        for b in shot.badges {
            let cfg = NSImage.SymbolConfiguration(pointSize: 54 * u, weight: .semibold)
                .applying(.init(paletteColors: [.white]))
            if let sym = NSImage(systemSymbolName: b.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                let s = sym.size
                sym.draw(in: CGRect(x: x, y: y + (64 * u - s.height) / 2, width: s.width, height: s.height),
                         from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                x += s.width + 18 * u
            }
            let lf = NSFont.systemFont(ofSize: 46 * u, weight: .bold)
            let lw = NSAttributedString(string: b.label, attributes: [.font: lf]).size().width
            drawText(b.label, at: CGPoint(x: x, y: y + 4 * u), font: lf, color: .white)
            x += lw + 56 * u
        }
        y += 64 * u
    }

    // Phone: the screen inside a dark bezel, centred, bottom running off the image.
    // The iPad's canvas is nearly square, so its device is drawn smaller to show the whole iPad.
    // The folded Duo's canvas is shorter than the iPhone's, so its panorama phone is smaller too.
    let isDuo = device == "Duo"
    let phoneScale = isPad ? (shot.panels > 1 ? 1.12 : 1) : (isDuo && shot.panels > 1 ? 1.12 : shot.phoneScale)
    let panoTop = isPad ? 600 : (isDuo ? 640 : shot.phoneTop)
    let phoneTop = (shot.panels > 1 ? panoTop : nil).map { $0 * u } ?? max(y + 70 * u, (isPad ? 640 : 700) * u)
    let pu = u * phoneScale   // the device's own unit, so its details scale with it
    let screenW = (isPad ? 740 : (isDuo ? 880 : 960)) * pu
    let screenH = screenW * CGFloat(screen.height) / CGFloat(screen.width)
    let bezel = (isPad ? 34 : 30) * pu
    let outerRadius = (isPad ? 70 : 150) * pu, screenRadius = (isPad ? 40 : 122) * pu
    let phone = CGRect(x: shot.phoneCenterX * w - screenW / 2 - bezel, y: phoneTop,
                       width: screenW + bezel * 2, height: screenH + bezel * 2)
    let screenRect = phone.insetBy(dx: bezel, dy: bezel)

    ctx.saveGState()
    ctx.translateBy(x: phone.midX, y: phone.midY)
    ctx.rotate(by: shot.tilt * .pi / 180)
    ctx.translateBy(x: -phone.midX, y: -phone.midY)
    // Shadow
    ctx.setShadow(offset: CGSize(width: 0, height: 40 * pu), blur: 90 * pu, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(roundedPath(phone, outerRadius)); ctx.setFillColor(NSColor(white: 0.08, alpha: 1).cgColor); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    // Metal edge
    ctx.addPath(roundedPath(phone.insetBy(dx: 2 * pu, dy: 2 * pu), outerRadius - 2 * pu))
    ctx.setStrokeColor(NSColor(white: 0.42, alpha: 1).cgColor); ctx.setLineWidth(5 * pu); ctx.strokePath()
    // Side buttons
    ctx.setFillColor(NSColor(white: 0.18, alpha: 1).cgColor)
    let left = phone.minX - 7 * pu, right = phone.maxX, top = phone.minY
    let buttons: [(CGFloat, CGFloat, CGFloat)] = [
        (left, top + 330 * pu, 110 * pu), (left, top + 480 * pu, 170 * pu),
        (left, top + 680 * pu, 170 * pu), (right, top + 520 * pu, 260 * pu),
    ]
    for (bx, by, bh) in (isPad ? [] : buttons) {
        ctx.addPath(roundedPath(CGRect(x: bx, y: by, width: 7 * pu, height: bh), 3 * pu)); ctx.fillPath()
    }
    // Screen
    ctx.saveGState()
    ctx.addPath(roundedPath(screenRect, screenRadius)); ctx.clip()
    ctx.translateBy(x: screenRect.minX, y: screenRect.maxY); ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.draw(screen, in: CGRect(origin: .zero, size: screenRect.size))
    ctx.restoreGState()
    // Dynamic Island
    if device == "iPhone" {
        let island = CGRect(x: screenRect.midX - 150 * pu, y: screenRect.minY + 30 * pu, width: 300 * pu, height: 88 * pu)
        ctx.addPath(roundedPath(island, 44 * pu)); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    }
    ctx.restoreGState()

    // The other drops float in front of the phone.
    for d in shot.drops where d.1 >= 0.2 { drawDrop(d) }

    NSGraphicsContext.current = nil
    return rep
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
func save(_ image: CGImage, _ path: String) {
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}
for shot in shots {
    guard let rep = render(shot), let image = rep.cgImage else { continue }
    if shot.panels == 1 {
        save(image, "\(outDir)/\(device) \(W)x\(H) - \(shot.file).png")
    } else {
        // Split the panorama into consecutive screenshots ("1a", "1b"), plus the joined preview.
        let number = shot.file.prefix { $0 != " " }, name = shot.file.drop { $0 != " " }
        for i in 0..<shot.panels {
            let part = image.cropping(to: CGRect(x: i * W, y: 0, width: W, height: H))!
            let letter = Character(UnicodeScalar(UInt8(97 + i)))
            save(part, "\(outDir)/\(device) \(W)x\(H) - \(number)\(letter)\(name).png")
        }
        save(image, "\(outDir)/Preview - \(device) \(shot.file) (joined).png")
    }
}
