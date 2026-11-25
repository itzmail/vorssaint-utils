// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 itzmail
//
// Draws the Solvane brand art, which replaces the Vorssaint artwork that
// TRADEMARKS.md does not license to forks:
// - Resources/Brand/AppIcon-Default.png: the app icon master (1024 px)
// - Resources/Brand/logo.png: the bare glyph on a transparent canvas, from
//   which MakeIcon.swift derives the menu bar template image and the brand mark
// - Resources/Brand/logo-menubar.png: the same glyph, heavier, for the menu bar
// Run it from anywhere: swift Tools/MakeSolvaneIcon.swift
import AppKit

let canvas: CGFloat = 1024
let projectDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let brandDir = projectDir.appendingPathComponent("Resources/Brand")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func render(to file: String, _ draw: (CGContext) -> Void) {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep)
    else { fatalError("no bitmap context") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw(context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png encode failed") }
    do { try png.write(to: brandDir.appendingPathComponent(file)) } catch { fatalError("\(error)") }
}

let center = CGPoint(x: canvas / 2, y: 520)

/// The compass star: a long four-point star over a shorter diagonal one.
func fillStar(_ c: CGContext, long: CGFloat, short: CGFloat, turned: Bool) {
    c.saveGState()
    c.translateBy(x: center.x, y: center.y)
    if turned { c.rotate(by: .pi / 4) }
    let points: [(CGFloat, CGFloat)] = [(0, long), (short, short), (long, 0), (short, -short),
                                        (0, -long), (-short, -short), (-long, 0), (-short, short)]
    let path = CGMutablePath()
    for (index, point) in points.enumerated() {
        index == 0 ? path.move(to: CGPoint(x: point.0, y: point.1)) : path.addLine(to: CGPoint(x: point.0, y: point.1))
    }
    path.closeSubpath()
    c.addPath(path)
    c.fillPath()
    c.restoreGState()
}

/// The sun at the star's heart: a ring cut out of the star around a dot.
func fillHeart(_ c: CGContext, cut: CGColor) {
    c.setFillColor(cut)
    c.fillEllipse(in: CGRect(x: center.x - 64, y: center.y - 64, width: 128, height: 128))
    c.setFillColor(color(0x000000))
    c.fillEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))
}

// App icon: black glyph on a white rounded square with a soft shadow.
render(to: "AppIcon-Default.png") { c in
    c.saveGState()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: canvas, height: canvas), xRadius: 230, yRadius: 230).addClip()
    let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: [color(0xFFFFFF), color(0xF3F3F3), color(0xFBFBFB)] as CFArray,
                                locations: [0, 0.7, 1])!
    c.drawLinearGradient(background, start: CGPoint(x: 0, y: canvas), end: .zero, options: [])
    c.setShadow(offset: CGSize(width: 0, height: -26), blur: 34, color: color(0x000000, 0.28))
    c.setFillColor(color(0x000000))
    c.setStrokeColor(color(0x000000))
    c.setLineWidth(34)
    c.setLineCap(.round)
    for (start, end) in [(12.0, 78.0), (102, 168), (192, 258), (282, 348)] {
        c.addArc(center: center, radius: 320, startAngle: start * .pi / 180, endAngle: end * .pi / 180, clockwise: false)
        c.strokePath()
    }
    fillStar(c, long: 390, short: 62, turned: false)
    fillStar(c, long: 235, short: 40, turned: true)
    c.setShadow(offset: .zero, blur: 0, color: nil)
    fillHeart(c, cut: color(0xFFFFFF))
    c.restoreGState()
}

// Brand glyph: only the star and its heart, on transparency. The orbit arcs
// are left out because they vanish at menu bar size (see logo-menubar.png).
render(to: "logo.png") { c in
    c.setFillColor(color(0x000000))
    fillStar(c, long: 390, short: 62, turned: false)
    fillStar(c, long: 235, short: 40, turned: true)
    c.setBlendMode(.clear)
    c.fillEllipse(in: CGRect(x: center.x - 64, y: center.y - 64, width: 128, height: 128))
    c.setBlendMode(.normal)
    c.setFillColor(color(0x000000))
    c.fillEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))
}
// Menu bar glyph: the same star and orbit arcs drawn for 15 pt. A wider heart,
// fatter secondary points and heavier arcs keep every part readable instead of
// blurring into grey.
render(to: "logo-menubar.png") { c in
    c.setFillColor(color(0x000000))
    c.setStrokeColor(color(0x000000))
    c.setLineWidth(70)
    c.setLineCap(.round)
    for (start, end) in [(16.0, 74.0), (106, 164), (196, 254), (286, 344)] {
        c.addArc(center: center, radius: 340, startAngle: start * .pi / 180, endAngle: end * .pi / 180, clockwise: false)
        c.strokePath()
    }
    fillStar(c, long: 390, short: 96, turned: false)
    fillStar(c, long: 250, short: 70, turned: true)
    c.setBlendMode(.clear)
    c.fillEllipse(in: CGRect(x: center.x - 112, y: center.y - 112, width: 224, height: 224))
    c.setBlendMode(.normal)
    c.setFillColor(color(0x000000))
    c.fillEllipse(in: CGRect(x: center.x - 52, y: center.y - 52, width: 104, height: 104))
}
print("wrote Resources/Brand/AppIcon-Default.png, logo.png and logo-menubar.png")
