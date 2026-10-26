import Foundation

/// Cloud cover in three tones (§12b): < 25 % clear, 25–70 % partly cloudy, ≥ 70 % overcast.
public enum SkyCondition: Sendable, Equatable {
    case clear
    case partlyCloudy
    case overcast

    public init(cloud: Int) {
        self = cloud < 25 ? .clear : (cloud < 70 ? .partlyCloudy : .overcast)
    }

    /// `Clear`, `Partly cloudy`, `Overcast` (readout text).
    public var label: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly cloudy"
        case .overcast: "Overcast"
        }
    }
}

/// Rain in three steps (§12b, `sky_reference.py`): none at 0; light < 0.5; rain < 1.5; heavy from 1.5 mm/h.
public enum Rain: Sendable, Equatable {
    case none
    case light
    case moderate
    case heavy

    public init(mmPerHour mm: Double) {
        if mm <= 0 { self = .none } else if mm < 0.5 { self = .light } else if mm < 1.5 { self = .moderate } else { self = .heavy }
    }

    /// `light rain`, `rain`, `heavy rain`; nil when dry.
    public var label: String? {
        switch self {
        case .none: nil
        case .light: "light rain"
        case .moderate: "rain"
        case .heavy: "heavy rain"
        }
    }

    /// Blue ticks hanging from the sky band cell: 0…3.
    public var ticks: Int {
        switch self {
        case .none: 0
        case .light: 1
        case .moderate: 2
        case .heavy: 3
        }
    }
}

/// Temperature display unit (§12b). Default °F; the iPhone About screen switches it. Stored in the
/// App Group defaults under `tempUnit` so the watch could read it (it shows no temperature today).
public enum TemperatureUnit: String, Sendable, CaseIterable {
    case fahrenheit = "F"
    case celsius = "C"

    public static let storageKey = "tempUnit"

    /// `°F` / `°C`.
    public var symbol: String { self == .fahrenheit ? "°F" : "°C" }

    /// Integer degrees in this unit.
    public func degrees(celsius c: Double) -> Int {
        Int((self == .fahrenheit ? c * 9 / 5 + 32 : c).rounded())
    }

    /// `48°F`.
    public func format(celsius c: Double) -> String { "\(degrees(celsius: c))\(symbol)" }

    /// VoiceOver: `48 degrees Fahrenheit`.
    public func spoken(celsius c: Double) -> String {
        "\(degrees(celsius: c)) degrees " + (self == .fahrenheit ? "Fahrenheit" : "Celsius")
    }
}

/// The phone chart's range (§12a): `48 h` (default, HRRR only) or `7 d` (HRRR, then NBM).
public enum ChartRange: String, Sendable, CaseIterable {
    case hours48 = "48h"
    case days7 = "7d"

    public static let storageKey = "chartRange"

    /// `48 h` / `7 d` (segmented control).
    public var label: String { self == .hours48 ? "48 h" : "7 d" }
    public var spoken: String { self == .hours48 ? "48 hours" : "7 days" }
    public var window: ChartWindow { self == .hours48 ? .all : .week }
}

extension Derivations {
    /// Readout label for a plotted slot: `Thu 12am · midnight` for an hour, `Sat 12–3pm` for a block.
    public static func slotLabel(_ p: HourPoint, tz: TimeZone) -> String {
        p.span > 1 ? TimeFormat.span(p.date, hours: p.span, tz: tz) : TimeFormat.scrubLabel(p.date, tz: tz)
    }

    /// VoiceOver form of a slot's time: `Thursday 00:00`, or `Saturday 12 to 3pm, NBM` for a block.
    public static func spokenSlot(_ p: HourPoint, tz: TimeZone) -> String {
        let day = TimeFormat.weekdayLong(p.date, tz: tz)
        guard p.span > 1 else { return day + " " + TimeFormat.hhmm(p.date, tz: tz) }
        let span = TimeFormat.span(p.date, hours: p.span, tz: tz).split(separator: " ").dropFirst().joined(separator: " ")
            .replacingOccurrences(of: "–", with: " to ")
        return day + " " + span + (p.isNBM ? ", NBM" : "")
    }

