import Foundation

/// Pure derivations over a `Forecast` (HANDOFF §2, §5, §6.1, §8.1).
public enum Derivations {
    /// Fractional hours between `start` and `now`. Negative before `start`; never clamped here.
    public static func nowIndex(forecast: Forecast, now: Date) -> Double {
        now.timeIntervalSince(forecast.start) / 3600
    }

    /// Index of the hero hour: `floor(nowIndex)` clamped to 0, or nil when `now > horizon`.
    public static func heroIndex(forecast: Forecast, now: Date) -> Int? {
        guard now <= forecast.horizon, !forecast.hours.isEmpty else { return nil }
        let i = Int(nowIndex(forecast: forecast, now: now).rounded(.down))
        return min(max(i, 0), forecast.hours.count - 1)
    }

    /// The hour shown in the hero, or nil past the horizon.
    public static func hero(forecast: Forecast, now: Date) -> Forecast.Hour? {
        heroIndex(forecast: forecast, now: now).map { forecast.hours[$0] }
    }

    /// Chart Y upper bound: `max(20, ceil((maxGust + 3) / 10) × 10)`, over the hours plotted.
    public static func yDomainMax(hours: [Forecast.Hour]) -> Int {
        yDomainMax(maxGust: hours.map(\.gust).max() ?? 0)
    }

    /// `max(20, ceil((maxGust + 3) / 10) × 10)`.
    public static func yDomainMax(maxGust: Int) -> Int {
        let rounded = Int((Double(maxGust + 3) / 10).rounded(.up)) * 10
        return max(20, rounded)
    }

    /// Complication strip Y upper bound (§6.3): `max(20, maxGust rounded up to 5)`.
    public static func stripYMax(maxGust: Int) -> Int {
        max(20, Int((Double(maxGust) / 5).rounded(.up)) * 5)
    }

    /// `HRRR ends 05:00`; `short` drops the model name (`ends 05:00`) when the edge is near the now marker.
    public static func horizonLabel(forecast: Forecast, tz: TimeZone? = nil, short: Bool = false) -> String {
        let time = TimeFormat.hhmm(forecast.horizon, tz: tz ?? forecast.timeZone)
        return short ? "ends \(time)" : "HRRR ends \(time)"
    }

    /// `ends Fri 5am` — the phone/web header suffix and chart edge label (HANDOFF §6.4a).
    public static func horizonWeekdayLabel(forecast: Forecast, tz: TimeZone? = nil) -> String {
        "ends " + TimeFormat.weekdayHour12(forecast.horizon, tz: tz ?? forecast.timeZone)
    }

    /// Chart card title: `Wed 9am → Fri 5am` (HANDOFF §6.4a).
    public static func chartTitle(forecast: Forecast, tz: TimeZone? = nil) -> String {
        let zone = tz ?? forecast.timeZone
        return TimeFormat.weekdayHour12(forecast.start, tz: zone) + " → " + TimeFormat.weekdayHour12(forecast.horizon, tz: zone)
    }

    /// Scrub readout label for hour `index`: `Thu 12am · midnight`.
    public static func scrubLabel(forecast: Forecast, index: Int, tz: TimeZone? = nil) -> String {
        TimeFormat.scrubLabel(forecast.date(ofHour: index), tz: tz ?? forecast.timeZone)
    }

    /// The readout's idle label (HANDOFF §6.4d): `Now · Wed 9:25am`.
    public static func nowLabel(now: Date, tz: TimeZone) -> String {
        "Now · " + TimeFormat.weekdayShort(now, tz: tz) + " " + TimeFormat.hourMinute12(now, tz: tz)
    }

    /// Rows the hourly table shows: the hero hour to the horizon (0 past the horizon).
    public static func tableHourCount(forecast: Forecast, now: Date) -> Int {
        guard let first = heroIndex(forecast: forecast, now: now) else { return 0 }
        return max(forecast.hours.count - first, 0)
    }

    /// The table disclosure caption (§6.4d): `45 hours · Wed 9am → Fri 5am`.
    public static func tableCaption(forecast: Forecast, now: Date, tz: TimeZone? = nil) -> String {
        let zone = tz ?? forecast.timeZone
        let n = tableHourCount(forecast: forecast, now: now)
        let hours = n == 1 ? "1 hour" : "\(n) hours"
        guard let first = heroIndex(forecast: forecast, now: now) else { return hours }
        return hours + " · " + TimeFormat.weekdayHour12(forecast.date(ofHour: first), tz: zone) + " → " + TimeFormat.weekdayHour12(forecast.horizon, tz: zone)
    }

    /// Period of the local day used by `relativeTimePhrase`.
    public enum DayPeriod: Sendable, Equatable {
        case morning      // 05:00–11:59
        case afternoon    // 12:00–16:59
        case evening      // 17:00–22:59
        case midnight     // 23:00–00:59
        case overnight    // 01:00–04:59

