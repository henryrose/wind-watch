// Renders every "Wake" icon PNG (HANDOFF §10a) from the geometry in
// docs/design/reference/brand_icon.py, so the streak count follows the size tier.
//
//   swift apple/scripts/render_icons.swift        # from the repo root
//
// App icons are full-bleed squares with no alpha (the system applies the mask);
// web favicons keep the 40/180 rounded tile with transparent corners.
import AppKit

enum Tier { case full, small, tiny
    // Tier is chosen by the size in points, not pixels (brand_icon.py `tier`).
    init(points: Double) { self = points >= 48 ? .full : (points >= 24 ? .small : .tiny) }
}

let ink = CGColor(srgbRed: 0x0B / 255, green: 0x0E / 255, blue: 0x12 / 255, alpha: 1)
func hex(_ v: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}
let b2 = hex(0x4FA3D8), b3 = hex(0x3FC2A0), b4 = hex(0x8DD44A)

/// (centre x, centre y, arrow half-height s, stroke width, streaks [(x, y1, y2, colour)]) on the 180 grid.
func glyph(_ t: Tier) -> (CGFloat, CGFloat, CGFloat, CGFloat, [(CGFloat, CGFloat, CGFloat, CGColor)]) {
    switch t {
    case .full: return (115.2, 101.8, 46, 11, [(-22, 58, 80, b2), (0, 58, 92, b3), (22, 58, 84, b4)])
    case .small: return (116.8, 102.2, 50, 18, [(-16, 62, 86, b2), (16, 62, 92, b4)])
    case .tiny: return (117, 103.1, 54, 26, [(0, 66, 96, b3)])
    }
}

func render(px: Int, tier: Tier, rounded: Bool, to path: String) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let alpha: CGImageAlphaInfo = rounded ? .premultipliedLast : .noneSkipLast
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: alpha.rawValue)!
    let k = CGFloat(px) / 180
    // SVG coordinates: y down.
    ctx.translateBy(x: 0, y: CGFloat(px)); ctx.scaleBy(x: k, y: -k)
    ctx.setFillColor(ink)
    if rounded {
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 180, height: 180), cornerWidth: 40, cornerHeight: 40, transform: nil))
        ctx.fillPath()
    } else {
        ctx.fill(CGRect(x: 0, y: 0, width: 180, height: 180))
    }
    let (cx, cy, s, sw, streaks) = glyph(tier)
    ctx.translateBy(x: cx, y: cy); ctx.rotate(by: 103 * .pi / 180)
    ctx.setLineWidth(sw); ctx.setLineCap(.round)
    for (x, a, b, c) in streaks {
        ctx.setStrokeColor(c); ctx.move(to: CGPoint(x: x, y: a)); ctx.addLine(to: CGPoint(x: x, y: b)); ctx.strokePath()
    }
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: -s)); p.addLine(to: CGPoint(x: 0.75 * s, y: s))
    p.addLine(to: CGPoint(x: 0, y: 0.4 * s)); p.addLine(to: CGPoint(x: -0.75 * s, y: s)); p.closeSubpath()
    ctx.addPath(p); ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)); ctx.fillPath()
    let data = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

let ios = "apple/WindWatch/Assets.xcassets/AppIcon.appiconset"
let watch = "apple/WindWatchWatch/Assets.xcassets/AppIcon.appiconset"
let web = "web/icons"
try! FileManager.default.createDirectory(atPath: web, withIntermediateDirectories: true)

// iPhone slots: points × scale. 20 pt → tiny, 29/40 pt → small, 60 pt and the store icon → full.
for (pt, scales) in [(20.0, [2, 3]), (29.0, [2, 3]), (40.0, [2, 3]), (60.0, [2, 3])] {
    for sc in scales {
        render(px: Int(pt) * sc, tier: Tier(points: pt), rounded: false, to: "\(ios)/icon-\(Int(pt))@\(sc)x.png")
    }
}
render(px: 1024, tier: .full, rounded: false, to: "\(ios)/icon-1024.png")
// Watch: one full-tier 1024 master; watchOS clips it to the circle.
render(px: 1024, tier: .full, rounded: false, to: "\(watch)/icon-1024.png")
// Web: favicons are tiny tier at 16/32 (drawn at 1×/2× of 16 pt), apple-touch-icon full tier, square.
render(px: 16, tier: .tiny, rounded: true, to: "\(web)/favicon-16.png")
render(px: 32, tier: .tiny, rounded: true, to: "\(web)/favicon-32.png")
render(px: 180, tier: .full, rounded: false, to: "\(web)/apple-touch-icon.png")
print("rendered icons")
