import Foundation
import SwiftUI

/// Which hours a chart plots (HANDOFF §6.1, §6.3, §12a).
public enum ChartWindow: Sendable, Equatable {
    /// Every HRRR hour from `start` (phone and web 48 h range).
    case all
    /// Exactly 12 slots from `floor(nowIndex)` (watch strip); the tail stays empty past the horizon.
    case next12
    /// The rectangular complication strip (§6.3): 12 slots from `floor(nowIndex)` like `next12`,
    /// y domain `max(20, max gust rounded up to 5)`.
    case complication
    /// The 7-day range (§12a): HRRR to its horizon, then NBM 3-hour blocks to their end (at most
    /// 168 h from `start`). Without NBM it stops at the HRRR edge.
    case week

    /// Fixed slot count, or nil for "all hours".
    public var fixedSlots: Int? {
        switch self {
        case .all, .week: nil
        case .next12, .complication: 12
        }
    }
}

/// Where a plotted value comes from. HRRR owns every hour it covers; NBM only follows it (§12a).
public enum ForecastSource: Sendable, Hashable {
    case hrrr
    case nbm
}

/// One plotted slot: an HRRR hour, an aggregated 3-hour HRRR block (portrait 7 d, the slot rule),
/// or an NBM block.
public struct HourPoint: Sendable, Hashable, Identifiable {
    /// Hour offset of the slot's start from `forecast.start` (the HRRR hour index for HRRR hours).
    public var index: Int
    /// Slot start.
    public var date: Date
    public var kn: Int
    public var gust: Int
    public var dirFrom: Int
    public var step: Int
    /// Hours the slot covers (1, or 3 for a block).
    public var span: Int
    public var source: ForecastSource
    /// Temperature (°C), cloud (%) and precipitation (mm/h) when the payload has them: the hour's
    /// own, or the block's mean / mean / max.
    public var tempC: Double?
    public var cloud: Int?
    public var precip: Double?

    public var id: Int { index }
    /// Slot centre: where the gust line, cap and arrow sit.
    public var centre: Date { date.addingTimeInterval(TimeInterval(span) * 1800) }
    /// Slot end (exclusive).
    public var end: Date { date.addingTimeInterval(TimeInterval(span) * 3600) }
    public var isNBM: Bool { source == .nbm }

    public init(index: Int, date: Date, kn: Int, gust: Int, dirFrom: Int, step: Int, span: Int = 1,
                source: ForecastSource = .hrrr, tempC: Double? = nil, cloud: Int? = nil, precip: Double? = nil) {
        self.index = index
        self.date = date
        self.kn = kn
        self.gust = gust
        self.dirFrom = dirFrom
        self.step = step
        self.span = span
        self.source = source
        self.tempC = tempC
        self.cloud = cloud
        self.precip = precip
    }

