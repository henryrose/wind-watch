import SwiftUI

/// Direction arrow kite (HANDOFF §5): `M0,-0.5 L0.38,0.5 L0,0.2 L-0.38,0.5 Z` in a unit box,
/// pointing up. Rotate by `Compass.arrowRotation(dirFrom:)` so it points where the wind blows TO.
public struct ArrowShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = rect.midX, cy = rect.midY
        var p = Path()
        p.move(to: CGPoint(x: cx, y: cy - 0.5 * h))
        p.addLine(to: CGPoint(x: cx + 0.38 * w, y: cy + 0.5 * h))
        p.addLine(to: CGPoint(x: cx, y: cy + 0.2 * h))
        p.addLine(to: CGPoint(x: cx - 0.38 * w, y: cy + 0.5 * h))
        p.closeSubpath()
        return p
    }
}

/// A filled arrow of `size` points, rotated to point where the wind blows TO.
public struct ArrowView: View {
    public var dirFrom: Int
    public var size: CGFloat
    public var color: Color?

    public init(dirFrom: Int, size: CGFloat, color: Color? = nil) {
        self.dirFrom = dirFrom
        self.size = size
        self.color = color
    }

    public var body: some View {
        ArrowShape()
            .fill(color ?? Color.primary)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(Compass.arrowRotation(dirFrom: dirFrom)))
            .accessibilityLabel(Text("blowing " + Compass.points[Compass.sectorIndex(degrees: Compass.toBearing(dirFrom: dirFrom))]))
    }
}

/// Horizontal line across the middle of its rect; stroke with round caps for a gust tick cap.
public struct TickCapShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// Gust tick cap: `width` = bar width + 2, stroke = gust line stroke, round caps, 100 % ink.
public struct TickCap: View {
    public var width: CGFloat
    public var lineWidth: CGFloat
    public var color: Color?

    public init(width: CGFloat, lineWidth: CGFloat, color: Color? = nil) {
        self.width = width
        self.lineWidth = lineWidth
        self.color = color
    }

    public var body: some View {
        TickCapShape()
            .stroke(color ?? Color.primary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: width, height: lineWidth)
    }
}

/// Sun marker: circle of `radius` in the `sun` token colour.
public struct SunDot: View {
    public var radius: CGFloat
    public var scheme: ColorScheme

    public init(radius: CGFloat, scheme: ColorScheme = .dark) {
        self.radius = radius
        self.scheme = scheme
    }

    public var body: some View {
        Circle()
            .fill(Tokens.sun(scheme))
            .frame(width: radius * 2, height: radius * 2)
            .accessibilityHidden(true)
    }
}

/// Hero Beaufort pill: 48×6 (phone/web) or 36×5 (watch), radius = half height, step colour.
/// `bft.10` carries its 2 pt inset `bft.8` stroke.
public struct BeaufortPill: View {
    public var step: Int
    public var width: CGFloat
    public var height: CGFloat
    public var scheme: ColorScheme

    public init(step: Int, width: CGFloat = 48, height: CGFloat = 6, scheme: ColorScheme = .dark) {
        self.step = step
        self.width = width
        self.height = height
        self.scheme = scheme
    }

    public static func watch(step: Int) -> BeaufortPill { BeaufortPill(step: step, width: 36, height: 5, scheme: .dark) }

    public var body: some View {
        let token = Beaufort.colorToken(step: step)
        Capsule()
            .fill(token.color(for: scheme))
            .overlay {
                if let stroke = token.strokeColor(for: scheme) {
                    Capsule().inset(by: 1).stroke(stroke, lineWidth: 2)
                }
            }
            .frame(width: width, height: height)
            .accessibilityLabel(Text("Beaufort \(step)"))
    }
}

/// Table Beaufort chip: min width 24, 2 pt vertical padding, radius 6, step colour, black
/// Semibold 13 label with the step number.
public struct BeaufortChip: View {
    public var step: Int
    public var scheme: ColorScheme

    public init(step: Int, scheme: ColorScheme = .dark) {
        self.step = step
        self.scheme = scheme
    }

    public var body: some View {
        let token = Beaufort.colorToken(step: step)
        Text("\(step)")
            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.black)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .frame(minWidth: 24)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(token.color(for: scheme))
                    .overlay {
                        if let stroke = token.strokeColor(for: scheme) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).inset(by: 1).stroke(stroke, lineWidth: 2)
                        }
                    }
            }
            .accessibilityLabel(Text("Beaufort \(step)"))
    }
}

/// The offline glyph: SF Symbol `wifi.slash`.
public struct WifiSlash: View {
    public init() {}

    public var body: some View {
        Image(systemName: "wifi.slash")
            .accessibilityLabel(Text("offline"))
    }
}
