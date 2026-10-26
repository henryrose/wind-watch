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
    /// `bw = round(slot * 0.72, 2)`, min 3.
    public var barWidth: CGFloat { max(style.minBarWidth, (slot * ChartStyle.barRatio * 100).rounded() / 100) }
    /// Tick cap width: bar + 2 (reference pixels).
    public var capWidth: CGFloat { barWidth + 2 * style.unit }
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
    /// Slot centre of a forecast index.
    public func centreX(index: Int) -> CGFloat { x(index: index) + slot / 2 }
    /// `Y(v) = top + plotH − v / ymax · plotH`.
    public func y(_ value: Double) -> CGFloat {
        plotBottom - CGFloat(value / Double(max(model.yMax, 1))) * plotHeight
    }

    // MARK: Marks

    /// Bar rectangle; 0 kn draws a 1 pt stub (HANDOFF §6.1).
    public func barRect(_ p: HourPoint) -> CGRect {
        let top = p.kn > 0 ? y(Double(p.kn)) : plotBottom - 1
        return CGRect(x: x(index: p.index) + (slot - barWidth) / 2, y: top, width: barWidth, height: plotBottom - top)
    }

    /// Gust cap / polyline vertex for a point.
    public func gustPoint(_ p: HourPoint) -> CGPoint {
        CGPoint(x: centreX(index: p.index), y: y(Double(p.gust)))
    }

    /// Gridline values: every 10 kn strictly below `yMax` (the top is never labelled).
    public var gridValues: [Int] { style.showsGrid ? Array(stride(from: 10, to: model.yMax, by: 10)) : [] }

    /// Sun dots on the plot's top edge (`y = top − 1`).
    public var sunPoints: [CGPoint] {
        model.sunMarkers.map { CGPoint(x: x(slot: model.slot(of: $0)), y: plotTop - 1 * unit) }
    }

    /// Now-marker x when `now` lies inside the window.
    public var nowX: CGFloat? {
        let s = model.nowSlot
        guard s >= 0, s <= Double(model.slotCount) else { return nil }
        return x(slot: s)
    }

    /// Horizon-edge x: `X(start + len(hours))`.
    public var edgeX: CGFloat? { model.horizonEdgeSlot.map { x(slot: Double($0)) } }

    /// Centre line of the arrow row: `top + plotH + bot / 2`.
    public var arrowY: CGFloat { plotBottom + style.bottomInset / 2 }

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

    /// Tick label text for a point, per the style's format.
    public func tickLabel(_ p: HourPoint) -> String? {
        // Round five: on the portrait phone the first slot's label would sit on the plot edge
        // (half a 9 pt slot in), so it is dropped; landscape and web have room and keep it.
        if style.dropsFirstTickLabel, p.index == model.firstIndex { return nil }
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

    /// The first day's name is suppressed when `now` sits in the window (round five: the readout
    /// already names the day), as `chart_reference.py` skips `i == start` when `now` is given.
    public var dayMarks: [DayMark] {
        guard style.showsDays else { return [] }
        return model.dayLabels.filter { !($0.slot == 0 && model.showsNow) }.map {
            let x = x(slot: Double($0.slot))
            let divider = $0.slot > 0
            return DayMark(x: x, name: $0.name, divider: divider, labelX: x + (divider ? 5 : 4) * style.unit)
        }
    }

    /// `ends 05:00` / `ends Fri 5am` per the style, when the edge is drawn.
    public var edgeLabel: String? {
        guard edgeX != nil else { return nil }
        switch style.edgeLabel {
        case .none: return nil
        case .time24: return "ends " + TimeFormat.hhmm(model.horizon, tz: model.timeZone)
        case .weekday12: return "ends " + TimeFormat.weekdayHour12(model.horizon, tz: model.timeZone)
        }
    }

    // MARK: Selection (HANDOFF §6.4)

    /// Full-height rule through a selected slot's centre: from `top − 6` to the arrow row bottom.
    public func selectionRuleX(index: Int) -> CGFloat { centreX(index: index) }

    /// White outline around a selected bar: 1.5 pt outside the bar, radius 2.5.
    public func selectionOutline(_ p: HourPoint) -> CGRect {
        let r = barRect(p)
        return CGRect(x: r.minX - 1.5, y: r.minY - 1.5, width: r.width + 3, height: r.height + 1.5)
    }

    /// Forecast index under an x position (`floor(x / slot)`), clamped to the plotted hours;
    /// nil when nothing is plotted.
    public func index(atX px: CGFloat) -> Int? {
        guard let first = model.points.first, let last = model.points.last else { return nil }
        let s = Int((px / slot).rounded(.down))
        return min(max(model.firstIndex + s, first.index), last.index)
    }
}