    /// Scrub detail after the label (§12b): `Overcast · rain · 48°F`; nil when the payload has no
    /// sky or temperature data. Never in the hero, complications or chart.
    public static func skyDetail(_ h: Forecast.Hour, unit: TemperatureUnit) -> String? {
        var parts: [String] = []
        if let cloud = h.cloud { parts.append(SkyCondition(cloud: cloud).label) }
        if let rain = h.precip.flatMap({ Rain(mmPerHour: $0).label }) { parts.append(rain) }
        if let t = h.tempC { parts.append(unit.format(celsius: t)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// VoiceOver form of `skyDetail`: `overcast, rain, 48 degrees Fahrenheit`.
    public static func skyDetailSpoken(_ h: Forecast.Hour, unit: TemperatureUnit) -> String? {
        var parts: [String] = []
        if let cloud = h.cloud { parts.append(SkyCondition(cloud: cloud).label.lowercased()) }
        if let rain = h.precip.flatMap({ Rain(mmPerHour: $0).label }) { parts.append(rain) }
        if let t = h.tempC { parts.append(unit.spoken(celsius: t)) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Readout right column at rest (§6.4d, §12a). 48 h: `peak G25 · 12am` from the payload's HRRR
    /// peak, the weekday added once the peak is past tonight. 7 d: the peak across everything
    /// plotted, `peak G32 · Sat 1pm · NBM` (a block names its middle hour; HRRR carries no tag).
    public static func peakText(forecast: Forecast, chart: ChartModel?, now: Date) -> String {
        let tz = forecast.timeZone
        if let chart, chart.window == .week, let p = chart.peakPoint {
            // An HRRR peak names its own hour even when the chart draws HRRR in 3-hour blocks.
            let at = p.isNBM ? p.date.addingTimeInterval(TimeInterval(p.span / 2) * 3600) : forecast.peakGust.at
            return "peak G\(p.gust) · " + TimeFormat.weekdayHour12(at, tz: tz) + (p.isNBM ? " · NBM" : "")
        }
        let at = forecast.peakGust.at
        let phrase = relativeTimePhrase(for: at, now: now, tz: tz)
        let tonight = phrase.hasPrefix("this ") || phrase == "around midnight" || phrase == "overnight"
        let time = tonight ? TimeFormat.hour12(hour: TimeFormat.hour(at, tz: tz)) : TimeFormat.weekdayHour12(at, tz: tz)
        return "peak G\(forecast.peakGust.kn) · " + time
    }

    /// VoiceOver form of `peakText`: `peak gust 32 knots, Saturday 1pm, NBM`.
    public static func peakSpoken(forecast: Forecast, chart: ChartModel?, now: Date) -> String {
        peakText(forecast: forecast, chart: chart, now: now)
            .replacingOccurrences(of: "peak G", with: "peak gust ")
            .replacingOccurrences(of: " · ", with: ", ")
    }

    /// 7 d chart title: `Wed 9am → Tue 9am` (to the NBM end), or the 48 h title without NBM.
    public static func weekTitle(forecast: Forecast) -> String {
        guard let e = forecast.extended else { return chartTitle(forecast: forecast) }
        return TimeFormat.weekdayHour12(forecast.start, tz: forecast.timeZone) + " → " + TimeFormat.weekdayHour12(e.end, tz: forecast.timeZone)
    }

    /// 7 d subtitle: `HRRR hourly · NBM 3-hourly after Fri 5am`, or `NBM unavailable · HRRR to Fri 5am`.
    public static func weekSubtitle(forecast: Forecast) -> String {
        let edge = TimeFormat.weekdayHour12(forecast.horizon, tz: forecast.timeZone)
        guard forecast.extended != nil else { return "NBM unavailable · HRRR to \(edge)" }
        return "HRRR hourly · NBM 3-hourly after \(edge)"
    }

    /// `ends Tue 9am` (7 d header suffix and edge label), falling back to the HRRR horizon.
    public static func weekEndLabel(forecast: Forecast) -> String {
        guard let e = forecast.extended else { return horizonWeekdayLabel(forecast: forecast) }
        return "ends " + TimeFormat.weekdayHour12(e.end, tz: forecast.timeZone)
    }

    /// 7 d table disclosure caption: `7 days · NBM after Fri 5am`.
    public static func weekTableCaption(forecast: Forecast, now: Date) -> String {
        guard forecast.extended != nil else {
            let n = tableHourCount(forecast: forecast, now: now)
            return (n == 1 ? "1 hour" : "\(n) hours") + " · NBM unavailable"
        }
        return "7 days · NBM after " + TimeFormat.weekdayHour12(forecast.horizon, tz: forecast.timeZone)
    }

    /// The table's one-line NBM header: `NBM from Fri 6am · 3-hourly` (the first block's start).
    public static func nbmTableHeader(forecast: Forecast) -> String? {
        guard let e = forecast.extended else { return nil }
        return "NBM from " + TimeFormat.weekdayHour12(e.from, tz: forecast.timeZone) + " · \(e.step)-hourly"
    }
}

extension TimeFormat {
    /// A block's span (§12a): `Sat 12–3pm`, `Fri 9am–12pm`, `Sun 9pm–12am`.
    public static func span(_ start: Date, hours: Int, tz: TimeZone) -> String {
        let h0 = hour(start, tz: tz)
        let h1 = hour(start.addingTimeInterval(TimeInterval(hours) * 3600), tz: tz)
        let a = hour12(hour: h0), b = hour12(hour: h1)
        let sameHalf = (h0 < 12) == (h1 < 12) && h1 != 0 && h1 > h0
        let first = sameHalf ? String(a.dropLast(2)) : a
        return weekdayShort(start, tz: tz) + " " + first + "–" + b
    }
}

extension AppGroupStore {
    /// The App Group `UserDefaults` for an app's bundle info (`WWBundlePrefix`), the same suite
    /// `ForecastSession.defaults` uses; `.standard` when the group is unavailable. For
    /// `@AppStorage(…, store:)` settings shared with the watch, such as `tempUnit`.
    public static func sharedDefaults(bundleInfo: [String: Any]) -> UserDefaults {
        let prefix = (bundleInfo["WWBundlePrefix"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "com.example"
        return UserDefaults(suiteName: groupID(bundlePrefix: prefix)) ?? .standard
    }
}
