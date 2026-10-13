import AppKit
import CoreGraphics
import Foundation

// Draws the Downarr app icon and writes a full .iconset. Every size is rendered from the vector
// description rather than downscaled from 1024, so the 16pt and 32pt versions stay crisp.

struct Palette {
    // Background: deep blue into violet, the same family as the app's accents.
    static let bgTop = CGColor(red: 0.29, green: 0.45, blue: 0.97, alpha: 1)
    static let bgBottom = CGColor(red: 0.40, green: 0.20, blue: 0.85, alpha: 1)
    static let glowTop = CGColor(red: 1, green: 1, blue: 1, alpha: 0.22)
    static let glowClear = CGColor(red: 1, green: 1, blue: 1, alpha: 0)
    static let vignette = CGColor(red: 0.04, green: 0.03, blue: 0.16, alpha: 0.38)
    static let markTop = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let markBottom = CGColor(red: 0.80, green: 0.92, blue: 1.0, alpha: 1)
    static let trayTint = CGColor(red: 0.21, green: 0.83, blue: 0.98, alpha: 1)   // Sonarr cyan
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
               colors: colors as CFArray,
               locations: locations)!
}

/// Renders the icon at `size` points into a bitmap (1x — callers pass the pixel size directly).
func renderIcon(size S: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(S)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    let cg = context.cgContext

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    // Work top-down so the geometry below reads like a design spec.
    cg.translateBy(x: 0, y: S)
    cg.scaleBy(x: 1, y: -1)
    cg.setAllowsAntialiasing(true)
    cg.interpolationQuality = .high

    // macOS icon grid: content inset from the canvas, generous continuous-corner radius.
    let inset = S * 0.094
    let side = S - inset * 2
    let radius = side * 0.225
    let body = CGRect(x: inset, y: inset, width: side, height: side)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow under the rounded square.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: S * 0.012),
                 blur: S * 0.03,
                 color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.30))
    cg.addPath(bodyPath)
    cg.setFillColor(Palette.bgTop)
    cg.fillPath()
    cg.restoreGState()

    // Base gradient.
    cg.saveGState()
    cg.addPath(bodyPath)
    cg.clip()
    cg.drawLinearGradient(gradient([Palette.bgTop, Palette.bgBottom], [0, 1]),
                          start: CGPoint(x: body.minX, y: body.minY),
                          end: CGPoint(x: body.maxX, y: body.maxY),
                          options: [])

    // Soft light from the top, and a darker floor so the mark has something to sit on.
    cg.drawLinearGradient(gradient([Palette.glowTop, Palette.glowClear], [0, 1]),
                          start: CGPoint(x: body.midX, y: body.minY),
                          end: CGPoint(x: body.midX, y: body.midY),
                          options: [])
    cg.drawLinearGradient(gradient([Palette.glowClear, Palette.vignette], [0, 1]),
                          start: CGPoint(x: body.midX, y: body.midY),
                          end: CGPoint(x: body.midX, y: body.maxY),
                          options: [])
    cg.restoreGState()

    // The download mark: shaft + chevron dropping into an open tray.
    let stroke = S * 0.115
    let trayStroke = S * 0.082

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: S * 0.012),
                 blur: S * 0.028,
                 color: CGColor(red: 0.05, green: 0.02, blue: 0.20, alpha: 0.45))

    // Clip to the mark, then paint it with a vertical gradient in one pass.
    let mark = CGMutablePath()
    let shaft = CGMutablePath()
    shaft.move(to: CGPoint(x: S * 0.5, y: S * 0.255))
    shaft.addLine(to: CGPoint(x: S * 0.5, y: S * 0.545))
    mark.addPath(shaft.copy(strokingWithWidth: stroke, lineCap: .round, lineJoin: .round, miterLimit: 10))

    let chevron = CGMutablePath()
    chevron.move(to: CGPoint(x: S * 0.335, y: S * 0.475))
    chevron.addLine(to: CGPoint(x: S * 0.5, y: S * 0.635))
    chevron.addLine(to: CGPoint(x: S * 0.665, y: S * 0.475))
    mark.addPath(chevron.copy(strokingWithWidth: stroke, lineCap: .round, lineJoin: .round, miterLimit: 10))

    cg.saveGState()
    cg.addPath(mark)
    cg.clip()
    cg.drawLinearGradient(gradient([Palette.markTop, Palette.markBottom], [0, 1]),
                          start: CGPoint(x: S * 0.5, y: S * 0.22),
                          end: CGPoint(x: S * 0.5, y: S * 0.66),
                          options: [])
    cg.restoreGState()

    // Tray: two uprights and a floor, in the app's cyan so the icon reads at a glance.
    let tray = CGMutablePath()
    tray.move(to: CGPoint(x: S * 0.285, y: S * 0.645))
    tray.addLine(to: CGPoint(x: S * 0.285, y: S * 0.755))
    tray.addLine(to: CGPoint(x: S * 0.715, y: S * 0.755))
    tray.addLine(to: CGPoint(x: S * 0.715, y: S * 0.645))
    let trayStroked = tray.copy(strokingWithWidth: trayStroke,
                                lineCap: .round, lineJoin: .round, miterLimit: 10)
    cg.addPath(trayStroked)
    cg.setFillColor(Palette.trayTint)
    cg.fillPath()
    cg.restoreGState()

    // Hairline rim so the icon keeps its edge on light and dark backgrounds.
    cg.addPath(bodyPath)
    cg.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    cg.setLineWidth(max(1, S * 0.004))
    cg.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Output

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/AppIcon.iconset"

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let entries: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for entry in entries {
    let rep = renderIcon(size: entry.pixels)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("failed to encode \(entry.name)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent(entry.name)
    try! data.write(to: url)
    print("wrote \(entry.name) (\(Int(entry.pixels))px)")
}
