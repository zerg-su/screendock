import AppKit
import Foundation

// Renders AppIcon.iconset/ — a dark squircle with a frosted "bar" holding three
// colourful window tiles (the app's motif). Run via `make icon`.

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

let outDir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}
func rrect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func draw(px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext

    // Background squircle with a vertical graphite gradient.
    let inset = size * 0.055
    let bg = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    ctx.saveGState()
    ctx.addPath(rrect(bg, bg.width * 0.225))
    ctx.clip()
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [color(0.22, 0.23, 0.26), color(0.08, 0.08, 0.10)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: bg.midX, y: bg.maxY),
                           end: CGPoint(x: bg.midX, y: bg.minY), options: [])
    ctx.restoreGState()

    // The frosted "bar".
    let pillW = size * 0.66, pillH = size * 0.30
    let pill = CGRect(x: (size - pillW) / 2, y: (size - pillH) / 2, width: pillW, height: pillH)
    ctx.addPath(rrect(pill, pillH * 0.32))
    ctx.setFillColor(color(1, 1, 1, 0.16))
    ctx.fillPath()

    // Three window tiles.
    let tile = pillH * 0.60
    let gap = (pillW - 3 * tile) / 4
    let tileY = pill.midY - tile / 2
    let cols = [color(0.20, 0.55, 1.0), color(1.0, 0.55, 0.10), color(0.30, 0.80, 0.45)]
    for i in 0..<3 {
        let x = pill.minX + gap * CGFloat(i + 1) + tile * CGFloat(i)
        ctx.addPath(rrect(CGRect(x: x, y: tileY, width: tile, height: tile), tile * 0.26))
        ctx.setFillColor(cols[i])
        ctx.fillPath()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in sizes {
    try! draw(px: px).write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("wrote \(name).png (\(px)px)")
}
