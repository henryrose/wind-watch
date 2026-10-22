import SwiftUI

/// The wind chart (HANDOFF §6): one drawing for the watch strip, the phone (portrait, landscape,
/// clamped) and the complication mini strip, driven by `ChartGeometry`, a port of
/// `chart_reference.py::svg()`. Twilight shading, Beaufort bars, gust line with caps, sun dots,
/// gridlines, now and horizon rules, day band, direction arrows, hour ticks, and the hour
/// selection (scrub) highlight.
public struct WindChart: View {
    public var model: ChartModel
    public var style: ChartStyle
    /// Selected forecast index (scrub); other bars dim to 45 %.
    public var selection: Int?
    /// When set, the plot takes touch/drag (`DragGesture(minimumDistance: 0)`) and reports the
    /// hour under the finger, nil on release. Also exposes an adjustable accessibility action.
    public var onScrub: ((Int?) -> Void)?

    public init(model: ChartModel, style: ChartStyle, selection: Int? = nil, onScrub: ((Int?) -> Void)? = nil) {
        self.model = model
        self.style = style
        self.selection = selection
        self.onScrub = onScrub
    }

    private var theme: WindTheme { WindTheme(model.scheme) }
    private var ink: Color { theme.inkPrimary }
    private var numberInk: Color { Tokens.numberInk(model.scheme, tier: model.ageTier) }

    public var body: some View {
        GeometryReader { geo in
            let g = ChartGeometry(model: model, style: style, width: geo.size.width)
            let overflow = style.overflow
            Canvas(rendersAsynchronously: false) { ctx, _ in
                ctx.translateBy(x: overflow, y: 0)
                draw(g, in: &ctx)
            }
            .padding(.horizontal, -overflow)
            .contentShape(Rectangle())
            .modifier(ScrubGesture(geometry: g, overflow: overflow, onScrub: onScrub))
        }
        .frame(height: style.totalHeight)
        .oldStateDesaturation(model.ageTier)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .modifier(ScrubAccessibility(model: model, selection: selection, onScrub: onScrub))
    }

    // MARK: Drawing (in the reference's order)

