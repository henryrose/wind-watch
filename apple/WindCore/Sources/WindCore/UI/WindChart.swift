import Charts
import SwiftUI

/// Per-surface chart geometry (HANDOFF §6.1). Watch values are points (the table lists px @2×).
public struct ChartStyle: Sendable, Equatable {
    public var plotHeight: CGFloat
    public var plotWidth: CGFloat
    public var topInset: CGFloat
    public var bottomInset: CGFloat
    public var barCornerRadius: CGFloat
    public var gustLineWidth: CGFloat
    public var arrowSize: CGFloat
    public var sunRadius: CGFloat
    public var tickLabelOpacity: Double
    public var isWatch: Bool

    public init(plotHeight: CGFloat, plotWidth: CGFloat, topInset: CGFloat, bottomInset: CGFloat, barCornerRadius: CGFloat,
                gustLineWidth: CGFloat, arrowSize: CGFloat, sunRadius: CGFloat, tickLabelOpacity: Double, isWatch: Bool) {
        self.plotHeight = plotHeight
        self.plotWidth = plotWidth
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.barCornerRadius = barCornerRadius
        self.gustLineWidth = gustLineWidth
        self.arrowSize = arrowSize
        self.sunRadius = sunRadius
        self.tickLabelOpacity = tickLabelOpacity
        self.isWatch = isWatch
    }

    /// Watch 12-h strip in the app (§7.3: 198×115 pt plot).
    public static let watch = ChartStyle(plotHeight: 92, plotWidth: 198, topInset: 12, bottomInset: 11, barCornerRadius: 2,
                                         gustLineWidth: 1.25, arrowSize: 7, sunRadius: 2.5, tickLabelOpacity: 0.6, isWatch: true)
    /// iPhone chart card (§6.1 / §8.1: 370 wide, 152 tall plot).
    public static let phone = ChartStyle(plotHeight: 152, plotWidth: 370, topInset: 22, bottomInset: 16, barCornerRadius: 1.5,
                                         gustLineWidth: 1.5, arrowSize: 9, sunRadius: 3, tickLabelOpacity: 0.6, isWatch: false)

    /// Bar width as a fraction of the slot.
    public static let barRatio: Double = 0.72

    /// Width of one hour slot in points for a given slot count.
    public func slotWidth(slots: Int) -> CGFloat { plotWidth / CGFloat(max(slots, 1)) }

    /// Half the tick-cap width expressed in seconds of chart time (cap = bar + 2 pt).
    public func capHalfWidthSeconds(slots: Int) -> TimeInterval {
        let slot = slotWidth(slots: slots)
        let barHours = Self.barRatio
        let extraHours = 2 / Double(slot)
        return (barHours + extraHours) / 2 * 3600
    }
}

/// The wind chart (HANDOFF §6): twilight shading, Beaufort bars, gust line with caps, sun dots,
/// now and horizon rules, direction arrows, hour ticks.
public struct WindChart: View {
    public var model: ChartModel
    public var style: ChartStyle

    public init(model: ChartModel, style: ChartStyle) {
        self.model = model
        self.style = style
    }

    private var theme: WindTheme { WindTheme(model.scheme) }
    private var ink: Color { theme.inkPrimary }
    private var numberInk: Color { Tokens.numberInk(model.scheme, tier: model.ageTier) }
    private var capHalf: TimeInterval { style.capHalfWidthSeconds(slots: model.slotCount) }
    private var yTicks: [Int] { Array(stride(from: 0, through: model.yMax, by: 10)) }

