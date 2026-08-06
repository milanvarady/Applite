#!/usr/bin/env swift
//
// Draws the DMG window background. Run by release.sh; no image asset is checked
// into the repo, so the look lives here as code you can tweak by editing numbers.
//
//     swift make_dmg_background.swift <out.png> <width> <height> <scale>
//
// release.sh renders it twice (1x and 2x) and combines the pair into a single
// multi-representation TIFF with `tiffutil -cathidpicheck`, which is what makes
// Finder render it crisply on a Retina display.
//
// Geometry must stay in sync with the create-dmg flags in release.sh: the image
// is the window's content area, so its size is exactly --window-size and the
// arrow is positioned between the two --icon centres.

import AppKit

// MARK: - Layout (points, y measured from the top like Finder's icon positions)

let iconCenterY: CGFloat = 185
let appIconX: CGFloat = 150
let dropLinkX: CGFloat = 410
let iconHalf: CGFloat = 64      // --icon-size 128
let arrowGap: CGFloat = 24      // breathing room between an icon and the arrow
let captionY: CGFloat = 316

// MARK: - Palette, derived from AppIcon.icon's gradient

func p3(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(displayP3Red: r, green: g, blue: b, alpha: a)
}

let brandViolet = p3(0.204, 0.351, 1.000)
let brandPink = p3(0.847, 0.294, 0.565)
let paperTop = p3(0.988, 0.988, 0.996)
let paperBottom = p3(0.945, 0.945, 0.965)
let captionColor = p3(0.42, 0.42, 0.47)

// MARK: - Arguments

let args = CommandLine.arguments
guard args.count == 5,
      let width = Double(args[2]), let height = Double(args[3]), let scale = Double(args[4])
else {
    FileHandle.standardError.write(
        "usage: make_dmg_background.swift <out.png> <width> <height> <scale>\n".data(using: .utf8)!)
    exit(2)
}
let outURL = URL(fileURLWithPath: args[1])
let w = CGFloat(width), h = CGFloat(height)

/// Finder positions icons from the top; Core Graphics draws from the bottom.
func flip(_ yFromTop: CGFloat) -> CGFloat { h - yFromTop }

// MARK: - Canvas

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else {
    FileHandle.standardError.write("could not allocate bitmap\n".data(using: .utf8)!)
    exit(1)
}
rep.size = NSSize(width: w, height: h)   // points, not pixels — this sets the scale

NSGraphicsContext.saveGraphicsState()
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

// MARK: - Paper
//
// The wash is drawn small and scaled up. Core Graphics dithers gradients, and
// that per-pixel noise is incompressible: rendering it at full size produced a
// 709 KB background and a DMG 17% larger than the previous release, for what is
// by design the smoothest part of the image. At 1/4 scale the noise disappears
// and a high-quality upscale is visually identical. The arrow and the caption
// are drawn afterwards at full resolution, so they stay crisp.

let washW = 140, washH = 100
let ww = CGFloat(washW), wh = CGFloat(washH)

guard let washRep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: washW, pixelsHigh: washH,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else {
    FileHandle.standardError.write("could not allocate wash bitmap\n".data(using: .utf8)!)
    exit(1)
}
washRep.size = NSSize(width: ww, height: wh)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: washRep)
NSGradient(colors: [paperTop, paperBottom])?
    .draw(in: NSRect(x: 0, y: 0, width: ww, height: wh), angle: -90)

// A very faint brand wash in the corners, just enough to stop it reading as grey.
for (color, center) in [(brandViolet, CGPoint(x: 0.08 * ww, y: 0.90 * wh)),
                        (brandPink, CGPoint(x: 0.94 * ww, y: 0.08 * wh))] {
    let glow = NSGradient(colors: [color.withAlphaComponent(0.10),
                                   color.withAlphaComponent(0.0)])
    glow?.draw(fromCenter: center, radius: 0,
               toCenter: center, radius: 0.62 * ww, options: [])
}
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.current = ctx
cg.interpolationQuality = .high
washRep.draw(in: NSRect(x: 0, y: 0, width: w, height: h))

// MARK: - Arrow

let arrowStartX = appIconX + iconHalf + arrowGap
let arrowEndX = dropLinkX - iconHalf - arrowGap
let arrowY = flip(iconCenterY)
let headLength: CGFloat = 21
let headHalfHeight: CGFloat = 13
let shaftWidth: CGFloat = 6.5

// The shaft is a rounded rect, but its right end deliberately runs *past* the
// triangle's base and under the head. Ending it flush at the base would show the
// rounded cap curving inward just before the head — the shaft would visibly
// narrow, then meet a wide triangle. The head is far taller than the shaft where
// the cap lands, so the curve is completely hidden.
let shaft = NSBezierPath(
    roundedRect: NSRect(x: arrowStartX,
                        y: arrowY - shaftWidth / 2,
                        width: (arrowEndX - headLength + shaftWidth) - arrowStartX,
                        height: shaftWidth),
    xRadius: shaftWidth / 2, yRadius: shaftWidth / 2)

let head = NSBezierPath()
head.move(to: CGPoint(x: arrowEndX, y: arrowY))
head.line(to: CGPoint(x: arrowEndX - headLength, y: arrowY + headHalfHeight))
head.line(to: CGPoint(x: arrowEndX - headLength, y: arrowY - headHalfHeight))
head.close()

// The same grey as the caption. A brand gradient here read as decoration in its
// own right, competing with the two icons the arrow exists to point between.
captionColor.setFill()
shaft.fill()
head.fill()

// MARK: - Caption

let caption = "Drag Applite to Applications"
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: captionColor,
    .paragraphStyle: paragraph,
]
let captionHeight: CGFloat = 20
NSAttributedString(string: caption, attributes: attributes)
    .draw(in: NSRect(x: 0, y: flip(captionY) - captionHeight,
                     width: w, height: captionHeight))

NSGraphicsContext.restoreGraphicsState()

// MARK: - Write

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("PNG encoding failed\n".data(using: .utf8)!)
    exit(1)
}
do {
    try png.write(to: outURL)
} catch {
    FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