    private func draw(_ g: ChartGeometry, in ctx: inout GraphicsContext) {
        let plotRect = CGRect(x: 0, y: g.plotTop, width: g.width, height: g.plotHeight)
        let u = g.unit
        let labelFont = Font.system(size: style.fontSize, weight: .semibold, design: .rounded).monospacedDigit()
        let textFont = Font.system(size: style.fontSize, weight: .semibold)

        // Day/night shading: one horizontal gradient over the plot.
        ctx.fill(Path(plotRect), with: .linearGradient(
            Gradient(stops: model.shadeStops),
            startPoint: CGPoint(x: 0, y: g.plotTop), endPoint: CGPoint(x: g.width, y: g.plotTop)))

        // Gridlines every 10 kn below the top, labels right-aligned inside the plot at 45 %.
        if style.showsGrid {
            for v in g.gridValues {
                let yy = g.y(Double(v))
                var line = Path()
                line.move(to: CGPoint(x: 0, y: yy))
                line.addLine(to: CGPoint(x: g.width, y: yy))
                ctx.stroke(line, with: .color(ink.opacity(0.12)), lineWidth: u)
                let gridFont = Font.system(size: max(style.fontSize - 1, 1), weight: .semibold, design: .rounded).monospacedDigit()
                drawText(&ctx, "\(v)", font: gridFont, color: ink.opacity(0.45), x: g.width - 2 * u, baseline: yy - 3 * u, anchor: .trailing)
            }
        }

        // Sun dots on the plot's top edge.
        for pt in g.sunPoints {
            let r = style.sunRadius
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: 2 * r, height: 2 * r)), with: .color(theme.sun))
        }

        // Sustained bars, Beaufort-stepped; non-selected bars dim to 45 % while scrubbing.
        for p in model.points {
            let rect = g.barRect(p)
            let token = Beaufort.colorToken(step: p.step)
            let dim = selection != nil && selection != p.index
            let path = Path(roundedRect: rect, cornerRadius: style.barCornerRadius)
            ctx.fill(path, with: .color(token.color(for: model.scheme).opacity(dim ? 0.45 : 1)))
            if let stroke = token.strokeColor(for: model.scheme), rect.height > 4 {
                ctx.stroke(Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: max(style.barCornerRadius - 1, 0.5)),
                           with: .color(stroke.opacity(dim ? 0.45 : 1)), lineWidth: 2)
            }
        }

        // Selection: full-height rule through the slot centre and a white outline on the bar.
        if let sel = selection, let p = model.point(index: sel) {
            let cx = g.selectionRuleX(index: sel)
            var rule = Path()
            rule.move(to: CGPoint(x: cx, y: g.plotTop - 6 * u))
            rule.addLine(to: CGPoint(x: cx, y: g.plotBottom + style.bottomInset))
            ctx.stroke(rule, with: .color(ink), lineWidth: 1.5)
            ctx.stroke(Path(roundedRect: g.selectionOutline(p), cornerRadius: 2.5), with: .color(ink), lineWidth: 1.5)
        }

        // Gust polyline through the cap centres, 75 % ink; caps bar + 2 wide, 100 % ink.
        if model.points.count > 1 {
            var line = Path()
            for (i, p) in model.points.enumerated() {
                let pt = g.gustPoint(p)
                if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
            }
            ctx.stroke(line, with: .color(ink.opacity(0.75)),
                       style: StrokeStyle(lineWidth: style.gustLineWidth, lineJoin: .round))
        }
        for p in model.points {
            let pt = g.gustPoint(p)
            var cap = Path()
            cap.move(to: CGPoint(x: pt.x - g.capWidth / 2, y: pt.y))
            cap.addLine(to: CGPoint(x: pt.x + g.capWidth / 2, y: pt.y))
            ctx.stroke(cap, with: .color(numberInk), style: StrokeStyle(lineWidth: style.gustLineWidth, lineCap: .round))
        }

        // Direction arrows (TO = from + 180) in the bottom inset, 90 % ink.
        for p in g.arrowPoints {
            let s = style.arrowSize
            let base = ArrowShape().path(in: CGRect(x: -s / 2, y: -s / 2, width: s, height: s))
            let transform = CGAffineTransform(translationX: g.centreX(index: p.index), y: g.arrowY)
                .rotated(by: Compass.arrowRotation(dirFrom: p.dirFrom) * .pi / 180)
            ctx.fill(base.applying(transform), with: .color(numberInk.opacity(0.9)))
        }

        // Hour ticks (1 pt, 50 %, 3 tall) and labels at the slot centre.
        for p in g.tickPoints {
            let cx = g.centreX(index: p.index)
            var tick = Path()
            tick.move(to: CGPoint(x: cx, y: g.plotBottom))
            tick.addLine(to: CGPoint(x: cx, y: g.plotBottom + 3 * u))
            ctx.stroke(tick, with: .color(ink.opacity(0.5)), lineWidth: u)
            if let label = g.tickLabel(p) {
                drawText(&ctx, label, font: labelFont, color: ink.opacity(0.6), x: cx, baseline: g.labelBaselineY, anchor: .center)
            }
        }

        // Day band: name at the left of each day; dotted divider at midnight (never the first day).
        // The first day's label is hidden when the `now` label would sit under it (README nit).
        let nowX = g.nowX
        for (i, mark) in g.dayMarks.enumerated() {
            if mark.divider {
                var line = Path()
                line.move(to: CGPoint(x: mark.x, y: g.plotTop - 18 * u))
                line.addLine(to: CGPoint(x: mark.x, y: g.plotBottom))
                ctx.stroke(line, with: .color(ink.opacity(0.28)), style: StrokeStyle(lineWidth: u, dash: [2 * u, 3 * u]))
            }
            if i == 0, let nowX, nowX < mark.x + 5 * u + 3 * style.fontSize { continue }
            drawText(&ctx, mark.name, font: .system(size: style.fontSize, weight: .bold), color: ink.opacity(0.75),
                     x: mark.x + 5 * u, baseline: g.plotTop - 22 * u, anchor: .leading)
        }

        // Now marker: 1.5 pt rule from `top − 6`, label 4 pt right of it.
        if let nowX {
            var rule = Path()
            rule.move(to: CGPoint(x: nowX, y: g.plotTop - 6 * u))
            rule.addLine(to: CGPoint(x: nowX, y: g.plotBottom))
            ctx.stroke(rule, with: .color(ink), lineWidth: 1.5 * u)
            drawText(&ctx, "now", font: textFont, color: ink, x: nowX + 4 * u, baseline: g.plotTop - 8 * u, anchor: .leading)
        }

        // Horizon edge: 1 pt dash 3/3 at 70 %, label right-aligned 4 pt left of it.
        if let edgeX = g.edgeX {
            var rule = Path()
            rule.move(to: CGPoint(x: edgeX, y: g.plotTop - 6 * u))
            rule.addLine(to: CGPoint(x: edgeX, y: g.plotBottom))
            ctx.stroke(rule, with: .color(ink.opacity(0.7)), style: StrokeStyle(lineWidth: u, dash: [3 * u, 3 * u]))
            if let label = g.edgeLabel {
                drawText(&ctx, label, font: textFont, color: ink.opacity(0.7), x: edgeX - 4 * u, baseline: g.plotTop - 8 * u, anchor: .trailing)
            }
        }
    }

    private enum TextAnchor { case leading, center, trailing }

    /// Draws `text` with its baseline at `baseline` (SVG `y` semantics).
    private func drawText(_ ctx: inout GraphicsContext, _ text: String, font: Font, color: Color,
                          x: CGFloat, baseline: CGFloat, anchor: TextAnchor) {
        let resolved = ctx.resolve(Text(verbatim: text).font(font).foregroundStyle(color))
        let size = resolved.measure(in: CGSize(width: 1000, height: 100))
        // SF's descender is roughly a quarter of the point size below the baseline.
        let y = baseline + style.fontSize * 0.24
        let origin: CGPoint
        switch anchor {
        case .leading: origin = CGPoint(x: x, y: y - size.height)
        case .center: origin = CGPoint(x: x - size.width / 2, y: y - size.height)
        case .trailing: origin = CGPoint(x: x - size.width, y: y - size.height)
        }
        ctx.draw(resolved, at: origin, anchor: .topLeading)
    }

    private var accessibilityText: String {
        let hours = model.points.count
        let ends = TimeFormat.weekdayLong(model.horizon, tz: model.timeZone) + " " + TimeFormat.hhmm(model.horizon, tz: model.timeZone)
        let kn = model.points.map(\.kn)
        guard let lo = kn.min(), let hi = kn.max() else { return "Wind chart: no forecast" }
        return "\(hours)-hour wind chart: sustained \(lo) to \(hi) knots, gusts to \(model.maxGust) knots, ends \(ends)"
    }
}

