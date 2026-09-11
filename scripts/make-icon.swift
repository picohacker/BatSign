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
    // Right wing, starting at the right ear tip.
    p.move(to: pt(575, 330))
    // Ear notch
    p.addLine(to: pt(512, 362))
    p.addLine(to: pt(449, 330))
    // Head dome to left shoulder
    p.addCurve(to: pt(430, 420), control1: pt(430, 352), control2: pt(422, 388))
    // Left wing top edge → left wing tip
    p.addCurve(to: pt(118, 358), control1: pt(330, 350), control2: pt(210, 322))
    // Outer scallop (down and inward)
    p.addCurve(to: pt(248, 560), control1: pt(196, 448), control2: pt(206, 512))
    // Mid scallop
    p.addCurve(to: pt(400, 520), control1: pt(300, 516), control2: pt(348, 472))
    // Inner scallop → body
    p.addCurve(to: pt(472, 470), control1: pt(448, 556), control2: pt(462, 512))
    // Belly
    p.addCurve(to: pt(552, 470), control1: pt(488, 500), control2: pt(536, 500))
    // Mirror side back to right ear
    p.addCurve(to: pt(594, 420), control1: pt(562, 512), control2: pt(576, 556))
    p.addCurve(to: pt(806, 520), control1: pt(652, 470), control2: pt(676, 556))
    p.addCurve(to: pt(824, 560), control1: pt(790, 472), control2: pt(808, 516))
    p.addCurve(to: pt(906, 358), control1: pt(818, 512), control2: pt(828, 448))
    p.addCurve(to: pt(594, 420), control1: pt(814, 322), control2: pt(694, 350))
    // Right shoulder to ear tip
    p.addCurve(to: pt(575, 330), control1: pt(602, 388), control2: pt(594, 352))
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
