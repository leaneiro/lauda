// Draws the disk image's background, Resources/DMG/background.tiff: three
// chevrons from Lauda to the Applications folder, in the icon's greys and
// darkening towards the folder up to the L's black, on white, where the icons
// sit in the window that make-dmg.sh lays out (660 by 400 points, the
// icons centred 170 points down, at 180 and 480 across). Drawn at 1x and
// 2x into one TIFF, so the Finder picks the sharp one on a Retina screen.
//   swift Scripts/make-dmg-background.swift Resources/DMG/background.tiff
import AppKit

let size = CGSize(width: 660, height: 400)
let iconCentres = (lauda: CGPoint(x: 180, y: 170), applications: CGPoint(x: 480, y: 170))
// The icon's own colours: the grey of its lines and the black of its L.
let grey = NSColor(srgbRed: 0.780, green: 0.776, blue: 0.753, alpha: 1)
let black = NSColor(srgbRed: 0.102, green: 0.098, blue: 0.086, alpha: 1)

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
    // White, like the icon's and the Finder's own window: a strip the
    // picture leaves uncovered at the window's edge does not show.
    NSColor.white.setFill()
    CGRect(origin: .zero, size: size).fill()

    // The chevrons, on the icons' centre line, in the Finder's top-down
    // coordinates turned into this bitmap's bottom-up ones.
    let y = size.height - iconCentres.lauda.y
    let middle = (iconCentres.lauda.x + iconCentres.applications.x) / 2
    let step: CGFloat = 42
    let height: CGFloat = 44
    let depth: CGFloat = 20
    let inks = [grey, grey.blended(withFraction: 0.5, of: black)!, black]
    for (index, ink) in inks.enumerated() {
        let x = middle + (CGFloat(index) - 1) * step
        let chevron = NSBezierPath()
        chevron.lineWidth = 7
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        chevron.move(to: CGPoint(x: x - depth / 2, y: y + height / 2))
        chevron.line(to: CGPoint(x: x + depth / 2, y: y))
        chevron.line(to: CGPoint(x: x - depth / 2, y: y - height / 2))
        ink.setStroke()
        chevron.stroke()
    }
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
