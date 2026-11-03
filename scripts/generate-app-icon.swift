import AppKit
// Usage: swift scripts/generate-app-icon.swift money-manager/Assets.xcassets/AppIcon.appiconset
import CoreGraphics

// Duitku icon: a geometric lowercase "d" whose bowl holds a coin.
enum Variant { case light, dark, tinted }

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ v: Variant, to path: String) {
    let s = 1024
    let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let full = CGRect(x: 0, y: 0, width: s, height: s)

    // Background
    switch v {
    case .light:
        let g = CGGradient(colorsSpace: nil, colors: [color(0xFF8A5C), color(0xFF4F6D)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
    case .dark:
        let g = CGGradient(colorsSpace: nil, colors: [color(0x2A2A2E), color(0x121214)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
    case .tinted:
        ctx.setFillColor(color(0x000000)); ctx.fill(full)
    }

    // Mark geometry (CG origin bottom-left). Bowl centred slightly left, stem on its right.
    let stroke: CGFloat = 112
    let bowlC = CGPoint(x: 512 - 95, y: 420)  // whole mark centred horizontally
    let bowlR: CGFloat = 190           // centre-line radius of the ring
    let stemX = bowlC.x + bowlR        // stem runs along the ring's right edge
    let stemTop: CGFloat = 800
    let stemBottom = bowlC.y - bowlR

    let markColor: CGColor
    let coinColor: CGColor
    switch v {
    case .light: markColor = color(0xFFFFFF); coinColor = color(0xFFFFFF)
    case .dark: markColor = color(0xFF6B5A); coinColor = color(0xFFB347)
    case .tinted: markColor = color(0xFFFFFF); coinColor = color(0xB0B0B0)
    }

    // Soft shadow under the mark on the light icon for depth.
    if v == .light { ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: color(0x8A1F2E, 0.35)) }
    // One layer so ring and stem cast a single shadow with no seam.
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)

    ctx.setStrokeColor(markColor)
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    // Ring
    ctx.addArc(center: bowlC, radius: bowlR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()
    // Stem
    ctx.move(to: CGPoint(x: stemX, y: stemBottom))
    ctx.addLine(to: CGPoint(x: stemX, y: stemTop))
    ctx.strokePath()
    ctx.endTransparencyLayer()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Coin inside the bowl
    let coinR: CGFloat = 62
    ctx.setFillColor(coinColor)
    ctx.fillEllipse(in: CGRect(x: bowlC.x - coinR, y: bowlC.y - coinR, width: coinR * 2, height: coinR * 2))

    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments[1]
render(.light, to: out + "/AppIcon.png")
render(.dark, to: out + "/AppIcon-dark.png")
render(.tinted, to: out + "/AppIcon-tinted.png")
