// Draws the disk image's background, Resources/DMG/background.tiff: the
// arrow from Lauda to the Applications folder, where the icons sit in the
// window that make-dmg.sh lays out (660 by 400 points, the icons centred
// 170 points down, at 180 and 480 across). Drawn at 1x and 2x into one
// TIFF, so the Finder picks the sharp one on a Retina screen.
//   swift Scripts/make-dmg-background.swift Resources/DMG/background.tiff
import AppKit

let size = CGSize(width: 660, height: 400)
let iconCentres = (lauda: CGPoint(x: 180, y: 170), applications: CGPoint(x: 480, y: 170))
let iconSide: CGFloat = 128

func draw(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    // Drawn in points: the context scales by the rep's pixels per point itself.
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    // The window's light grey, a shade off white so the icons' white edges read.
    NSColor(white: 0.965, alpha: 1).setFill()
    CGRect(origin: .zero, size: size).fill()

    // The arrow, between the icons, in the Finder's top-down coordinates
    // turned into this bitmap's bottom-up ones.
    let y = size.height - iconCentres.lauda.y
    let start = CGPoint(x: iconCentres.lauda.x + iconSide / 2 + 22, y: y)
    let end = CGPoint(x: iconCentres.applications.x - iconSide / 2 - 22, y: y)
    let ink = NSColor(white: 0.62, alpha: 1)
    ink.setStroke()
    let shaft = NSBezierPath()
    shaft.lineWidth = 6
    shaft.lineCapStyle = .round
    shaft.move(to: start)
    shaft.line(to: CGPoint(x: end.x - 3, y: y))
    shaft.stroke()
    let head = NSBezierPath()
    head.lineWidth = 6
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.move(to: CGPoint(x: end.x - 30, y: y + 18))
    head.line(to: end)
    head.line(to: CGPoint(x: end.x - 30, y: y - 18))
    head.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

guard CommandLine.arguments.count > 1 else {
    print("usage: swift Scripts/make-dmg-background.swift <output.tiff>")
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let pages = [draw(scale: 1), draw(scale: 2)]
let data = NSBitmapImageRep.representationOfImageReps(
    in: pages, using: .tiff, properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw.rawValue])!
try data.write(to: output)
print("OK: \(output.path)")
