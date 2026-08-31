// Draws the app icon (1024x1024 PNG) — run via Scripts/make-icon.sh.
import AppKit

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon_1024.png"

let canvas = 1024
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvas,
    pixelsHigh: canvas,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .calibratedRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Could not create bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Rounded-rect plate (Big Sur style: 824pt plate on 1024 canvas).
let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
let platePath = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)

let gradient = NSGradient(
    starting: NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1),
    ending: NSColor(calibratedRed: 0.936, green: 0.936, blue: 0.960, alpha: 1)
)!
gradient.draw(in: platePath, angle: -90)

NSColor(calibratedWhite: 0.82, alpha: 1).setStroke()
platePath.lineWidth = 3
platePath.stroke()

// "M↓" mark, markdown-logo style, in indigo.
let indigo = NSColor(calibratedRed: 0.310, green: 0.275, blue: 0.898, alpha: 1)
let mark = NSAttributedString(
    string: "M↓",
    attributes: [
        .font: NSFont.systemFont(ofSize: 400, weight: .bold),
        .foregroundColor: indigo,
        .kern: 8,
    ]
)
let markSize = mark.size()
mark.draw(at: NSPoint(
    x: (CGFloat(canvas) - markSize.width) / 2,
    y: (CGFloat(canvas) - markSize.height) / 2 + 8
))

NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
