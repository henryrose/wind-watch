import Foundation

/// One gradient stop for day/night shading: `fraction` along the plotted range (0…1), `value`
/// 1 = full day, 0 = night.
public struct TwilightStop: Sendable, Hashable {
    public var fraction: Double
    public var value: Double

    public init(fraction: Double, value: Double) {
        self.fraction = fraction
        self.value = value
    }
}

/// Day/night shading (HANDOFF §2 "Twilight / shading fraction").
///
/// `day(at:)` is 1 inside [sunrise, sunset], 0 inside [civilDusk, next civilDawn], and ramps
/// linearly across [civilDawn, sunrise] and [sunset, civilDusk]. Outside the covered sun days the
/// nearest defined value is held (0 before the first dawn and after the last dusk).
public enum Twilight {
    /// Shading value at an instant.
    public static func day(at t: Date, sun: [Forecast.SunDay]) -> Double {
        let points = breakpoints(sun: sun)
        guard let first = points.first, let last = points.last else { return 1 }
        if t <= first.date { return first.value }
        if t >= last.date { return last.value }
        // points are sorted; find the segment containing t.
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            if t <= b.date {
                let span = b.date.timeIntervalSince(a.date)
                if span <= 0 { return b.value }
                let f = t.timeIntervalSince(a.date) / span
                return a.value + (b.value - a.value) * f
            }
        }
        return last.value
    }

    /// Gradient stops over `range`: a stop at fraction 0 and 1 with the held values plus one at
    /// each dawn/rise/set/dusk inside the range (sorted, de-duplicated by fraction).
    public static func gradientStops(range: ClosedRange<Date>, sun: [Forecast.SunDay]) -> [TwilightStop] {
        let span = range.upperBound.timeIntervalSince(range.lowerBound)
        let startValue = day(at: range.lowerBound, sun: sun)
        guard span > 0 else {
            return [TwilightStop(fraction: 0, value: startValue), TwilightStop(fraction: 1, value: startValue)]
        }
        var stops = [TwilightStop(fraction: 0, value: startValue)]
        for p in breakpoints(sun: sun) where range.contains(p.date) {
            stops.append(TwilightStop(fraction: p.date.timeIntervalSince(range.lowerBound) / span, value: p.value))
        }
        stops.append(TwilightStop(fraction: 1, value: day(at: range.upperBound, sun: sun)))
        stops.sort { $0.fraction < $1.fraction }
        var out: [TwilightStop] = []
        for s in stops where out.last.map({ abs($0.fraction - s.fraction) > 1e-9 }) ?? true {
            out.append(s)
        }
        return out
    }

    struct Breakpoint: Sendable { var date: Date; var value: Double }

    /// dawn 0 → rise 1 → set 1 → dusk 0 for each day, sorted by time. Linear interpolation between
    /// consecutive points reproduces the piecewise definition (dusk→next dawn is flat 0).
    static func breakpoints(sun: [Forecast.SunDay]) -> [Breakpoint] {
        sun.flatMap { d in
            [
                Breakpoint(date: d.civilDawn, value: 0),
                Breakpoint(date: d.sunrise, value: 1),
                Breakpoint(date: d.sunset, value: 1),
                Breakpoint(date: d.civilDusk, value: 0),
            ]
        }
        .sorted { $0.date < $1.date }
    }
}
