#!/usr/bin/env swift
//
// Builds the QuickFiles app icon and menu-bar glyph from the Flaticon source artwork.
//
// Icon artwork: "file-and-folder" by Wyasa.Design – Flaticon
// https://www.flaticon.com/kr/free-icons/  (free license, attribution required)
//
// Usage (from the repository root):
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift Design/AppIcon/compose_icon.swift

import AppKit
import CoreGraphics
import Foundation

// MARK: - Tunables

/// Tile colour (#4ECDC4). Set `drawsTile` to false for a transparent icon (the black line art
/// then disappears on a dark Dock, so the tile is on by default).
let drawsTile = true
let tileColor = CGColor(red: 0x4E / 255, green: 0xCD / 255, blue: 0xC4 / 255, alpha: 1)
/// Sheen/shade/rim overlay on the tile. Set to false for a completely flat tile.
let tileFinish = true
let inkColor = CGColor(red: 0x0F / 255, green: 0x3B / 255, blue: 0x38 / 255, alpha: 1)  // dark teal #0F3B38 (white: CGColor(gray: 1, alpha: 1))
/// Glyph size as a fraction of the 1024 canvas (Apple's grid uses an 824pt tile with 100pt margins).
let glyphFraction: CGFloat = 0.56

// MARK: - Paths

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("Design/AppIcon/Source/flaticon-file-and-folder-9099437.png")
let appIconSet = root.appendingPathComponent("QuickFiles/Assets.xcassets/AppIcon.appiconset")
let menuBarSet = root.appendingPathComponent("QuickFiles/Assets.xcassets/MenuBarIcon.imageset")
let previewDir = root.appendingPathComponent("Design/AppIcon")

// MARK: - Source

func loadSource() -> CGImage {
    guard let image = NSImage(contentsOf: sourceURL),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("Cannot read \(sourceURL.path)")
    }
    return cgImage
}

/// Bounding box of non-transparent pixels, in CGImage (top-left origin) pixel coordinates.
func opaqueBounds(of image: CGImage) -> CGRect {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0..<height {
        for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    precondition(maxX >= 0, "Source image is fully transparent")
    // Row 0 of a bitmap context's backing store is the top row, matching CGImage.cropping's origin.
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let source = loadSource()
let glyph = source.cropping(to: opaqueBounds(of: source))!

// MARK: - Rendering

/// Light overlay "mask" on the flat tile: a top sheen, a soft top-left glow, a gentle shade
/// toward the bottom, and a thin bright rim — all clipped to the tile so the base colour stays
/// recognisably `tileColor` while gaining depth.
func drawTileFinish(in context: CGContext, tilePath: CGPath, pixelSize: Int) {
    let space = CGColorSpaceCreateDeviceRGB()
    func gradient(_ stops: [(CGFloat, CGFloat, CGFloat)]) -> CGGradient {
        // (gray, alpha, location)
        CGGradient(
            colorsSpace: space,
            colors: stops.map { CGColor(gray: $0.0, alpha: $0.1) } as CFArray,
            locations: stops.map(\.2)
        )!
    }

    context.saveGState()
    context.addPath(tilePath)
    context.clip()

    // Top sheen fading out before the middle (y-up: 924 is the top edge of the tile).
    // Kept light so the white doesn't wash out the base colour.
    context.drawLinearGradient(
        gradient([(1, 0.14, 0), (1, 0.03, 0.45), (1, 0, 1)]),
        start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 520), options: []
    )
    // Shade toward the bottom with a deeper, saturated teal (not grey/black) so the
    // colour gets richer instead of muddier.
    let deepTeal = CGColor(red: 0x1F / 255, green: 0xB0 / 255, blue: 0xA6 / 255, alpha: 1)
    let shade = CGGradient(
        colorsSpace: space,
        colors: [deepTeal.copy(alpha: 0)!, deepTeal.copy(alpha: 0.55)!] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        shade, start: CGPoint(x: 512, y: 600), end: CGPoint(x: 512, y: 100), options: []
    )
    // Soft glow from the upper-left, like a light source.
    context.drawRadialGradient(
        gradient([(1, 0.10, 0), (1, 0, 1)]),
        startCenter: CGPoint(x: 290, y: 860), startRadius: 0,
        endCenter: CGPoint(x: 290, y: 860), endRadius: 560, options: []
    )
    context.restoreGState()

    // Thin bright inner rim; skipped at tiny sizes where it would just blur the edge.
    if pixelSize >= 64 {
        context.saveGState()
        context.addPath(tilePath)
        context.clip()
        context.addPath(tilePath)
        context.setLineWidth(10)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.28))
        context.strokePath()
        context.restoreGState()
    }
}

