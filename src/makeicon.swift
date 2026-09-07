// Renders AppIcon.iconset for TeamsAwake: a white bolt-in-circle on an
// indigo-violet squircle. Same mark as the menu-bar glyph, in colour.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let boltPoints: [(CGFloat, CGFloat)] = [   // 24-unit grid, y-down (SVG style)
    (13.4, 6.2), (8.8, 13.6), (11.9, 13.6), (10.9, 18.0), (15.5, 10.6), (12.4, 10.6),
]

func render(_ S: CGFloat) -> CGImage? {
    let px = Int(S)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: px, height: px,
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // Squircle plate, inset like a standard macOS icon.
    let inset = S * 0.098
    let plate = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
    let radius = plate.width * 0.225
    let path = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius,
                      transform: nil)

    // Solid fill first, purely to cast the shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.022,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.30))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(srgbRed: 0.36, green: 0.31, blue: 0.85, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Gradient over the plate.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let top = CGColor(srgbRed: 0.36, green: 0.31, blue: 0.90, alpha: 1)
    let bot = CGColor(srgbRed: 0.55, green: 0.27, blue: 0.88, alpha: 1)
    let grad = CGGradient(colorsSpace: cs, colors: [top, bot] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: plate.maxY),
                           end: CGPoint(x: 0, y: plate.minY), options: [])
    // Soft top highlight so it is not visually dead flat.
    let hi = CGGradient(colorsSpace: cs,
                        colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16),
                                 CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(hi, start: CGPoint(x: 0, y: plate.maxY),
                           end: CGPoint(x: 0, y: plate.midY), options: [])
    ctx.restoreGState()

    // Glyph: map the 24-unit grid into a centred box, flipping y.
    let G = plate.width * 0.58
    let ox = plate.midX - G / 2, oy = plate.midY - G / 2
    let k = G / 24
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: ox + x * k, y: oy + (24 - y) * k)
    }

    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(2 * k)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)

    let c = p(12, 12)
    ctx.addArc(center: c, radius: 9 * k, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    ctx.move(to: p(boltPoints[0].0, boltPoints[0].1))
    for pt in boltPoints.dropFirst() { ctx.addLine(to: p(pt.0, pt.1)) }
    ctx.closePath()
    ctx.fillPath()

    return ctx.makeImage()
}

func write(_ img: CGImage, to url: URL) {
    guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("destination") }
    CGImageDestinationAddImage(d, img, nil)
    CGImageDestinationFinalize(d)
}

// Output directory, so the build script can decide where this lands.
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let set = URL(fileURLWithPath: outDir)
try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

let variants: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in variants {
    guard let img = render(size) else { fatalError("render \(name)") }
    write(img, to: set.appendingPathComponent("\(name).png"))
}
print("iconset written: \(variants.count) images")
