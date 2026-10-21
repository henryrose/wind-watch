import Foundation
import SwiftUI

/// Which hours a chart plots (HANDOFF §6.1).
public enum ChartWindow: Sendable, Equatable {
    /// Every forecast hour from `start` (phone, web).
    case all
    /// Exactly 12 slots from `floor(nowIndex)` (watch strip); the tail stays empty past the horizon.
    case next12
}

/// One plotted hour.
public struct HourPoint: Sendable, Hashable, Identifiable {
    public var index: Int
    /// Hour start.
    public var date: Date
    public var kn: Int
    public var gust: Int
    public var dirFrom: Int
    public var step: Int

    public var id: Int { index }
    /// Slot centre (hour start + 30 min): where the gust line, cap and arrow sit.
    public var centre: Date { date.addingTimeInterval(1800) }

    public init(index: Int, date: Date, kn: Int, gust: Int, dirFrom: Int, step: Int) {
        self.index = index
        self.date = date
        self.kn = kn
        self.gust = gust
        self.dirFrom = dirFrom
        self.step = step
    }
}

/// Everything a chart needs, computed once from a `Forecast`. Views never read the payload.
public struct ChartModel: Sendable {
    public let window: ChartWindow
    public let scheme: ColorScheme
    public let timeZone: TimeZone
    public let points: [HourPoint]
    /// Window start … last plotted hour + 1 h (`.all`), or exactly 12 h (`.next12`).
    public let xRange: ClosedRange<Date>
    /// Number of hour slots across `xRange`.
    public let slotCount: Int
    /// `0 … yMax` (HANDOFF §6.1), over the plotted hours.
    public let yMax: Int
    public let twilightStops: [TwilightStop]
    /// Sunrise / sunset instants inside `xRange`.
    public let sunMarkers: [Date]
    public let nowDate: Date
    /// Fractional hour position of `now` relative to `forecast.start`.
    public let nowIndex: Double
    /// `lastHour + 1 h` when it lies inside the window, else nil.
    public let horizonEdge: Date?
    /// `HRRR ends 05:00`, or `ends 05:00` when the edge is within 12 slots of now; nil when no edge.
    public let horizonLabel: String?
    public let ageTier: AgeTier
    /// Draw an arrow on every n-th bar: 1 (watch 12-h strip) or 3 (phone).
    public let arrowCadence: Int
    /// Time tick every n hours: 3 (watch) or 6 (phone).
    public let tickEvery: Int

    public init(forecast: Forecast, now: Date, window: ChartWindow, scheme: ColorScheme) {
        self.window = window
        self.scheme = scheme
        self.timeZone = forecast.timeZone
        self.nowDate = now
        self.nowIndex = Derivations.nowIndex(forecast: forecast, now: now)
        self.ageTier = AgeTier.compute(fetched: forecast.fetched, now: now)

        let count = forecast.hours.count
        let firstIndex: Int
        let slots: Int
        switch window {
        case .all:
            firstIndex = 0
            slots = count
            arrowCadence = 3
            tickEvery = 6
        case .next12:
            firstIndex = min(max(Int(nowIndex.rounded(.down)), 0), max(count - 1, 0))
            slots = 12
            arrowCadence = 1
            tickEvery = 3
        }
        let lastExclusive = min(firstIndex + slots, count)
        let indices = firstIndex < lastExclusive ? Array(firstIndex..<lastExclusive) : []
        self.points = indices.map { i in
            let h = forecast.hours[i]
            return HourPoint(index: i, date: forecast.date(ofHour: i), kn: h.kn, gust: h.gust, dirFrom: h.dirFrom, step: Beaufort.step(kn: h.kn))
        }
        self.slotCount = slots
        let windowStart = forecast.date(ofHour: firstIndex)
        let range = windowStart...windowStart.addingTimeInterval(TimeInterval(slots) * 3600)
        self.xRange = range
        self.yMax = Derivations.yDomainMax(hours: indices.map { forecast.hours[$0] })
        self.twilightStops = Twilight.gradientStops(range: range, sun: forecast.sun)
        self.sunMarkers = forecast.sun.flatMap { [$0.sunrise, $0.sunset] }.filter { range.contains($0) }.sorted()

        let edge = forecast.horizon.addingTimeInterval(3600)
        if count > 0, range.contains(edge) {
            self.horizonEdge = edge
            let edgeIndex = Double(count)
            let short = edgeIndex - nowIndex <= 12
            self.horizonLabel = Derivations.horizonLabel(forecast: forecast, short: short)
        } else {
            self.horizonEdge = nil
            self.horizonLabel = nil
        }
    }

    /// Whether the now marker falls inside the plotted range.
    public var showsNow: Bool { xRange.contains(nowDate) }

    /// Window max gust (for the watch strip header `gusts to 15`).
    public var maxGust: Int { points.map(\.gust).max() ?? 0 }

    /// Gradient stops as colours for the day-shade rectangle: dark = white at 7 % × day,
    /// light = black at 8 % × (1 − day).
    public var shadeStops: [Gradient.Stop] {
        twilightStops.map { stop in
            let color: Color = scheme == .dark
                ? Color.white.opacity(0.07 * stop.value)
                : Color.black.opacity(0.08 * (1 - stop.value))
            return Gradient.Stop(color: color, location: stop.fraction)
        }
    }
}