        public static func of(hour: Int) -> DayPeriod {
            switch hour {
            case 5...11: .morning
            case 12...16: .afternoon
            case 17...22: .evening
            case 23, 0: .midnight
            default: .overnight
            }
        }
    }

    /// Relative phrase for a time (HANDOFF §8.1): `this morning`, `this afternoon`, `this evening`,
    /// `around midnight`, `overnight`, `tomorrow morning`, `tomorrow night`, `Friday afternoon`, …
    ///
    /// A night (23:00–04:59) belongs to the day that precedes it: at 09:00 on Wednesday a peak at
    /// 00:00 Thursday is "around midnight", not "tomorrow". Day periods use calendar days.
    public static func relativeTimePhrase(for date: Date, now: Date, tz: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let period = DayPeriod.of(hour: cal.component(.hour, from: date))
        let isNight = period == .midnight || period == .overnight
        // Nights (23:00–04:59) belong to the day that precedes them, so the target's day is
        // anchored at 05:00. "Now" is anchored the same way only when comparing nights; for day
        // periods it uses the plain calendar day, so at 02:00 Thursday 10:00 is "this morning"
        // while 00:00 is still "around midnight".
        let shift: TimeInterval = -5 * 3600
        let dateDay = cal.startOfDay(for: date.addingTimeInterval(shift))
        let nowDay = cal.startOfDay(for: isNight ? now.addingTimeInterval(shift) : now)
        let diff = cal.dateComponents([.day], from: nowDay, to: dateDay).day ?? 0

        switch diff {
        case 0:
            switch period {
            case .morning: return "this morning"
            case .afternoon: return "this afternoon"
            case .evening: return "this evening"
            case .midnight: return "around midnight"
            case .overnight: return "overnight"
            }
        case 1:
            switch period {
            case .morning: return "tomorrow morning"
            case .afternoon: return "tomorrow afternoon"
            case .evening: return "tomorrow evening"
            case .midnight, .overnight: return "tomorrow night"
            }
        case -1:
            switch period {
            case .morning: return "yesterday morning"
            case .afternoon: return "yesterday afternoon"
            case .evening: return "yesterday evening"
            case .midnight, .overnight: return "last night"
            }
        default:
            let weekday = TimeFormat.weekdayLong(dateDay, tz: tz)
            switch period {
            case .morning: return "\(weekday) morning"
            case .afternoon: return "\(weekday) afternoon"
            case .evening: return "\(weekday) evening"
            case .midnight, .overnight: return "\(weekday) night"
            }
        }
    }

    /// `25 kn gusts around midnight` (phone peak-gust chip, HANDOFF §8.1).
    public static func peakGustChipText(forecast: Forecast, now: Date, tz: TimeZone? = nil) -> String {
        let phrase = relativeTimePhrase(for: forecast.peakGust.at, now: now, tz: tz ?? forecast.timeZone)
        return "\(forecast.peakGust.kn) kn gusts \(phrase)"
    }

    /// `peak G25 · 12am` (round five readout, HANDOFF §6.4d). The day is added (`peak G25 · Thu 3pm`)
    /// when the peak is 18 h or more away, where an hour alone would be ambiguous.
    public static func peakReadoutText(forecast: Forecast, now: Date, tz: TimeZone? = nil) -> String {
        let zone = tz ?? forecast.timeZone
        let at = forecast.peakGust.at
        let when = at.timeIntervalSince(now) < 18 * 3600
            ? TimeFormat.hour12(hour: TimeFormat.hour(at, tz: zone))
            : TimeFormat.weekdayHour12(at, tz: zone)
        return "peak G\(forecast.peakGust.kn) · \(when)"
    }

    /// Hero VoiceOver label: `15 knots, gusting 25, from the west, as of 23:30`.
    public static func heroAccessibilityLabel(hour: Forecast.Hour, forecast: Forecast, tz: TimeZone? = nil) -> String {
        let asOf = TimeFormat.hhmm(forecast.fetched, tz: tz ?? forecast.timeZone)
        return "\(hour.kn) knots, gusting \(hour.gust), \(Compass.spokenFromText(dirFrom: hour.dirFrom)), as of \(asOf)"
    }
}

extension Forecast {
    public func nowIndex(at now: Date) -> Double { Derivations.nowIndex(forecast: self, now: now) }
    public func heroIndex(at now: Date) -> Int? { Derivations.heroIndex(forecast: self, now: now) }
    public func hero(at now: Date) -> Hour? { Derivations.hero(forecast: self, now: now) }
    public var yDomainMax: Int { Derivations.yDomainMax(hours: hours) }
    public var horizonLabel: String { Derivations.horizonLabel(forecast: self) }
}
