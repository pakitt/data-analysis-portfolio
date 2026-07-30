import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r, g, b, a])!
}

let navyBottom = rgb(0.043, 0.047, 0.118)
let navyTop    = rgb(0.149, 0.161, 0.325)
let amber      = rgb(1.00, 0.706, 0.235)
let amberHot   = rgb(1.00, 0.91, 0.66)
let bodyLight  = rgb(0.235, 0.255, 0.435)
let bodyDark   = rgb(0.067, 0.075, 0.165)

func newLayer() -> CGContext {
    let c = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                      bytesPerRow: 0, space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setShouldAntialias(true); c.interpolationQuality = .high
    return c
}

let ciCtx = CIContext(options: [.workingColorSpace: cs])
func blurred(_ layer: CGContext, _ radius: Double) -> CGImage {
    let src = CIImage(cgImage: layer.makeImage()!)
    let f = CIFilter(name: "CIGaussianBlur")!
    f.setValue(src.clampedToExtent(), forKey: kCIInputImageKey)
    f.setValue(radius, forKey: kCIInputRadiusKey)
    return ciCtx.createCGImage(f.outputImage!, from: src.extent)!
}

// Geometry: lower-left tail → upper-right firefly
let tail = CGPoint(x: 235, y: 452)
let head = CGPoint(x: 610, y: 548)        // glowing abdomen / bright end
let dx = head.x - tail.x, dy = head.y - tail.y
let len = hypot(dx, dy)
let ux = dx/len, uy = dy/len
let px = -uy, py = ux
let angle = atan2(uy, ux)

func tapered(_ p0: CGPoint, _ p1: CGPoint, _ hw0: CGFloat, _ hw1: CGFloat) -> CGPath {
    let a1 = atan2(py, px)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: p0.x + px*hw0, y: p0.y + py*hw0))
    p.addLine(to: CGPoint(x: p1.x + px*hw1, y: p1.y + py*hw1))
    p.addArc(center: p1, radius: hw1, startAngle: a1, endAngle: a1 - .pi, clockwise: true)
    p.addLine(to: CGPoint(x: p0.x - px*hw0, y: p0.y - py*hw0))
    p.addArc(center: p0, radius: hw0, startAngle: atan2(-py,-px),
             endAngle: atan2(-py,-px) - .pi, clockwise: true)
    p.closeSubpath()
    return p
}
func ellipsePath(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, _ a: CGFloat) -> CGPath {
    var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: a)
    return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: 2*rx, height: 2*ry), transform: &t)
}
func fillTaperedGradient(_ ctx: CGContext, _ p0: CGPoint, _ p1: CGPoint, _ hw0: CGFloat, _ hw1: CGFloat,
                         _ c0: CGColor, _ c1: CGColor) {
    ctx.saveGState(); ctx.addPath(tapered(p0, p1, hw0, hw1)); ctx.clip()
    let g = CGGradient(colorsSpace: cs, colors: [c0, c1] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: p0, end: p1, options: [])
    ctx.restoreGState()
}
func radial(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ inner: CGColor, _ outer: CGColor) {
    let g = CGGradient(colorsSpace: cs, colors: [inner, outer] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
}

// ============ Compose ============
let ctx = newLayer()
ctx.clear(CGRect(x: 0, y: 0, width: S, height: S))

let margin: CGFloat = 100
let iconRect = CGRect(x: margin, y: margin, width: S - 2*margin, height: S - 2*margin)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: iconRect, cornerWidth: 185, cornerHeight: 185, transform: nil))
ctx.clip()

// 1. Background
let bg = CGGradient(colorsSpace: cs, colors: [navyBottom, navyTop] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: iconRect.minY),
                       end: CGPoint(x: 0, y: iconRect.maxY), options: [])

// 2. Soft halo layer: wide streak + big orb, heavily blurred
let halo = newLayer()
fillTaperedGradient(halo, tail, head, 14, 58, rgb(1.0, 0.72, 0.28, 0), rgb(1.0, 0.75, 0.32, 0.85))
radial(halo, head, 130, rgb(1.0, 0.80, 0.40, 0.95), rgb(1.0, 0.80, 0.40, 0))
ctx.draw(blurred(halo, 30), in: CGRect(x: 0, y: 0, width: S, height: S))

