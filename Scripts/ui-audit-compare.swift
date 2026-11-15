// Compares two folders of interface audit captures, the baseline's and the
// candidate's (see Scripts/ui-audit.sh), and writes what changed.
//
//   ui-audit-compare <baseline folder> <candidate folder> <report folder>
//
// For every screen: the same, changed (with a picture of where), new or
// gone. The layout notes beside each capture (.txt) are compared line by
// line. Exits 0 whatever it finds: a difference is something to read, and
// whether it was meant is for whoever made the change to say.

import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// A channel may be this far off before a pixel counts as changed: the
/// window server's compositing of glass is not bit-exact between two runs.
let channelTolerance = 6
/// Changed pixels are gathered in cells of this many pixels, to tell
/// "one region" from "all over".
let cellSide = 64
/// Under this share of the picture a difference is listed apart: a caret
/// caught mid-blink is that small, and so is a real one-pixel slip, so it
/// is still to be looked at, after the large ones.
let smallShare = 0.1
let changedInk: (UInt8, UInt8, UInt8) = (255, 0, 170)

struct Pixels {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init?(contentsOf url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        width = image.width
        height = image.height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        if !drawn { return nil }
    }

    func write(to url: URL) {
        var copy = bytes
        copy.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                let image = context.makeImage(),
                let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
            else { return }
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
    }
}

struct Difference {
    var changedPixels = 0
    var cells = Set<Int>()
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    var picture: Pixels?
    var sizeNote: String?
}

func difference(between baseline: Pixels, and candidate: Pixels) -> Difference {
    var result = Difference()
    guard baseline.width == candidate.width, baseline.height == candidate.height else {
        result.sizeNote = "\(baseline.width)x\(baseline.height) → \(candidate.width)x\(candidate.height)"
        result.changedPixels = -1
        return result
    }
    var picture = candidate
    let width = baseline.width
    let cellsAcross = width / cellSide + 1
    for y in 0..<baseline.height {
        for x in 0..<width {
            let at = (y * width + x) * 4
            var changed = false
            for channel in 0..<4 where abs(Int(baseline.bytes[at + channel]) - Int(candidate.bytes[at + channel])) > channelTolerance {
                changed = true
            }
            if changed {
                result.changedPixels += 1
                result.cells.insert((y / cellSide) * cellsAcross + x / cellSide)
                result.minX = min(result.minX, x)
                result.maxX = max(result.maxX, x)
                result.minY = min(result.minY, y)
                result.maxY = max(result.maxY, y)
                picture.bytes[at] = changedInk.0
                picture.bytes[at + 1] = changedInk.1
                picture.bytes[at + 2] = changedInk.2
                picture.bytes[at + 3] = 255
            } else {
                // What stayed the same goes pale, so the ink stands out.
                for channel in 0..<3 {
                    picture.bytes[at + channel] = UInt8(255 - (255 - Int(picture.bytes[at + channel])) / 3)
                }
            }
        }
    }
    if result.changedPixels > 0 {
        result.picture = picture
    }
    return result
}

func files(in folder: URL, withExtension wanted: String) -> Set<String> {
    guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return [] }
    var found = Set<String>()
    let root = folder.standardizedFileURL.path
    for case let url as URL in walker where url.pathExtension == wanted {
        found.insert(String(url.standardizedFileURL.path.dropFirst(root.count + 1)))
    }
    return found
}

func lines(of url: URL) -> [String] {
    ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: ui-audit-compare <baseline> <candidate> <report>\n".utf8))
    exit(64)
}
let baselineFolder = URL(fileURLWithPath: arguments[1], isDirectory: true)
let candidateFolder = URL(fileURLWithPath: arguments[2], isDirectory: true)
let reportFolder = URL(fileURLWithPath: arguments[3], isDirectory: true)
try? FileManager.default.createDirectory(at: reportFolder, withIntermediateDirectories: true)

let baselineShots = files(in: baselineFolder, withExtension: "png")
let candidateShots = files(in: candidateFolder, withExtension: "png")

var same: [String] = []
var changed: [String] = []
var small: [String] = []
var layoutChanged: [String] = []
var report = ""

for name in baselineShots.union(candidateShots).sorted() {
    let screen = String(name.dropLast(4))
    guard baselineShots.contains(name) else {
        changed.append("- **\(screen)**: new, no baseline. `candidate/\(name)`")
        continue
    }
    guard candidateShots.contains(name) else {
        changed.append("- **\(screen)**: gone from the candidate. `baseline/\(name)`")
        continue
    }
    guard let baseline = Pixels(contentsOf: baselineFolder.appendingPathComponent(name)),
        let candidate = Pixels(contentsOf: candidateFolder.appendingPathComponent(name))
    else {
        changed.append("- **\(screen)**: could not be read")
        continue
    }
    let found = difference(between: baseline, and: candidate)
    if let sizeNote = found.sizeNote {
        changed.append("- **\(screen)**: the capture changed size, \(sizeNote)")
    } else if found.changedPixels == 0 {
        same.append(screen)
    } else {
        let pictureName = screen.replacingOccurrences(of: "/", with: "--") + ".diff.png"
        found.picture?.write(to: reportFolder.appendingPathComponent(pictureName))
        let share = Double(found.changedPixels) / Double(baseline.width * baseline.height) * 100
        let line =
            "- **\(screen)**: \(found.changedPixels) px (\(String(format: "%.2f", share))%) in \(found.cells.count) cell(s), "
                + "within x \(found.minX)…\(found.maxX), y \(found.minY)…\(found.maxY). `\(pictureName)`"
        if share < smallShare {
            small.append(line)
        } else {
            changed.append(line)
        }
    }

    let notes = screen + ".txt"
    let before = lines(of: baselineFolder.appendingPathComponent(notes))
    let after = lines(of: candidateFolder.appendingPathComponent(notes))
    if before != after {
        let gone = before.filter { !after.contains($0) }.map { "  - `- \($0)`" }
        let come = after.filter { !before.contains($0) }.map { "  - `+ \($0)`" }
        layoutChanged.append((["- **\(screen)**"] + gone + come).joined(separator: "\n"))
    }
}

report += "# Interface audit: candidate against baseline\n\n"
report += "- baseline: `\(baselineFolder.path)`\n- candidate: `\(candidateFolder.path)`\n"
report += "- \(same.count) screen(s) the same, \(changed.count) changed, \(small.count) with a small difference, \(layoutChanged.count) with layout notes changed\n\n"
report += "## Changed pictures\n\n" + (changed.isEmpty ? "none\n" : changed.joined(separator: "\n") + "\n")
report += "\n## Small differences (under \(smallShare)% of the picture)\n\n"
report += "A caret caught mid-blink looks like this, and so does a one-pixel slip: look before trusting.\n\n"
report += small.isEmpty ? "none\n" : small.joined(separator: "\n") + "\n"
report += "\n## Changed layout notes\n\n" + (layoutChanged.isEmpty ? "none\n" : layoutChanged.joined(separator: "\n") + "\n")
report += "\n## The same\n\n" + (same.isEmpty ? "none\n" : same.map { "- \($0)" }.joined(separator: "\n") + "\n")

let reportFile = reportFolder.appendingPathComponent("comparison.md")
try report.write(to: reportFile, atomically: true, encoding: .utf8)
print(report)
print("written to \(reportFile.path)")
