import Foundation

/// Pixel mapping for one chart layout: a port of the maths in `chart_reference.py::svg()`.
/// Everything derives from the slot width `width / slotCount`. Pure, so tests can compare it
/// with the reference SVG fragments in `docs/design/reference/charts/`.
public struct ChartGeometry: Sendable {
    public let model: ChartModel
    public let style: ChartStyle
    /// Plot width (`W`); the plot has no left gutter (`left = 0`).
    public let width: CGFloat

    public init(model: ChartModel, style: ChartStyle, width: CGFloat) {
        self.model = model
        self.style = style
        self.width = width
    }

    // MARK: Slots and axes

    /// `slot = plotW / n`.
    public var slot: CGFloat { width / CGFloat(max(model.slotCount, 1)) }
    /// `bw = round(slot * 0.72, 2)`, min 3, for a one-hour slot.
    public var barWidth: CGFloat { barWidth(span: 1) }
    /// Tick cap width: bar + 2 (reference pixels).
    public var capWidth: CGFloat { barWidth + 2 * style.unit }
    /// Bar width for a slot of `span` hours (`max(3, span · pxh · 0.72)` in `mixed_reference.py`).
    public func barWidth(span: Int) -> CGFloat {
        max(style.minBarWidth, (CGFloat(span) * slot * ChartStyle.barRatio * 100).rounded() / 100)
    }
    /// Cap width for a point: its bar + 2.
    public func capWidth(_ p: HourPoint) -> CGFloat { barWidth(span: p.span) + 2 * style.unit }
    /// Points per reference pixel.
    public var unit: CGFloat { style.unit }

    public var plotTop: CGFloat { style.topInset }
    public var plotHeight: CGFloat { style.plotHeight }
    public var plotBottom: CGFloat { style.topInset + style.plotHeight }
    /// `H` in the reference: `top + plotH + bot`.
    public var boxHeight: CGFloat { style.boxHeight }
    /// Full height including the tick-label band.
    public var height: CGFloat { style.totalHeight }

    /// `X(i) = left + (i − start) · slot`, for fractional slots.
    public func x(slot s: Double) -> CGFloat { CGFloat(s) * slot }
    /// Left edge of a forecast index's slot.
    public func x(index: Int) -> CGFloat { x(slot: Double(index - model.firstIndex)) }
    /// Slot centre of a one-hour forecast index.
    public func centreX(index: Int) -> CGFloat { x(index: index) + slot / 2 }
    /// Centre of a plotted slot (a 3-hour block is three slots wide).
    public func centreX(_ p: HourPoint) -> CGFloat { x(index: p.index) + CGFloat(p.span) * slot / 2 }
    /// `Y(v) = top + plotH − v / ymax · plotH`.
    public func y(_ value: Double) -> CGFloat {
        plotBottom - CGFloat(value / Double(max(model.yMax, 1))) * plotHeight
    }

    // MARK: Marks

    /// Bar rectangle; 0 kn draws a 1 pt stub (HANDOFF §6.1).
    public func barRect(_ p: HourPoint) -> CGRect {
        let top = p.kn > 0 ? y(Double(p.kn)) : plotBottom - 1
        let w = barWidth(span: p.span)
        return CGRect(x: x(index: p.index) + (CGFloat(p.span) * slot - w) / 2, y: top, width: w, height: plotBottom - top)
    }

    /// Gust cap / polyline vertex for a point.
    public func gustPoint(_ p: HourPoint) -> CGPoint {
        CGPoint(x: centreX(p), y: y(Double(p.gust)))
    }

    /// Gridline values: every 10 kn strictly below `yMax` (the top is never labelled).
    public var gridValues: [Int] { style.showsGrid ? Array(stride(from: 10, to: model.yMax, by: 10)) : [] }

    /// Sun dots on the plot's top edge (`y = top − 1`).
    public var sunPoints: [CGPoint] {
        guard style.showsSun else { return [] }
        return model.sunMarkers.map { CGPoint(x: x(slot: model.slot(of: $0)), y: plotTop - 1 * unit) }
    }

