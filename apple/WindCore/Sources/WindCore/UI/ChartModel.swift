import Foundation
import SwiftUI

/// Which hours a chart plots (HANDOFF §6.1, §6.3).
public enum ChartWindow: Sendable, Equatable {
    /// Every forecast hour from `start` (phone, web).
    case all
    /// Exactly 12 slots from `floor(nowIndex)` (watch strip); the tail stays empty past the horizon.
    case next12
    /// Exactly 6 slots from `floor(nowIndex)` (the first-package mini strip); y domain rounds to 5.
    case next6
    /// Exactly 12 slots from `floor(nowIndex)` for the rectangular complication (§6.3 round five).
    /// Y domain = max(20, max gust from the payload's first hour to the window end, rounded up to
    /// 5): it only grows as the window slides through one run and resets with a new payload.
    case complication12

    /// Fixed slot count, or nil for "all hours".
    public var fixedSlots: Int? {
        switch self {
        case .all: nil
        case .next12, .complication12: 12
        case .next6: 6
        }
    }
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

/// A day-band label: the slot it sits at and the weekday name (HANDOFF §6.4a).
public struct DayLabel: Sendable, Hashable {
    public var slot: Int
    public var name: String

    public init(slot: Int, name: String) {
        self.slot = slot
        self.name = name
    }
}

/// Everything a chart needs, computed once from a `Forecast`. Views never read the payload.
/// Mirrors the inputs of `chart_reference.py::svg()`: `start` = `firstIndex`, `n` = `slotCount`,
/// `ymax`, the twilight stops, sun events, `now` and the horizon edge, all in slot space.
public struct ChartModel: Sendable {
    public let window: ChartWindow
    public let scheme: ColorScheme
    public let timeZone: TimeZone
    /// The plotted hours (at most `slotCount`; fewer when the horizon falls inside the window).
    public let points: [HourPoint]
    /// Forecast index of slot 0 (`start` in the reference).
    public let firstIndex: Int
    /// Number of hour slots across the plot (`n` in the reference).
    public let slotCount: Int
    /// Window start … window start + `slotCount` hours.
    public let xRange: ClosedRange<Date>
    /// `0 … yMax` (HANDOFF §6.1), over the plotted hours; the mini strip rounds to 5 (§6.3).
    public let yMax: Int
    public let twilightStops: [TwilightStop]
    /// Sunrise / sunset instants inside `xRange`.
    public let sunMarkers: [Date]
    public let nowDate: Date
    /// Fractional hour position of `now` relative to `forecast.start`.
    public let nowIndex: Double
    /// Last forecast hour (inclusive).
    public let horizon: Date
    /// Slot at which the forecast ends (`lastHour + 1`), when inside the window.
    public let horizonEdgeSlot: Int?
    public let ageTier: AgeTier
    /// First day name at slot 0, then one at each midnight among the plotted hours.
    public let dayLabels: [DayLabel]

    public init(forecast: Forecast, now: Date, window: ChartWindow, scheme: ColorScheme) {
        self.window = window
        self.scheme = scheme
        self.timeZone = forecast.timeZone
        self.nowDate = now
        self.nowIndex = Derivations.nowIndex(forecast: forecast, now: now)
        self.ageTier = AgeTier.compute(fetched: forecast.fetched, now: now)
        self.horizon = forecast.horizon

        let count = forecast.hours.count
        let firstIndex: Int
        let slots: Int
        if let fixed = window.fixedSlots {
            firstIndex = min(max(Int(nowIndex.rounded(.down)), 0), max(count - 1, 0))
            slots = fixed
        } else {
            firstIndex = 0
            slots = count
        }
        let lastExclusive = min(firstIndex + slots, count)
        let pastHorizon = window != .all && now > forecast.horizon
        let indices = (firstIndex < lastExclusive && !pastHorizon) ? Array(firstIndex..<lastExclusive) : []
        self.points = indices.map { i in
            let h = forecast.hours[i]
            return HourPoint(index: i, date: forecast.date(ofHour: i), kn: h.kn, gust: h.gust, dirFrom: h.dirFrom, step: Beaufort.step(kn: h.kn))
        }
        self.firstIndex = firstIndex
        self.slotCount = slots
        let windowStart = forecast.date(ofHour: firstIndex)
        let range = windowStart...windowStart.addingTimeInterval(TimeInterval(slots) * 3600)
        self.xRange = range
        let plotted = indices.map { forecast.hours[$0] }
        if window == .complication12 {
            let runMax = forecast.hours.prefix(lastExclusive).map(\.gust).max() ?? 0
            self.yMax = max(20, Int((Double(runMax) / 5).rounded(.up)) * 5)
        } else if window == .next6 {
            let maxGust = plotted.map(\.gust).max() ?? 0
            self.yMax = max(5, Int((Double(maxGust) / 5).rounded(.up)) * 5)
        } else {
            self.yMax = Derivations.yDomainMax(hours: plotted)
        }
        // Nothing is drawn past the horizon edge (HANDOFF §6.2: Fri dawn is not drawn): sun days
        // that begin after the edge are dropped and the shading holds flat.
        let edgeDate = forecast.horizon.addingTimeInterval(3600)
        let sun = forecast.sun.filter { $0.civilDawn <= edgeDate }
        self.twilightStops = Twilight.gradientStops(range: range, sun: sun)
        self.sunMarkers = sun.flatMap { [$0.sunrise, $0.sunset] }.filter { range.contains($0) && $0 <= edgeDate }.sorted()

        let edgeSlot = count - firstIndex
        self.horizonEdgeSlot = (count > 0 && edgeSlot >= 0 && edgeSlot <= slots) ? edgeSlot : nil

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = forecast.timeZone
        var days: [DayLabel] = []
        for (slot, i) in indices.enumerated() {
            let date = forecast.date(ofHour: i)
            if slot == 0 || cal.component(.hour, from: date) == 0 {
                days.append(DayLabel(slot: slot, name: TimeFormat.weekdayShort(date, tz: forecast.timeZone)))
            }
        }
        self.dayLabels = days
    }

    /// Fractional slot position of an instant (0 at the window start).
    public func slot(of date: Date) -> Double {
        date.timeIntervalSince(xRange.lowerBound) / 3600
    }

    /// Hour start at a slot.
    public func date(ofSlot slot: Int) -> Date {
        xRange.lowerBound.addingTimeInterval(TimeInterval(slot) * 3600)
    }

    /// Local hour of day (0…23) of a slot's hour start.
    public func hourOfDay(slot: Int) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.component(.hour, from: date(ofSlot: slot))
    }

    /// `now` in slot space.
    public var nowSlot: Double { slot(of: nowDate) }

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

    /// Point for a forecast index, when plotted.
    public func point(index: Int) -> HourPoint? {
        points.first { $0.index == index }
    }
}
