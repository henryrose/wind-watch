import Foundation
import SwiftUI
import WidgetKit
import WindCore

/// One complication timeline entry: a date plus an index into one shared forecast (DESIGN §5.2).
/// Compiled into the widget extension and (for the DEBUG preview page) the watch app.
struct WindEntry: TimelineEntry, Sendable {
    let date: Date
    let forecast: Forecast?
    let hourIndex: Int?
    let trust: TrustState
    let isDefault: Bool
    /// The rectangular strip's grow-only y domain for this entry (`TimelineBuilder.stripDomains`);
    /// nil uses the window's own.
    var stripYMax: Int? = nil

    /// The hour to render, nil when numbers must not be shown.
    var hour: Forecast.Hour? {
        guard let forecast, let hourIndex, trust.showsNumbers, forecast.hours.indices.contains(hourIndex) else { return nil }
        return forecast.hours[hourIndex]
    }

    var tier: AgeTier {
        forecast.map { AgeTier.compute(fetched: $0.fetched, now: date) } ?? .fresh
    }

    /// Stale, old or offline: amber text, dashed rings.
    var isAmber: Bool { trust.isAmber }

    var timeZone: TimeZone { forecast?.timeZone ?? .current }

    /// `as of 23:30` (fresh, stale) / `Tue 13:05` (old) — the rectangular trust text (HANDOFF §7.1).
    var asOfText: String {
        guard let forecast else { return "" }
        switch tier {
        case .old: return TimeFormat.weekdayHHMM(forecast.fetched, tz: timeZone)
        default: return "as of " + TimeFormat.hhmm(forecast.fetched, tz: timeZone)
        }
    }

    /// `15Z Tue`: the last run, right of `No forecast` on the past-horizon rectangular.
    var lastRunText: String {
        guard let forecast else { return "" }
        let hour = forecast.run.replacingOccurrences(of: "HRRR ", with: "")
        return "\(hour) \(TimeFormat.weekdayShort(forecast.runDate, tz: timeZone))"
    }

    /// `15Z Tue`: the past-horizon rectangular's right-hand run label (round five).
    var runShortText: String {
        guard let forecast else { return "" }
        let hour = forecast.run.replacingOccurrences(of: "HRRR ", with: "")
        return "\(hour) \(TimeFormat.weekdayShort(forecast.runDate, tz: timeZone))"
    }

    static func make(forecast: Forecast, at date: Date, lastCheckOK: Bool = true, isDefault: Bool = true) -> WindEntry {
        WindEntry(
            date: date,
            forecast: forecast,
            hourIndex: Derivations.heroIndex(forecast: forecast, now: date),
            trust: TrustState.compute(forecast: forecast, now: date, lastCheckOK: lastCheckOK),
            isDefault: isDefault)
    }

    static func make(_ entry: WindTimelineEntry, forecast: Forecast, isDefault: Bool, stripYMax: Int? = nil) -> WindEntry {
        WindEntry(date: entry.date, forecast: forecast, hourIndex: entry.hourIndex, trust: entry.trust, isDefault: isDefault,
                  stripYMax: stripYMax)
    }

    static func firstRun(at date: Date) -> WindEntry {
        WindEntry(date: date, forecast: nil, hourIndex: nil, trust: .firstRun, isDefault: true)
    }

    /// Reference-payload entries for previews and the DEBUG page: `fresh`, `stale`, `old`,
    /// `offline`, `horizon`, `firstrun`.
    static func fixture(_ state: String) -> WindEntry {
        let f = PreviewData.forecast
        switch state {
        case "stale": return make(forecast: f, at: f.fetched.addingTimeInterval(2 * 3600))
        case "old": return make(forecast: f, at: f.fetched.addingTimeInterval(7 * 3600))
        case "offline": return make(forecast: f, at: PreviewData.now, lastCheckOK: false)
        case "horizon": return make(forecast: f, at: f.horizon.addingTimeInterval(2 * 3600))
        case "firstrun": return firstRun(at: PreviewData.now)
        default: return make(forecast: f, at: PreviewData.now)
        }
    }
}

/// Shared colour decisions for every family.
enum ComplicationInk {
    /// Numbers: primary, `ink.old` when old; in tinted rendering always `.primary`.
    static func number(_ entry: WindEntry, tinted: Bool) -> Color {
        if tinted { return .primary }
        return Tokens.numberInk(.dark, tier: entry.tier)
    }

    static func secondary(_ tinted: Bool) -> Color {
        tinted ? Color.primary.opacity(0.7) : Tokens.inkSecondary(.dark)
    }

    static func trust(_ entry: WindEntry, tinted: Bool) -> Color {
        if entry.isAmber { return tinted ? .primary : Tokens.trustAmber(.dark) }
        return secondary(tinted)
    }

    /// Beaufort ramp colour for the hour, or `.primary` when tinted.
    static func beaufort(_ hour: Forecast.Hour?, tinted: Bool) -> Color {
        guard let hour, !tinted else { return .primary }
        return Beaufort.color(step: Beaufort.step(kn: hour.kn), scheme: .dark)
    }

    /// The eight ramp colours B0–7 for the corner gauge.
    static let rampB0to7: [Color] = (0...7).map { Beaufort.color(step: max($0, 1), scheme: .dark) }
}