    /// Sun markers with their kind: sunrise a filled dot of `sunRadius`, sunset a ring
    /// `0.75 · unit` smaller with a `1.5 · unit` stroke (§5, `chart_reference.py` 'rise-set').
    public var sunMarks: [(point: CGPoint, isRise: Bool)] {
        guard style.showsSun else { return [] }
        return model.sunEvents.map { (CGPoint(x: x(slot: model.slot(of: $0.date)), y: plotTop - 1 * unit), $0.isRise) }
    }

    /// Radius of the sunset ring.
    public var sunsetRingRadius: CGFloat { style.sunRadius - 0.75 * unit }

    /// Now-marker x when `now` lies inside the window.
    public var nowX: CGFloat? {
        let s = model.nowSlot
        guard style.showsRules, s >= 0, s <= Double(model.slotCount) else { return nil }
        return x(slot: s)
    }

    /// Horizon-edge x: `X(start + len(hours))`, or the end of the last NBM block in 7 d.
    public var edgeX: CGFloat? { style.showsRules ? model.horizonEdgeSlot.map { x(slot: Double($0)) } : nil }

    /// The HRRR→NBM seam x (7 d), when NBM is plotted.
    public var seamX: CGFloat? { model.seamSlot.map { x(slot: Double($0)) } }

    /// The NBM region (tinted #4FA3D8 at 4.5 %): seam to the plot's right edge.
    public var nbmRegion: CGRect? {
        seamX.map { CGRect(x: $0, y: plotTop, width: max(width - $0, 0), height: plotHeight) }
    }

    /// Centre line of the arrow row: `top + plotH + bot / 2`; 5 higher when the day names take the
    /// bottom axis (7 d, `mixed_reference.py`).
    public var arrowY: CGFloat { plotBottom + style.bottomInset / 2 - (style.dayLabelsAtBottom ? 5 * unit : 0) }

    /// Points that get an arrow: every `arrowEvery`-th slot from the window start.
    public var arrowPoints: [HourPoint] {
        guard style.arrowEvery > 0 else { return [] }
        return model.points.filter { ($0.index - model.firstIndex) % style.arrowEvery == 0 }
    }

    /// Points that get a tick + label: local hours on the `tickEvery` grid (6-h ticks sit at
    /// 03/09/15/21 so 9am · 3pm · 9pm · 3am; 3-h ticks at 00/03/…).
    public var tickPoints: [HourPoint] {
        guard style.tickEvery > 0 else { return [] }
        let phase = style.tickEvery == 6 ? 3 : 0
        return model.points.filter { p in
            let hour = model.hourOfDay(slot: p.index - model.firstIndex)
            return (hour - phase) % style.tickEvery == 0
        }
    }

    /// Tick label text for a point, per the style's format (none for the first slot when the
    /// style drops it at the plot edge).
    public func tickLabel(_ p: HourPoint) -> String? {
        if style.dropsFirstTickLabel && p.index == model.firstIndex { return nil }
        let hour = model.hourOfDay(slot: p.index - model.firstIndex)
        switch style.labelFormat {
        case .none: return nil
        case .hour24: return String(format: "%02d", hour)
        case .hour12: return TimeFormat.hour12Tick(hour: hour)
        }
    }

    /// Baseline y of the tick labels (`H + 10` in the reference).
    public var labelBaselineY: CGFloat { boxHeight + style.labelBaseline }

    /// A day-band mark: the divider x, whether a divider is drawn (never for the first day), and
    /// the label's x (`X(i) + 5`, or `+ 4` on the first day, which has no divider to clear).
    public struct DayMark: Sendable, Equatable {
        public var x: CGFloat
        public var name: String
        public var divider: Bool
        public var labelX: CGFloat
    }