    public var body: some View {
        Chart {
            // Day/night shading, full plot height.
            RectangleMark(
                xStart: .value("Start", model.xRange.lowerBound),
                xEnd: .value("End", model.xRange.upperBound),
                yStart: .value("Floor", 0),
                yEnd: .value("Top", model.yMax)
            )
            .foregroundStyle(LinearGradient(stops: model.shadeStops, startPoint: .leading, endPoint: .trailing))

            // Sustained bars, Beaufort-stepped.
            ForEach(model.points) { p in
                BarMark(
                    x: .value("Hour", p.date, unit: .hour),
                    y: .value("Sustained", p.kn),
                    width: .ratio(ChartStyle.barRatio)
                )
                .foregroundStyle(Beaufort.color(step: p.step, scheme: model.scheme))
                .cornerRadius(style.barCornerRadius)
                .annotation(position: .bottom, spacing: style.bottomInset / 2 - style.arrowSize / 2) {
                    if p.index % model.arrowCadence == 0 {
                        ArrowView(dirFrom: p.dirFrom, size: style.arrowSize, color: numberInk)
                    }
                }
            }

            // Gust polyline through the cap centres, 75 % ink.
            ForEach(model.points) { p in
                LineMark(x: .value("Time", p.centre), y: .value("Gust", p.gust), series: .value("Series", "gust"))
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: style.gustLineWidth, lineJoin: .round))
                    .foregroundStyle(ink.opacity(0.75))
            }

            // Tick caps, bar + 2 wide, 100 % ink.
            ForEach(model.points) { p in
                RuleMark(
                    xStart: .value("CapStart", p.centre.addingTimeInterval(-capHalf)),
                    xEnd: .value("CapEnd", p.centre.addingTimeInterval(capHalf)),
                    y: .value("Gust", p.gust)
                )
                .lineStyle(StrokeStyle(lineWidth: style.gustLineWidth, lineCap: .round))
                .foregroundStyle(numberInk)
            }

            // Sun dots on the plot's top edge.
            ForEach(model.sunMarkers, id: \.self) { date in
                PointMark(x: .value("Sun", date), y: .value("Top", model.yMax))
                    .symbol(Circle())
                    .symbolSize(.pi * style.sunRadius * style.sunRadius)
                    .foregroundStyle(theme.sun)
            }

            // Now marker.
            if model.showsNow {
                RuleMark(x: .value("Now", model.nowDate))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .foregroundStyle(ink)
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("now")
                            .font(.system(size: style.isWatch ? 10 : 11, weight: .semibold))
                            .foregroundStyle(ink)
                            .padding(.leading, 4)
                    }
            }

            // Horizon edge.
            if let edge = model.horizonEdge {
                RuleMark(x: .value("Horizon", edge))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(ink.opacity(0.7))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        if let label = model.horizonLabel {
                            Text(label)
                                .font(.system(size: style.isWatch ? 10 : 11, weight: .semibold))
                                .foregroundStyle(ink.opacity(0.7))
                                .padding(.trailing, 4)
                                .fixedSize()
                        }
                    }
            }
        }
        .chartXScale(domain: model.xRange)
        .chartYScale(domain: 0...model.yMax)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: model.tickEvery)) { value in
                AxisTick(length: 3, stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(ink.opacity(0.5))
                AxisValueLabel(anchor: .top) {
                    if let date = value.as(Date.self) {
                        Text(TimeFormat.hh(date, tz: model.timeZone))
                            .font(Tokens.axisFont(watch: style.isWatch))
                            .foregroundStyle(ink.opacity(style.tickLabelOpacity))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yTicks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(ink.opacity(0.12))
                AxisValueLabel(anchor: .trailing) {
                    if let kn = value.as(Int.self), kn > 0 {
                        Text("\(kn)")
                            .font(.system(size: style.isWatch ? 10 : 11, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(ink.opacity(0.45))
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.frame(height: style.plotHeight)
        }
        .padding(.top, style.topInset)
        .environment(\.timeZone, model.timeZone)
        .oldStateDesaturation(model.ageTier)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        let hours = model.points.count
        let ends = model.points.last.map { TimeFormat.weekdayHHMM($0.date, tz: model.timeZone) } ?? ""
        return "\(hours)-hour wind chart: gusts to \(model.maxGust) knots, ends \(ends)"
    }
}
