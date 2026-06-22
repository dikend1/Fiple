import AppKit
import CoreGraphics
import Foundation

// Renders the Fiple app icon — a blue, rounded "F" wordmark on a white field —
// at 1024×1024 and writes a PNG. iOS applies its own squircle mask, so the
// canvas is full-bleed white. Run: swift tools/MakeAppIcon.swift <output.png>

let out = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Apps/FipleiOS/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("no context") }

// White background (iOS rounds the corners into the squircle).
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// "F" built from three capsules (stem + top arm + middle arm). Bottom-left origin.
let T: CGFloat = 132          // stroke thickness
let x0: CGFloat = 360         // left edge of the stem
let yBot: CGFloat = 300       // bottom of the stem
let stemH: CGFloat = 430      // stem height
let topArmW: CGFloat = 320    // top arm length
let midArmW: CGFloat = 232    // middle arm length
let armGap: CGFloat = 80      // clear white gap between the two arms

func capsule(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
    let r = min(w, h) / 2
    return CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
                  cornerWidth: r, cornerHeight: r, transform: nil)
}

let yTop = yBot + stemH                    // 724
let topArmY = yTop - T                      // top arm flush with the stem top
let midArmY = topArmY - armGap - T          // middle arm a clear gap below it

let f = CGMutablePath()
f.addPath(capsule(x0, yBot, T, stemH))      // vertical stem
f.addPath(capsule(x0, topArmY, topArmW, T)) // top arm
f.addPath(capsule(x0, midArmY, midArmW, T)) // middle arm

ctx.saveGState()
ctx.addPath(f)
ctx.clip()
let grad = CGGradient(
    colorsSpace: cs,
    colors: [
        CGColor(red: 0.32, green: 0.49, blue: 1.00, alpha: 1),  // lighter at top
        CGColor(red: 0.17, green: 0.31, blue: 0.95, alpha: 1),  // deeper at bottom
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: 0, y: yTop),
                       end: CGPoint(x: 0, y: yBot),
                       options: [])
ctx.restoreGState()

guard let img = ctx.makeImage() else { fatalError("no image") }
let rep = NSBitmapImageRep(cgImage: img)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