/// `contrast` boosts edge alpha for tiny sizes, where the source strokes would otherwise fall
/// below one pixel and render as light grey (0 = untouched source).
func render(pixelSize: Int, tile: Bool, ink: CGColor, glyphScale: CGFloat, contrast: CGFloat = 0) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    context.interpolationQuality = .high
    let scale = CGFloat(pixelSize) / 1024
    context.scaleBy(x: scale, y: scale)

    if tile {
        let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
        let path = CGPath(roundedRect: tileRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
        context.saveGState()
        if pixelSize >= 128 {
            context.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: CGColor(gray: 0, alpha: 0.12))
        }
        context.addPath(path)
        context.setFillColor(tileColor)
        context.fillPath()
        context.restoreGState()
        if tileFinish {
            drawTileFinish(in: context, tilePath: path, pixelSize: pixelSize)
        }
    }

    // Fit the glyph's longer side into the glyph box, centred on the canvas.
    let box = 1024 * glyphScale
    let aspect = CGFloat(glyph.width) / CGFloat(glyph.height)
    let size = aspect >= 1 ? CGSize(width: box, height: box / aspect) : CGSize(width: box * aspect, height: box)
    let rect = CGRect(x: (1024 - size.width) / 2, y: (1024 - size.height) / 2, width: size.width, height: size.height)

    let layer = inkLayer(pixelSize: pixelSize, rect: rect, scale: scale, ink: ink, alphaGain: 1 + contrast)
    context.draw(layer, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    return rep
}

/// Renders the glyph at the final pixel size, recoloured to `ink`. `alphaGain` > 1 strengthens
/// the anti-aliased edge pixels so sub-pixel strokes at tiny sizes stay dark instead of grey,
/// without growing the shapes into blobs.
func inkLayer(pixelSize: Int, rect: CGRect, scale: CGFloat, ink: CGColor, alphaGain: CGFloat) -> CGImage {
    let width = pixelSize, height = pixelSize
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.scaleBy(x: scale, y: scale)
    context.draw(glyph, in: rect)

    let components = ink.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)!.components!
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let alpha = min(1, CGFloat(pixels[index + 3]) / 255 * alphaGain)
        pixels[index] = UInt8((components[0] * alpha * 255).rounded())
        pixels[index + 1] = UInt8((components[1] * alpha * 255).rounded())
        pixels[index + 2] = UInt8((components[2] * alpha * 255).rounded())
        pixels[index + 3] = UInt8((alpha * 255).rounded())
    }
    return context.makeImage()!
}

func write(_ rep: NSBitmapImageRep, to url: URL) {
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed") }
    try! data.write(to: url)
}

// MARK: - App icon slots

let slots: [(file: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("quickfiles.png", 1024)
]

for slot in slots {
    // Small sizes get a slightly larger, higher-contrast glyph so the thin strokes keep some weight.
    let scale = slot.pixels <= 32 ? glyphFraction + 0.08 : glyphFraction
    let contrast: CGFloat = switch slot.pixels {
    case ...16: 1.2
    case ...32: 1.0
    case ...64: 0.5
    default: 0
    }
    write(render(pixelSize: slot.pixels, tile: drawsTile, ink: inkColor, glyphScale: scale, contrast: contrast),
          to: appIconSet.appendingPathComponent(slot.file))
}

// MARK: - Menu-bar template glyph (black on transparent, 18pt @1x/@2x)

try? FileManager.default.createDirectory(at: menuBarSet, withIntermediateDirectories: true)
write(render(pixelSize: 18, tile: false, ink: CGColor(gray: 0, alpha: 1), glyphScale: 0.98, contrast: 1.0),
      to: menuBarSet.appendingPathComponent("menubar.png"))
write(render(pixelSize: 36, tile: false, ink: CGColor(gray: 0, alpha: 1), glyphScale: 0.98, contrast: 0.6),
      to: menuBarSet.appendingPathComponent("menubar@2x.png"))
let menuBarContents = """
{
  "images" : [
    { "filename" : "menubar.png", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "menubar@2x.png", "idiom" : "universal", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "template" }
}

"""
try! menuBarContents.write(to: menuBarSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

// MARK: - Previews

write(render(pixelSize: 1024, tile: drawsTile, ink: inkColor, glyphScale: glyphFraction),
      to: previewDir.appendingPathComponent("QuickFiles-AppIcon-1024.png"))
print("Wrote \(slots.count) app icon slots, menu-bar glyph, and preview.")
