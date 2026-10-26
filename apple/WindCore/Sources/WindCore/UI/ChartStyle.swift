import Foundation

/// Tick-label text under the plot (HANDOFF §6.1, §6.4a).
public enum TimeLabelFormat: Sendable, Equatable {
    case none
    /// `09`, `15` (watch strip).
    case hour24
    /// `9am`, `noon`, `12am` (phone, web).
    case hour12
}

/// The horizon-edge label (HANDOFF §5, §6.4a).
public enum EdgeLabelFormat: Sendable, Equatable {
    case none
    /// `ends 05:00` (watch).
    case time24
    /// `ends Fri 5am` (phone, web).
    case weekday12
}

/// Per-surface chart parameters: the keyword arguments of `chart_reference.py::svg()` in points.
/// Watch values are the reference's 2× pixels halved.
public struct ChartStyle: Sendable, Equatable {
    /// `plotH` — height of the plot between the insets.
    public var plotHeight: CGFloat
    /// `top` — room above the plot for the day band, `now` / edge labels and sun dots.
    public var topInset: CGFloat
    /// `bot` — the arrow row under the plot.
    public var bottomInset: CGFloat
    /// Baseline of the tick labels below `top + plotH + bot` (the reference's `H + 10`).
    public var labelBaseline: CGFloat
    /// Height reserved under the box for the tick labels.
    public var labelBand: CGFloat
    public var barCornerRadius: CGFloat
    public var minBarWidth: CGFloat
    /// `gw` — gust line stroke; caps use the same.
    public var gustLineWidth: CGFloat
    /// `font` — label size; grid labels use one point less.
    public var fontSize: CGFloat
    public var arrowSize: CGFloat
    /// Arrow every n-th slot; 0 = none.
    public var arrowEvery: Int
    /// Tick every n hours of the day; 0 = none. 6-h ticks sit at 03/09/15/21, 3-h at 00/03/….
    public var tickEvery: Int
    public var labelFormat: TimeLabelFormat
    public var showsGrid: Bool
    /// Day band above the plot with dotted midnight dividers.
    public var showsDays: Bool
    public var sunRadius: CGFloat
    public var edgeLabel: EdgeLabelFormat
    public var isWatch: Bool
    /// Points per reference pixel: 1 on the phone, 0.5 on the watch (the reference draws watch
    /// surfaces at 2×). Scales the small constants (cap + 2, `top − 6`, label offsets, dashes).
    public var unit: CGFloat
    /// Horizontal room outside the plot that labels may spill into (the reference SVG has
    /// `overflow: visible`); drawn, never laid out. Phone cards have 16 pt of padding.
    public var overflow: CGFloat
    /// 7 d (§12a): day names centred under each day on the bottom axis instead of hour labels;
    /// the dotted midnight dividers stay.
    public var dayLabelsAtBottom = false
    /// Drop the tick label of the first slot (§6.4d: the edge-to-edge portrait plot would clip it).
    public var dropsFirstTickLabel = false

    public init(plotHeight: CGFloat, topInset: CGFloat, bottomInset: CGFloat, labelBaseline: CGFloat, labelBand: CGFloat,
                barCornerRadius: CGFloat, minBarWidth: CGFloat = 3, gustLineWidth: CGFloat, fontSize: CGFloat, arrowSize: CGFloat,
                arrowEvery: Int, tickEvery: Int, labelFormat: TimeLabelFormat, showsGrid: Bool, showsDays: Bool,
                sunRadius: CGFloat, edgeLabel: EdgeLabelFormat, isWatch: Bool, unit: CGFloat = 1, overflow: CGFloat = 16) {
        self.plotHeight = plotHeight
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.labelBaseline = labelBaseline
        self.labelBand = labelBand
        self.barCornerRadius = barCornerRadius
        self.minBarWidth = minBarWidth
        self.gustLineWidth = gustLineWidth
        self.fontSize = fontSize
        self.arrowSize = arrowSize
        self.arrowEvery = arrowEvery
        self.tickEvery = tickEvery
        self.labelFormat = labelFormat
        self.showsGrid = showsGrid
        self.showsDays = showsDays
        self.sunRadius = sunRadius
        self.edgeLabel = edgeLabel
        self.isWatch = isWatch
        self.unit = unit
        self.overflow = overflow
    }

    /// Bar width as a fraction of the slot.
    public static let barRatio: Double = 0.72

    /// `top + plotH + bot`: the reference's `H`.
    public var boxHeight: CGFloat { topInset + plotHeight + bottomInset }
    /// Full view height including the tick-label band.
    public var totalHeight: CGFloat { boxHeight + labelBand }

