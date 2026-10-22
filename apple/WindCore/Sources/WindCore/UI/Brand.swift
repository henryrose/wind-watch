import SwiftUI

/// The "Wake" mark (HANDOFF §10a): a white TO-arrow at 103° trailing B2/B3/B4 streaks on an
/// `#0B0E12` tile. Geometry mirrors `docs/design/reference/brand_icon.py` on its 180 grid; the
/// streak count follows the size tier. The app-icon PNGs come from `apple/scripts/render_icons.swift`.
public struct BrandMark: View {
    public enum Tier: Equatable, Sendable {
        case full, small, tiny
        /// ≥ 48 pt full, 24–47 small, < 24 tiny.
        public init(points: CGFloat) { self = points >= 48 ? .full : (points >= 24 ? .small : .tiny) }
    }

    public let size: CGFloat
    public let round: Bool

    /// - Parameters:
    ///   - size: tile edge in points.
    ///   - round: circle tile (watch) instead of the 40/180 rounded square.
    public init(size: CGFloat, round: Bool = false) {
        self.size = size
        self.round = round
    }

    static let ground = Color(red: 0x0B / 255, green: 0x0E / 255, blue: 0x12 / 255)
    // The brand wake uses these exact values, independent of the light/dark ramp.
    static let b2 = Color(red: 0x4F / 255, green: 0xA3 / 255, blue: 0xD8 / 255)
    static let b3 = Color(red: 0x3F / 255, green: 0xC2 / 255, blue: 0xA0 / 255)
    static let b4 = Color(red: 0x8D / 255, green: 0xD4 / 255, blue: 0x4A / 255)

    struct Streak { let x, y1, y2: CGFloat; let color: Color }
    struct Glyph { let cx, cy, s, stroke: CGFloat; let streaks: [Streak] }

    static func glyph(_ tier: Tier) -> Glyph {
        switch tier {
        case .full:
            Glyph(cx: 115.2, cy: 101.8, s: 46, stroke: 11, streaks: [
                Streak(x: -22, y1: 58, y2: 80, color: b2), Streak(x: 0, y1: 58, y2: 92, color: b3),
                Streak(x: 22, y1: 58, y2: 84, color: b4),
            ])
        case .small:
            Glyph(cx: 116.8, cy: 102.2, s: 50, stroke: 18, streaks: [
                Streak(x: -16, y1: 62, y2: 86, color: b2), Streak(x: 16, y1: 62, y2: 92, color: b4),
            ])
        case .tiny:
            Glyph(cx: 117, cy: 103.1, s: 54, stroke: 26, streaks: [Streak(x: 0, y1: 66, y2: 96, color: b3)])
        }
    }

    public var body: some View {
        let g = Self.glyph(Tier(points: size))
        Canvas { ctx, canvas in
            let k = canvas.width / 180
            ctx.scaleBy(x: k, y: k)
            let tile = round
                ? Path(ellipseIn: CGRect(x: 0, y: 0, width: 180, height: 180))
                : Path(roundedRect: CGRect(x: 0, y: 0, width: 180, height: 180), cornerRadius: 40, style: .continuous)
            ctx.fill(tile, with: .color(Self.ground))
            ctx.translateBy(x: g.cx, y: g.cy)
            ctx.rotate(by: .degrees(103))
            for st in g.streaks {
                var line = Path()
                line.move(to: CGPoint(x: st.x, y: st.y1))
                line.addLine(to: CGPoint(x: st.x, y: st.y2))
                ctx.stroke(line, with: .color(st.color), style: StrokeStyle(lineWidth: g.stroke, lineCap: .round))
            }
            var arrow = Path()
            arrow.move(to: CGPoint(x: 0, y: -g.s))
            arrow.addLine(to: CGPoint(x: 0.75 * g.s, y: g.s))
            arrow.addLine(to: CGPoint(x: 0, y: 0.4 * g.s))
            arrow.addLine(to: CGPoint(x: -0.75 * g.s, y: g.s))
            arrow.closeSubpath()
            ctx.fill(arrow, with: .color(.white))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "Wind" Heavy in `ink.primary` + " Watch" Medium in `ink.secondary`, SF Pro Rounded, tracking −3 %.
public struct Wordmark: View {
    public let size: CGFloat
    public let scheme: ColorScheme

    public init(size: CGFloat, scheme: ColorScheme) {
        self.size = size
        self.scheme = scheme
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Wind")
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundStyle(Tokens.inkPrimary(scheme))
            Text(" Watch")
                .font(.system(size: size, weight: .medium, design: .rounded))
                .foregroundStyle(Tokens.inkSecondary(scheme))
        }
        .tracking(-0.03 * size)
        .lineLimit(1)
        .fixedSize()
    }
}

/// Icon tile + wordmark, gap from the artboards (≈ 0.4 × type size). VoiceOver reads "Wind Watch".
public struct BrandLockup: View {
    public let tile: CGFloat
    public let type: CGFloat
    public let gap: CGFloat
    public let scheme: ColorScheme

    public init(tile: CGFloat, type: CGFloat, gap: CGFloat? = nil, scheme: ColorScheme) {
        self.tile = tile
        self.type = type
        self.gap = gap ?? (0.4 * type).rounded()
        self.scheme = scheme
    }

    public var body: some View {
        HStack(spacing: gap) {
            BrandMark(size: tile)
            Wordmark(size: type, scheme: scheme)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wind Watch")
    }
}
