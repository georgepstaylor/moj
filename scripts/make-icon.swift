// Draws the moj app icon and writes:
//   Resources/AppIcon.icon  Icon Composer format: the gradient fill plus the face as a layer.
//                           build.sh compiles it with actool into Assets.car (macOS 26+, which
//                           frames old-style icons in grey) and AppIcon.icns (older macOS).
//   Resources/AppIcon.png   the finished tile at 1024px, for docs and the website.
// Usage: swift scripts/make-icon.swift
//
// A grinning face on a pink-to-violet tile. Drawn in code rather than with an emoji character,
// so it's sharp at every size and it's our own artwork.
import AppKit
import CoreGraphics

let resources = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A superellipse, close to the continuous-corner tile macOS icons use.
func squircle(_ rect: CGRect, exponent n: CGFloat = 4.2) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    for degree in 0..<360 {
        let t = CGFloat(degree) * .pi / 180
        let c = cos(t), s = sin(t)
        let point = CGPoint(x: rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n),
                            y: rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n))
        if degree == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

let fillTop: UInt32 = 0xFF8CC6, fillMiddle: UInt32 = 0xC07BF0, fillBottom: UInt32 = 0x8E72FF

/// Drawn on a 1024pt canvas (origin bottom-left, y up) and scaled to `size`. With `faceOnly`, just
/// the face on a transparent canvas the size of a full-bleed tile, for the Icon Composer layer.
func render(size: Int, faceOnly: Bool = false) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(size) / 1024
    ctx.scaleBy(x: scale, y: scale)
    ctx.interpolationQuality = .high
    // Shadows are in device pixels and ignore the scale above, so size them by hand.
    func shadow(y: CGFloat, blur: CGFloat, _ shade: CGColor) {
        ctx.setShadow(offset: CGSize(width: 0, height: y * scale), blur: blur * scale, color: shade)
    }
    func linear(_ colors: [CGColor], from: CGPoint, to: CGPoint) {
        let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
        ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    if faceOnly {
        // The layer canvas is the whole tile, so scale the 824pt tile up to fill it.
        let grow: CGFloat = 1024 / 824
        ctx.translateBy(x: 512, y: 512)
        ctx.scaleBy(x: grow, y: grow)
        ctx.translateBy(x: -512, y: -512)
    } else {
    // Tile: the standard macOS grid, an 824pt tile in a 1024pt canvas, with a soft drop shadow.
    let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tile = squircle(tileRect)
    ctx.saveGState()
    shadow(y: -12, blur: 28, color(0x000000, 0.32))
    ctx.addPath(tile)
    ctx.setFillColor(color(0xC57BE8))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    linear([color(fillTop), color(fillMiddle), color(fillBottom)],
           from: CGPoint(x: 380, y: 924), to: CGPoint(x: 644, y: 100))
    // A gentle sheen across the top half.
    linear([color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)],
           from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 560))
    ctx.restoreGState()
    }

    // Face.
    let face = CGRect(x: 512 - 280, y: 500 - 280, width: 560, height: 560)
    ctx.saveGState()
    if !faceOnly { shadow(y: -16, blur: 30, color(0x4B1D7A, 0.45)) }  // Icon Composer adds its own
    ctx.addEllipse(in: face)
    ctx.setFillColor(color(0xFFCC3D))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addEllipse(in: face)
    ctx.clip()
    let radial = CGGradient(colorsSpace: space,
                            colors: [color(0xFFF2A0), color(0xFFD445), color(0xF7A928)] as CFArray,
                            locations: [0, 0.55, 1])!
    ctx.drawRadialGradient(radial, startCenter: CGPoint(x: 450, y: 640), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 500), endRadius: 300, options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    let ink = color(0x4A2610)

    // Eyes: tall ovals.
    ctx.setFillColor(ink)
    for x in [418.0, 606.0] {
        ctx.fillEllipse(in: CGRect(x: x - 34, y: 548, width: 68, height: 108))
    }

    // Mouth: a flat-topped grin with teeth along the top and a tongue at the bottom.
    let mouth = CGMutablePath()
    mouth.move(to: CGPoint(x: 352, y: 470))
    mouth.addLine(to: CGPoint(x: 672, y: 470))
    mouth.addCurve(to: CGPoint(x: 512, y: 300), control1: CGPoint(x: 672, y: 372), control2: CGPoint(x: 604, y: 300))
    mouth.addCurve(to: CGPoint(x: 352, y: 470), control1: CGPoint(x: 420, y: 300), control2: CGPoint(x: 352, y: 372))
    mouth.closeSubpath()
    ctx.addPath(mouth)
    ctx.setFillColor(ink)
    ctx.fillPath()

    ctx.saveGState()
    ctx.addPath(mouth)
    ctx.clip()
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fill(CGRect(x: 340, y: 424, width: 344, height: 60))
    ctx.setFillColor(color(0xFF6F91))
    ctx.fillEllipse(in: CGRect(x: 512 - 92, y: 268, width: 184, height: 110))
    ctx.restoreGState()

    let image = ctx.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

try render(size: 1024).write(to: resources.appendingPathComponent("AppIcon.png"))

// Icon Composer document: the gradient as the fill, the face as one layer.
func srgb(_ hex: UInt32) -> String {
    let c = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { String(format: "%.5f", Double($0) / 255) }
    return "srgb:\(c[0]),\(c[1]),\(c[2]),1.00000"
}
let iconDoc = resources.appendingPathComponent("AppIcon.icon")
try? FileManager.default.removeItem(at: iconDoc)
try FileManager.default.createDirectory(at: iconDoc.appendingPathComponent("Assets"), withIntermediateDirectories: true)
try render(size: 1024, faceOnly: true).write(to: iconDoc.appendingPathComponent("Assets/face.png"))
let json: [String: Any] = [
    "fill": [
        "linear-gradient": [srgb(fillTop), srgb(fillBottom)],
        "orientation": ["start": ["x": 0.3, "y": 0.0], "stop": ["x": 0.7, "y": 1.0]],
    ],
    "groups": [[
        "layers": [[
            "glass": false,
            "hidden": false,
            "image-name": "face.png",
            "name": "face",
            "position": ["scale": 1.0, "translation-in-points": [0, 0]],
        ]],
        "shadow": ["kind": "neutral", "opacity": 0.5],
        "translucency": ["enabled": false, "value": 0.5],
    ]],
    "supported-platforms": ["squares": "shared"],
]
try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconDoc.appendingPathComponent("icon.json"))
print("Wrote AppIcon.icon and AppIcon.png in \(resources.path)")