    /// iPhone portrait (`phonebig`): 402×262 (edge to edge, §6.4d), top 38 / bottom 18, arrows every 3 h, 6-h 12-hour
    /// labels, day band, `ends Fri 5am` (HANDOFF §6.4, §6.4a).
    public static let phonePortrait: ChartStyle = {
        var s = ChartStyle(
            plotHeight: 206, topInset: 38, bottomInset: 18, labelBaseline: 10, labelBand: 13,
            barCornerRadius: 1.5, gustLineWidth: 1.5, fontSize: 11, arrowSize: 9,
            arrowEvery: 3, tickEvery: 6, labelFormat: .hour12, showsGrid: true, showsDays: true,
            sunRadius: 3, edgeLabel: .weekday12, isWatch: false)
        s.dropsFirstTickLabel = true
        return s
    }()

    /// iPhone portrait 7 d (`Phone-Main-7d`, `mixed_reference.py` 'phone'): the same box, arrows
    /// every 6 h, no hour labels, day names on the bottom axis (§12a).
    public static let phonePortraitWeek: ChartStyle = {
        var s = phonePortrait
        s.arrowEvery = 6
        s.tickEvery = 0
        s.labelFormat = .none
        s.dayLabelsAtBottom = true
        s.labelBand = 14
        return s
    }()

    /// iPhone landscape (`land`): 834×296 (screen − 40, §6.4d), top 38 / bottom 22, arrows every hour, 3-h labels (§6.4b).
    public static let phoneLandscape = ChartStyle(
        plotHeight: 236, topInset: 38, bottomInset: 22, labelBaseline: 10, labelBand: 14,
        barCornerRadius: 1.5, gustLineWidth: 1.5, fontSize: 12, arrowSize: 9,
        arrowEvery: 1, tickEvery: 3, labelFormat: .hour12, showsGrid: true, showsDays: true,
        sunRadius: 3, edgeLabel: .weekday12, isWatch: false)

    /// iPhone landscape 7 d (`Phone-Landscape-7d`, 'web' mode): HRRR hourly to the seam, arrows
    /// every 3 h, day names on the bottom axis.
    public static let phoneLandscapeWeek: ChartStyle = {
        var s = phoneLandscape
        s.arrowEvery = 3
        s.tickEvery = 0
        s.labelFormat = .none
        s.dayLabelsAtBottom = true
        return s
    }()

    /// iPhone at accessibility type sizes: the plot clamps at 152 and loses the day band (§4.3).
    public static let phoneClamped = ChartStyle(
        plotHeight: 152, topInset: 22, bottomInset: 16, labelBaseline: 10, labelBand: 13,
        barCornerRadius: 1.5, gustLineWidth: 1.5, fontSize: 11, arrowSize: 9,
        arrowEvery: 3, tickEvery: 6, labelFormat: .hour12, showsGrid: true, showsDays: false,
        sunRadius: 3, edgeLabel: .weekday12, isWatch: false)

    /// Clamped 7 d: the clamped plot with the 7-day axis.
    public static let phoneClampedWeek: ChartStyle = {
        var s = phoneClamped
        s.arrowEvery = 6
        s.tickEvery = 0
        s.labelFormat = .none
        s.dayLabelsAtBottom = true
        s.labelBand = 14
        return s
    }()

    /// Watch 12-h strip (`watchstrip`, 396×230 px @2×): 198×115 pt, top 12 / bottom 11, arrows every
    /// hour, 3-h `HH` labels, no day band, `ends 05:00` (§6.1, §7.3).
    public static let watchStrip = ChartStyle(
        plotHeight: 92, topInset: 12, bottomInset: 11, labelBaseline: 5, labelBand: 8,
        barCornerRadius: 2, gustLineWidth: 1.25, fontSize: 11, arrowSize: 7,
        arrowEvery: 1, tickEvery: 3, labelFormat: .hour24, showsGrid: true, showsDays: false,
        sunRadius: 2.5, edgeLabel: .time24, isWatch: true, unit: 0.5, overflow: 5)

    /// Complication mini strip (`mini`, 150×62 px @2×): 75×31 pt, top 5 / bottom 1; bars, gust line,
    /// caps and sun dot only (§6.3).
    public static let mini = ChartStyle(
        plotHeight: 25, topInset: 5, bottomInset: 1, labelBaseline: 0, labelBand: 0,
        barCornerRadius: 2, gustLineWidth: 1, fontSize: 0, arrowSize: 0,
        arrowEvery: 0, tickEvery: 0, labelFormat: .none, showsGrid: false, showsDays: false,
        sunRadius: 1.5, edgeLabel: .none, isWatch: true, unit: 0.5, overflow: 0)
}
