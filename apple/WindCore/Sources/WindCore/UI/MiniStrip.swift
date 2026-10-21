import SwiftUI

/// Six-hour mini strip for the rectangular complication (HANDOFF §6.3): bars in Beaufort colours,
/// a 2 pt gust polyline with caps, a sun dot; no arrows, ticks or gridlines. Plain SwiftUI so it
/// renders inside WidgetKit without Swift Charts.
public struct MiniStrip: View {
    nonisolated public static let slots = 6

    public var forecast: Forecast
    public var now: Date
    public var scheme: ColorScheme

    public init(forecast: Forecast, now: Date, scheme: ColorScheme = .dark) {
        self.forecast = forecast
        self.now = now
        self.scheme = scheme
    }

    /// Prepared geometry inputs, exposed for tests.
    public struct Window: Sendable, Equatable {
        public var firstIndex: Int
        public var points: [HourPoint]
        public var yMax: Int
        public var range: ClosedRange<Date>
        public var sunMarkers: [Date]
        public var ageTier: AgeTier
    }

    nonisolated public static func window(forecast: Forecast, now: Date) -> Window {
        let count = forecast.hours.count
        let nowIndex = Derivations.nowIndex(forecast: forecast, now: now)
        let first = min(max(Int(nowIndex.rounded(.down)), 0), max(count - 1, 0))
        let lastExclusive = min(first + slots, count)
        let indices = (first < lastExclusive && now <= forecast.horizon) ? Array(first..<lastExclusive) : []
        let points = indices.map { i -> HourPoint in
            let h = forecast.hours[i]
            return HourPoint(index: i, date: forecast.date(ofHour: i), kn: h.kn, gust: h.gust, dirFrom: h.dirFrom, step: Beaufort.step(kn: h.kn))
        }
        let maxGust = points.map(\.gust).max() ?? 0
        let yMax = max(5, Int((Double(maxGust) / 5).rounded(.up)) * 5)
        let start = forecast.date(ofHour: first)
        let range = start...start.addingTimeInterval(TimeInterval(slots) * 3600)
        let sun = forecast.sun.flatMap { [$0.sunrise, $0.sunset] }.filter { range.contains($0) }.sorted()
        return Window(firstIndex: first, points: points, yMax: yMax, range: range, sunMarkers: sun,
                      ageTier: AgeTier.compute(fetched: forecast.fetched, now: now))
    }

    /// Pixel mapping for one layout pass (exposed for tests).
    public struct Geometry: Sendable {
        public let window: Window
        public let width: CGFloat
        public let height: CGFloat
        public let slot: CGFloat
        /// Bar width: 0.72 × slot, min 3.
        public let bar: CGFloat

        public init(window: Window, size: CGSize) {
            self.window = window
            self.width = size.width
            self.height = size.height
            self.slot = size.width / CGFloat(MiniStrip.slots)
            self.bar = max(3, slot * 0.72)
        }

        public func x(_ date: Date) -> CGFloat {
            let span = window.range.upperBound.timeIntervalSince(window.range.lowerBound)
            return width * CGFloat(date.timeIntervalSince(window.range.lowerBound) / span)
        }

        public func y(_ kn: Int) -> CGFloat { height - barHeight(kn: kn) }

        /// Bar height in points; 0 kn draws a 1 pt stub (HANDOFF §6.1).
        public func barHeight(kn: Int) -> CGFloat {
            kn <= 0 ? 1 : height * CGFloat(kn) / CGFloat(window.yMax)
        }
    }

    public var body: some View {
        let w = Self.window(forecast: forecast, now: now)
        let ink = Tokens.numberInk(scheme, tier: w.ageTier)
        GeometryReader { geo in
            let g = Geometry(window: w, size: geo.size)
            ZStack(alignment: .topLeading) {
                // Bars.
                ForEach(w.points) { p in
                    let h = g.barHeight(kn: p.kn)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Beaufort.color(step: p.step, scheme: scheme))
                        .frame(width: g.bar, height: h)
                        .position(x: g.x(p.centre), y: g.height - h / 2)
                }
                // Gust polyline, 75 % ink.
                Path { path in
                    for (i, p) in w.points.enumerated() {
                        let pt = CGPoint(x: g.x(p.centre), y: g.y(p.gust))
                        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                }
                .stroke(ink.opacity(0.75), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                // Caps, bar + 2 wide, 100 % ink.
                ForEach(w.points) { p in
                    TickCap(width: g.bar + 2, lineWidth: 2, color: ink)
                        .position(x: g.x(p.centre), y: g.y(p.gust))
                }
                // Sun dots on the top edge.
                ForEach(w.sunMarkers, id: \.self) { date in
                    SunDot(radius: 2.5, scheme: scheme)
                        .position(x: g.x(date), y: 2.5)
                }
            }
            .frame(width: g.width, height: g.height)
        }
        .oldStateDesaturation(w.ageTier)
        .accessibilityLabel(Text("Next 6 hours, gusts to \(w.points.map(\.gust).max() ?? 0) knots"))
    }
}