// 3. Core streak: thinner & brighter, lightly blurred
let core = newLayer()
fillTaperedGradient(core, tail, head, 4, 30, rgb(1.0, 0.70, 0.24, 0), amber)
radial(core, head, 72, amberHot, rgb(1.0, 0.88, 0.6, 0))
ctx.draw(blurred(core, 8), in: CGRect(x: 0, y: 0, width: S, height: S))

// 4. Wings (drawn behind body): two pearly translucent wings on the upper side, swept back
let bodyCenter = CGPoint(x: head.x + ux*72, y: head.y + uy*72)
func drawWing(_ along: CGFloat, _ spread: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ tilt: CGFloat) {
    let wc = CGPoint(x: bodyCenter.x + ux*along + px*spread,
                     y: bodyCenter.y + uy*along + py*spread)
    let path = ellipsePath(wc, rx, ry, angle + tilt)
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    radial(ctx, wc, max(rx, ry), rgb(0.80, 0.87, 1.0, 0.32), rgb(0.80, 0.87, 1.0, 0.04))
    ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(rgb(0.85, 0.90, 1.0, 0.28)); ctx.setLineWidth(2.5); ctx.strokePath()
}
drawWing(8,  44, 74, 28, 0.55)    // forward wing
drawWing(-26, 54, 66, 25, 0.95)   // rear wing

// 5. Antennae: two thin amber strokes curving forward from the head of the body
let headTip = CGPoint(x: bodyCenter.x + ux*82, y: bodyCenter.y + uy*82)
ctx.setLineCap(.round)
for side in [CGFloat(1), -1] {
    let p = CGMutablePath()
    p.move(to: headTip)
    let ctrl = CGPoint(x: headTip.x + ux*46 + px*30*side, y: headTip.y + uy*46 + py*30*side)
    let end  = CGPoint(x: headTip.x + ux*64 + px*70*side, y: headTip.y + uy*64 + py*70*side)
    p.addQuadCurve(to: end, control: ctrl)
    ctx.addPath(p); ctx.setStrokeColor(rgb(1.0, 0.85, 0.5, 0.85)); ctx.setLineWidth(7); ctx.strokePath()
    radial(ctx, end, 14, amberHot, rgb(1.0, 0.9, 0.6, 0))  // glowing tip
}

// 6. Firefly body: slim dark oval, angled. Warm near the lit abdomen (rear), cool navy at the head.
let body = ellipsePath(bodyCenter, 92, 41, angle)
let warmDark = rgb(0.20, 0.14, 0.13)   // warm charcoal near the glow
ctx.saveGState(); ctx.addPath(body); ctx.clip()
let bodyGrad = CGGradient(colorsSpace: cs, colors: [warmDark, bodyDark] as CFArray, locations: [0, 1])!
// along the body axis: rear (near abdomen) → head
ctx.drawLinearGradient(bodyGrad,
    start: CGPoint(x: bodyCenter.x - ux*92, y: bodyCenter.y - uy*92),
    end: CGPoint(x: bodyCenter.x + ux*92, y: bodyCenter.y + uy*92), options: [])
// soft upper rim highlight only (subtle, not a hard pebble edge)
let rim = newLayer()
rim.addPath(body); rim.setStrokeColor(rgb(0.40, 0.45, 0.70, 0.55)); rim.setLineWidth(5); rim.strokePath()
ctx.saveGState()
ctx.addPath(ellipsePath(CGPoint(x: bodyCenter.x + px*30, y: bodyCenter.y + py*30), 110, 70, angle)); ctx.clip()
ctx.draw(blurred(rim, 3), in: CGRect(x: 0, y: 0, width: S, height: S))
ctx.restoreGState()
ctx.restoreGState()

// 7. Bright abdomen core (the lit tail), slightly into the body
radial(ctx, head, 110, rgb(1.0, 0.86, 0.55, 0.5), rgb(1.0, 0.80, 0.40, 0))
radial(ctx, head, 46,  rgb(1.0, 0.98, 0.88, 0.98), rgb(1.0, 0.92, 0.70, 0))

// 8. A few faint stars
func star(_ p: CGPoint, _ r: CGFloat, _ a: CGFloat) {
    radial(ctx, p, r, rgb(1, 1, 1, a), rgb(1, 1, 1, 0))
}
star(CGPoint(x: 770, y: 770), 6, 0.45)
star(CGPoint(x: 300, y: 700), 5, 0.30)
star(CGPoint(x: 720, y: 320), 4, 0.28)

ctx.restoreGState()

let img = ctx.makeImage()!
let out = URL(fileURLWithPath: "/tmp/ffdash_icon_1024.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