    /// The slot's values as a forecast hour (readout, VoiceOver).
    public var hour: Forecast.Hour {
        Forecast.Hour(kn: kn, gust: gust, dirFrom: dirFrom, tempC: tempC, cloud: cloud, precip: precip)
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

/// A sun marker: sunrise is drawn filled, sunset as a ring (§5, 26 Oct).
public struct SunMarker: Sendable, Hashable {
    public var date: Date
    public var isRise: Bool

    public init(date: Date, isRise: Bool) {
        self.date = date
        self.isRise = isRise
    }
}

/// One cell of the sky band (§12b): a 3-hour span in slot space with its cloud cover and rain.
public struct SkyCell: Sendable, Hashable {
    /// Hour offset of the cell's start from the window start.
    public var slot: Int
    /// Hours covered (3; the last HRRR cell may be shorter).
    public var hours: Int
    public var cloud: Int
    public var precip: Double

    public init(slot: Int, hours: Int, cloud: Int, precip: Double) {
        self.slot = slot
        self.hours = hours
        self.cloud = cloud
        self.precip = precip
    }

    public var sky: SkyCondition { SkyCondition(cloud: cloud) }
    public var rain: Rain { Rain(mmPerHour: precip) }
}

/// Everything a chart needs, computed once from a `Forecast`. Views never read the payload.
/// Mirrors the inputs of `chart_reference.py::svg()` / `mixed_reference.py::mixed_svg()`: `start` =
/// `firstIndex`, `n` / `total` = `slotCount` (hours across the plot), `ymax`, the twilight stops,
/// sun events, `now`, the horizon edge and the HRRR→NBM seam, all in hour-slot space.
public struct ChartModel: Sendable {
    public let window: ChartWindow
    public let scheme: ColorScheme
    public let timeZone: TimeZone
    /// The plotted slots (at most `slotCount` hours; fewer when the horizon falls inside the window).
    public let points: [HourPoint]
    /// Forecast index of slot 0 (`start` in the reference).
    public let firstIndex: Int
    /// Number of hours across the plot (`n` in the reference); a slot is one hour wide.
    public let slotCount: Int
    /// Window start … window start + `slotCount` hours.
    public let xRange: ClosedRange<Date>
    /// `0 … yMax` (HANDOFF §6.1), over the plotted hours; the complication strip rounds to 5 and
    /// never drops below the domain it already showed for the run (§6.3).
    public let yMax: Int
    public let twilightStops: [TwilightStop]
    /// Sunrise / sunset instants inside `xRange`.
    public let sunMarkers: [Date]
    /// The same instants with their kind (rise filled, set ring).
    public let sunEvents: [SunMarker]
    public let nowDate: Date
    /// Fractional hour position of `now` relative to `forecast.start`.
    public let nowIndex: Double
    /// What the edge label names: the HRRR horizon (last hour), or in 7 d the last NBM block's
    /// end (`ends Tue 9am`).
    public let horizon: Date
    /// Slot at which the forecast ends (`lastHour + 1`, or the last block's end), when inside the window.
    public let horizonEdgeSlot: Int?
    public let ageTier: AgeTier
    /// First day name at slot 0, then one at each midnight among the plotted hours.
    public let dayLabels: [DayLabel]
    /// 7 d only: the HRRR→NBM seam (the HRRR edge), when NBM follows it.
    public let seamSlot: Int?
    /// 7 d only: NBM is missing, so the chart stops at the HRRR edge (`NBM unavailable`).
    public let nbmUnavailable: Bool
    /// Age tier of the NBM data (its own `fetched`), when NBM is plotted.
    public let nbmTier: AgeTier?
    /// HRRR plotted as 3-hour blocks (the slot rule: under 4 pt per hour).
    public let aggregatesHRRR: Bool
    /// The sky band's cells (§12b); empty when the payload has no cloud data.
    public let skyCells: [SkyCell]

    /// - Parameter plotWidth: the plot's width in points, for the 7-day slot rule (§12a): under 4 pt
    ///   per hour the whole chart is 3-hourly. Ignored by the other windows.
    /// - Parameter yMaxFloor: a domain the chart must not shrink below (the complication strip's
    ///   grow-only scale, `TimelineBuilder.stripDomains`).
    public init(forecast: Forecast, now: Date, window: ChartWindow, scheme: ColorScheme, plotWidth: CGFloat? = nil,
                yMaxFloor: Int? = nil) {
        self.window = window
        self.scheme = scheme
        self.timeZone = forecast.timeZone
        self.nowDate = now
        self.nowIndex = Derivations.nowIndex(forecast: forecast, now: now)
        self.ageTier = AgeTier.compute(fetched: forecast.fetched, now: now)

        let count = forecast.hours.count
        let firstIndex: Int
        let slots: Int
        // NBM blocks within 168 h of the start; never before the HRRR edge (`Forecast` enforces it).
        let blocks = window == .week
            ? (forecast.extended?.blocks ?? []).filter { $0.end <= forecast.start.addingTimeInterval(168 * 3600) }
            : []
        if let fixed = window.fixedSlots {
            firstIndex = min(max(Int(nowIndex.rounded(.down)), 0), max(count - 1, 0))
            slots = fixed
        } else {
            firstIndex = 0
            let end = blocks.last?.end ?? forecast.date(ofHour: count)
            slots = max(Int((end.timeIntervalSince(forecast.start) / 3600).rounded()), count)
        }
        let lastExclusive = min(firstIndex + slots, count)
        let pastHorizon = window != .all && window != .week && now > forecast.horizon
        let indices = (firstIndex < lastExclusive && !pastHorizon) ? Array(firstIndex..<lastExclusive) : []
        let aggregate = window == .week && plotWidth.map { $0 / CGFloat(max(slots, 1)) < 4 } == true
        self.aggregatesHRRR = aggregate

        var points: [HourPoint]
        if aggregate {
            points = stride(from: 0, to: indices.count, by: 3).map { s in
                let group = Array(indices[s..<min(s + 3, indices.count)])
                return Self.block(index: group[0], date: forecast.date(ofHour: group[0]), hours: group.map { forecast.hours[$0] }, source: .hrrr)
            }
        } else {
            points = indices.map { i in
                let h = forecast.hours[i]
                return HourPoint(index: i, date: forecast.date(ofHour: i), kn: h.kn, gust: h.gust, dirFrom: h.dirFrom,
                                 step: Beaufort.step(kn: h.kn), tempC: h.tempC, cloud: h.cloud, precip: h.precip)
            }
        }
        for b in blocks {
            let w = b.wind
            points.append(HourPoint(index: Int((b.start.timeIntervalSince(forecast.start) / 3600).rounded()), date: b.start,
                                    kn: w.kn, gust: w.gust, dirFrom: w.dirFrom, step: Beaufort.step(kn: w.kn), span: b.hours,
                                    source: .nbm, tempC: w.tempC, cloud: w.cloud, precip: w.precip))
        }
        self.points = points
        self.firstIndex = firstIndex
        self.slotCount = slots
        let windowStart = forecast.date(ofHour: firstIndex)
        let range = windowStart...windowStart.addingTimeInterval(TimeInterval(slots) * 3600)
        self.xRange = range
        let maxGust = points.map(\.gust).max() ?? 0
        let domain = window == .complication ? Derivations.stripYMax(maxGust: maxGust) : Derivations.yDomainMax(maxGust: maxGust)
        self.yMax = max(domain, yMaxFloor ?? 0)

        // The edge: the HRRR horizon, or the last NBM block's end in 7 d.
        let edgeDate = blocks.last?.end ?? forecast.horizon.addingTimeInterval(3600)
        self.horizon = blocks.last?.end ?? forecast.horizon
        // Nothing is drawn past the edge (HANDOFF §6.2: Fri dawn is not drawn): sun days that begin
        // after it are dropped and the shading holds flat. 7 d computes the days the payload lacks.
        let allSun = window == .week ? forecast.sunDays(through: edgeDate) : forecast.sun
        let sun = allSun.filter { $0.civilDawn <= edgeDate }
        self.twilightStops = Twilight.gradientStops(range: range, sun: sun)
        let events = sun.flatMap { [SunMarker(date: $0.sunrise, isRise: true), SunMarker(date: $0.sunset, isRise: false)] }
            .filter { range.contains($0.date) && $0.date <= edgeDate }
            .sorted { $0.date < $1.date }
        self.sunEvents = events
        self.sunMarkers = events.map(\.date)

        let edgeSlot = Int((edgeDate.timeIntervalSince(windowStart) / 3600).rounded())
        self.horizonEdgeSlot = (count > 0 && edgeSlot >= 0 && edgeSlot <= slots) ? edgeSlot : nil
        if window == .week, !blocks.isEmpty {
            self.seamSlot = count - firstIndex
            self.nbmTier = forecast.extended.map { AgeTier.compute(fetched: $0.fetched, now: now) }
        } else {
            self.seamSlot = nil
            self.nbmTier = nil
        }
        self.nbmUnavailable = window == .week && blocks.isEmpty

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = forecast.timeZone
        var days: [DayLabel] = []
        let dayHours = window == .week ? Array(0..<slots) : indices.map { $0 - firstIndex }
        for slot in dayHours {
            let date = windowStart.addingTimeInterval(TimeInterval(slot) * 3600)
            if slot == 0 || cal.component(.hour, from: date) == 0 {
                days.append(DayLabel(slot: slot, name: TimeFormat.weekdayShort(date, tz: forecast.timeZone)))
            }
        }
        self.dayLabels = days

        // Sky cells: HRRR hours in threes from index 0 (cloud mean, precip max), then NBM blocks.
        var cells: [SkyCell] = []
        if window == .all || window == .week, !forecast.hours.isEmpty,
           forecast.hours.allSatisfy({ $0.cloud != nil && $0.precip != nil }) {
            for s in stride(from: 0, to: count, by: 3) {
                let group = forecast.hours[s..<min(s + 3, count)]
                let cloud = Double(group.compactMap(\.cloud).reduce(0, +)) / Double(group.count)
                cells.append(SkyCell(slot: s - firstIndex, hours: group.count, cloud: Int(cloud.rounded()),
                                     precip: group.compactMap(\.precip).max() ?? 0))
            }
            for p in points where p.isNBM {
                guard let cloud = p.cloud else { continue }
                cells.append(SkyCell(slot: p.index - firstIndex, hours: p.span, cloud: cloud, precip: p.precip ?? 0))
            }
        }
        self.skyCells = cells
    }

    /// A 3-hour HRRR block (portrait 7 d): max sustained, max gust, vector-mean direction (as
    /// `mixed_reference.py::blocks3`); mean temperature and cloud, max precipitation.
    static func block(index: Int, date: Date, hours: [Forecast.Hour], source: ForecastSource) -> HourPoint {
        let kn = hours.map(\.kn).max() ?? 0
        let gust = hours.map(\.gust).max() ?? 0
        let x = hours.map { cos(Double($0.dirFrom) * .pi / 180) }.reduce(0, +)
        let y = hours.map { sin(Double($0.dirFrom) * .pi / 180) }.reduce(0, +)
        let dir = Int((atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360).rounded()) % 360
        func mean(_ v: [Double]) -> Double? { v.count == hours.count && !v.isEmpty ? v.reduce(0, +) / Double(v.count) : nil }
        let temp = mean(hours.compactMap(\.tempC))
        let cloud = mean(hours.compactMap { $0.cloud.map(Double.init) }).map { Int($0.rounded()) }
        let precip = hours.compactMap(\.precip).count == hours.count ? hours.compactMap(\.precip).max() : nil
        return HourPoint(index: index, date: date, kn: kn, gust: gust, dirFrom: dir, step: Beaufort.step(kn: kn),
                         span: hours.count, source: source, tempC: temp, cloud: cloud, precip: precip)
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

    /// Hours per NBM block (3), for the seam label `NBM · 3-hourly`.
    public var nbmStep: Int { points.first(where: \.isNBM)?.span ?? 3 }

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

    /// Point starting at a forecast index, when plotted.
    public func point(index: Int) -> HourPoint? {
        points.first { $0.index == index }
    }

    /// The plotted slot that covers hour offset `index` (a 3-hour block covers three).
    public func point(containing index: Int) -> HourPoint? {
        points.first { index >= $0.index && index < $0.index + $0.span }
    }

    /// The slot holding the peak gust across everything plotted (first on a tie): the 7-day peak chip.
    public var peakPoint: HourPoint? {
        points.reduce(nil) { best, p in (best.map { p.gust > $0.gust } ?? true) ? p : best }
    }
}