    /// The first day's name is suppressed when the `now` marker is drawn (§6.4a, 26 Oct: the
    /// readout already names the day).
    public var dayMarks: [DayMark] {
        guard style.showsDays || style.dayLabelsAtBottom else { return [] }
        return model.dayLabels.filter { $0.slot > 0 || !model.showsNow || style.dayLabelsAtBottom }.map {
            let x = x(slot: Double($0.slot))
            let divider = $0.slot > 0
            return DayMark(x: x, name: $0.name, divider: divider, labelX: x + (divider ? 5 : 4) * style.unit)
        }
    }

    /// 7 d bottom axis (§12a): each day's name centred on its visible part (`X(h + 12)` for a whole
    /// day, the first day between the start and its first midnight, as `mixed_reference.py`),
    /// dropped within 10 pt of the right edge.
    public var bottomDayMarks: [(x: CGFloat, name: String)] {
        guard style.dayLabelsAtBottom else { return [] }
        let labels = model.dayLabels
        return labels.enumerated().compactMap { i, d in
            let end = i + 1 < labels.count ? labels[i + 1].slot : min(d.slot + 24, model.slotCount)
            let cx = x(slot: Double(d.slot + end) / 2)
            return cx < width - 10 * unit ? (cx, d.name) : nil
        }
    }

    /// `ends 05:00` / `ends Fri 5am` per the style, when the edge is drawn. 7 d without NBM:
    /// `ends Fri 5am · NBM unavailable`.
    public var edgeLabel: String? {
        guard edgeX != nil else { return nil }
        let text: String
        switch style.edgeLabel {
        case .none: return nil
        case .time24: text = "ends " + TimeFormat.hhmm(model.horizon, tz: model.timeZone)
        case .weekday12: text = "ends " + TimeFormat.weekdayHour12(model.horizon, tz: model.timeZone)
        }
        return model.nbmUnavailable ? text + " · NBM unavailable" : text
    }

    // MARK: Selection (HANDOFF §6.4)

    /// Full-height rule through a selected slot's centre: from `top − 6` to the arrow row bottom.
    public func selectionRuleX(index: Int) -> CGFloat {
        model.point(index: index).map { centreX($0) } ?? centreX(index: index)
    }

    /// White outline around a selected bar: 1.5 pt outside the bar, radius 2.5.
    public func selectionOutline(_ p: HourPoint) -> CGRect {
        let r = barRect(p)
        return CGRect(x: r.minX - 1.5, y: r.minY - 1.5, width: r.width + 3, height: r.height + 1.5)
    }

    /// Start index of the plotted slot under an x position (`floor(x / slot)`, then the slot that
    /// covers that hour), clamped to the plotted range; nil when nothing is plotted.
    public func index(atX px: CGFloat) -> Int? {
        guard let first = model.points.first, let last = model.points.last else { return nil }
        let s = Int((px / slot).rounded(.down))
        let hour = min(max(model.firstIndex + s, first.index), last.index + last.span - 1)
        return model.point(containing: hour)?.index ?? last.index
    }

    // MARK: Sky band (§12b, `sky_reference.py`)

    /// A sky cell's rect inside a band of `bandHeight` (14): `X + 0.5`, width − 1, 2 pt inset top
    /// and bottom, radius 2.
    public func skyRect(_ c: SkyCell, bandHeight: CGFloat = 14) -> CGRect {
        let x0 = x(slot: Double(c.slot))
        return CGRect(x: x0 + 0.5, y: 2, width: CGFloat(c.hours) * slot - 1, height: bandHeight - 4)
    }

    /// Rain tick x positions, evenly spaced in the cell: `x + w · (j + 1) / (k + 1)`.
    public func rainTickXs(_ c: SkyCell) -> [CGFloat] {
        let k = c.rain.ticks
        let x0 = x(slot: Double(c.slot)), w = CGFloat(c.hours) * slot
        return (0..<k).map { x0 + w * CGFloat($0 + 1) / CGFloat(k + 1) }
    }
}