/// Touch or drag anywhere on the plot selects the hour under the finger; release clears.
private struct ScrubGesture: ViewModifier {
    let geometry: ChartGeometry
    let overflow: CGFloat
    let onScrub: ((Int?) -> Void)?

    func body(content: Content) -> some View {
        if let onScrub {
            content.highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in onScrub(geometry.index(atX: value.location.x - overflow)) }
                    .onEnded { _ in onScrub(nil) }
            )
        } else {
            content
        }
    }
}

/// VoiceOver: the chart is adjustable; swipe up/down steps hours and reads the hour's values.
private struct ScrubAccessibility: ViewModifier {
    let model: ChartModel
    let selection: Int?
    let onScrub: ((Int?) -> Void)?

    func body(content: Content) -> some View {
        if let onScrub, let first = model.points.first, let last = model.points.last {
            content
                .accessibilityValue(Text(value))
                .accessibilityAdjustableAction { direction in
                    let current = selection ?? max(Int(model.nowIndex.rounded(.down)), first.index)
                    switch direction {
                    case .increment: onScrub(min(current + 1, last.index))
                    case .decrement: onScrub(max(current - 1, first.index))
                    @unknown default: break
                    }
                }
        } else {
            content
        }
    }

    private var value: String {
        guard let sel = selection, let p = model.point(index: sel) else { return "" }
        return "\(TimeFormat.weekdayLong(p.date, tz: model.timeZone)) \(TimeFormat.hhmm(p.date, tz: model.timeZone)), \(p.kn) knots gusting \(p.gust) \(Compass.spokenFromText(dirFrom: p.dirFrom)), Beaufort \(p.step)"
    }
}
