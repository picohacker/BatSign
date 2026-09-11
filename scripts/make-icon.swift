// Renders the BatSign app icon (1024×1024) with CoreGraphics and wires up
// the asset catalog. Runs on macOS CI via `swift scripts/make-icon.swift`.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let scale: CGFloat = 2 // supersample for smooth edges
let w = CGFloat(size) * scale

guard let ctx = CGContext(data: nil, width: Int(w), height: Int(w), bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("icon: cannot create context")
}
ctx.scaleBy(x: scale, y: scale)
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)

let canvas = CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))

// Deep space gradient background (dark navy → graphite, warm glow bottom-left)
let bgColors = [CGColor(red: 0.043, green: 0.049, blue: 0.078, alpha: 1),
                CGColor(red: 0.078, green: 0.086, blue: 0.129, alpha: 1)] as CFArray
let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: bgColors, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])

// Ambient amber glow behind the glyph
let glowColors = [CGColor(red: 1.0, green: 0.72, blue: 0.11, alpha: 0.55),
                  CGColor(red: 1.0, green: 0.72, blue: 0.11, alpha: 0.0)] as CFArray
let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: glowColors, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 420), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 420), endRadius: 460, options: [])

// ---- Bat glyph -------------------------------------------------------------
// One wing is authored, then mirrored. Coordinates in 0...1024 (top-down).
// CG y-axis is bottom-up, so flip: y' = 1024 - y.
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: 1024 - y) }

    func batPath() -> CGPath {
        let p = CGMutablePath()
        // Left side authored; right side is its exact mirror (mx = 1024 - x).
        p.move(to: pt(449, 318))              // left ear tip
        p.addLine(to: pt(512, 356))           // head notch
        p.addLine(to: pt(575, 318))           // right ear tip
        p.addCurve(to: pt(598, 402), control1: pt(590, 344), control2: pt(598, 372))
        // Right wing top edge → tip
        p.addCurve(to: pt(912, 350), control1: pt(700, 336), control2: pt(816, 312))
        // Outer scallop down + inward
        p.addCurve(to: pt(788, 570), control1: pt(836, 448), control2: pt(826, 516))
        // Mid scallop
        p.addCurve(to: pt(624, 530), control1: pt(726, 522), control2: pt(676, 480))
        // Inner scallop → body
        p.addCurve(to: pt(556, 470), control1: pt(576, 566), control2: pt(564, 516))
        // Belly
        p.addCurve(to: pt(468, 470), control1: pt(532, 500), control2: pt(492, 500))
        // Mirror: inner scallop out
        p.addCurve(to: pt(400, 530), control1: pt(460, 516), control2: pt(448, 566))
        // Mid scallop out
        p.addCurve(to: pt(236, 570), control1: pt(348, 480), control2: pt(298, 522))
        // Outer scallop up + out to left tip
        p.addCurve(to: pt(112, 350), control1: pt(198, 516), control2: pt(188, 448))
        // Left wing top → left shoulder → left ear tip
        p.addCurve(to: pt(426, 402), control1: pt(208, 312), control2: pt(324, 336))
        p.addCurve(to: pt(449, 318), control1: pt(426, 372), control2: pt(434, 344))
        p.closeSubpath()
        return p
    }

let glyph = batPath()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 42,
              color: CGColor(red: 1.0, green: 0.70, blue: 0.10, alpha: 0.65))

let glyphColors = [CGColor(red: 1.0, green: 0.804, blue: 0.259, alpha: 1),   // #FFCE42
                   CGColor(red: 0.976, green: 0.604, blue: 0.098, alpha: 1)] as CFArray
let glyphGrad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: glyphColors, locations: [0, 1])!
ctx.saveGState()
ctx.addPath(glyph)
ctx.clip()
ctx.drawLinearGradient(glyphGrad, start: pt(0, 560), end: pt(0, 300), options: [])
ctx.restoreGState()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

let img = ctx.makeImage()!

// Downscale the 2× supersampled render to exactly 1024×1024.
let finalSize = 1024
guard let finalCtx = CGContext(data: nil, width: finalSize, height: finalSize, bitsPerComponent: 8,
                               bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("icon: cannot create final context")
}
finalCtx.interpolationQuality = .high
finalCtx.draw(img, in: CGRect(x: 0, y: 0, width: finalSize, height: finalSize))
let finalImage = finalCtx.makeImage()!

// ---- Write asset catalog ---------------------------------------------------
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = root.appendingPathComponent("BatSign/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let dest = iconset.appendingPathComponent("icon_1024.png")
let imageDest = CGImageDestinationCreateWithURL(dest as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(imageDest, finalImage, nil)
guard CGImageDestinationFinalize(imageDest) else { fatalError("icon: failed to write PNG") }

let contents = """
{
  "images" : [
    {
      "filename" : "icon_1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try contents.write(to: iconset.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("icon: wrote \(dest.path)")
