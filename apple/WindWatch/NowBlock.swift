import SwiftUI
import WindCore

/// Readout row (HANDOFF §6.4d round five, `Phone-Main.dc.html` / `Phone-Main-Scrub.dc.html`): a
/// fixed 96 pt `card` plate (radius 12, padding 10/12) with the same three columns in both states
/// so nothing above the chart moves while a finger is down.
/// - Left (124 pt): the 13 pt label line (`Now · Wed 9:25am` with a blue 2 pt bar, or
///   `Thu 12am · midnight` with a white one) over the 56 pt number + `kn`.
/// - Middle: `G 4` over arrow + `from W`; while scrubbing `283°` follows, Medium 13 secondary.
/// - Right: `peak G25 · 12am` at rest or `now 3 kn` while scrubbing (Medium 12 secondary) over
///   the Beaufort chip, number only.
/// Scrubbing adds a 1.5 pt white inset ring. Every text is single-line (`lineLimit(1)`,
/// `minimumScaleFactor(0.85)`).
struct NowBlock: View {
    var scrub: Int?

    @Environment(ForecastSession.self) private var model
    @Environment(\.colorScheme) private var scheme

    private var numberInk: Color { Tokens.numberInk(scheme, tier: model.ageTier) }

    /// The scrubbed hour when `scrub` is a valid index, else nil.
    private var scrubbed: (index: Int, hour: Forecast.Hour)? {
        guard let forecast = model.forecast, let index = scrub, forecast.hours.indices.contains(index) else { return nil }
        return (index, forecast.hours[index])
    }

    var body: some View {
        let shown = scrubbed?.hour ?? model.hero
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                labelLine
                heroNumber(shown?.kn)
            }
            .frame(width: 124, alignment: .leading)
            if let shown {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("G")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Tokens.inkSecondary(scheme))
                        Text("\(shown.gust)")
                            .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(numberInk)
                    }
                    .frame(height: 26)
                    HStack(spacing: 6) {
                        ArrowView(dirFrom: shown.dirFrom, size: 16, color: numberInk)
                        Text(Compass.fromText(dirFrom: shown.dirFrom))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(numberInk)
                        if scrubbed != nil {
                            Text("\(shown.dirFrom)°")
                                .font(.system(size: 13, weight: .medium).monospacedDigit())
                                .foregroundStyle(Tokens.inkSecondary(scheme))
                        }
                    }
                    .frame(height: 20)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.top, 18)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(rightText)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Tokens.inkSecondary(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(height: 16)
                    BeaufortChip(step: Beaufort.step(kn: shown.kn), scheme: scheme)
                        .oldStateDesaturation(model.ageTier)
                }
                .padding(.top, 18)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 96)
        .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if scrubbed != nil {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .inset(by: 0.75)
                    .stroke(Tokens.inkPrimary(scheme), lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Pieces

    /// `Now · Wed 9:25am` (blue bar) or `Thu 12am · midnight` (white bar); 13 Bold on a 16 pt line.
    private var labelLine: some View {
        let scrubbing = scrubbed != nil
        let text: String = {
            if let forecast = model.forecast, let s = scrubbed { return Derivations.scrubLabel(forecast: forecast, index: s.index) }
            return Derivations.nowLabel(now: model.now, tz: model.forecast?.timeZone ?? .current)
        }()
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(scrubbing ? Tokens.inkPrimary(scheme) : Tokens.nowBar(scheme))
                .frame(width: 2, height: 14)
            Text(text)
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(Tokens.inkPrimary(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(height: 16)
    }

    /// 56 pt Rounded Heavy on a 52 pt line, `kn` 18 Semibold 5 pt right on the baseline.
    private func heroNumber(_ kn: Int?) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 5) {
            if let kn {
                Text("\(kn)")
                    .font(.system(size: 56, weight: .heavy, design: .rounded).monospacedDigit())
                    .tracking(-0.03 * 56)
                    .foregroundStyle(numberInk)
                Text("kn")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Tokens.inkSecondary(scheme))
            } else {
                Text("—")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(Tokens.inkDisabled(scheme))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .frame(height: 52)
    }

    /// Right column line: `peak G25 · 12am` at rest, `now 3 kn` while scrubbing.
    private var rightText: String {
        if scrubbed != nil, let hero = model.hero { return "now \(hero.kn) kn" }
        if let forecast = model.forecast { return Derivations.peakReadoutText(forecast: forecast, now: model.now) }
        return ""
    }

    private var accessibilityText: String {
        guard let hero = model.hero, let forecast = model.forecast else {
            return model.trustState == .firstRun ? TrustLine.firstRunText : "No forecast"
        }
        if let s = scrubbed {
            let date = forecast.date(ofHour: s.index)
            return "\(TimeFormat.weekdayLong(date, tz: forecast.timeZone)) \(TimeFormat.hhmm(date, tz: forecast.timeZone)), \(s.hour.kn) knots gusting \(s.hour.gust) \(Compass.spokenFromText(dirFrom: s.hour.dirFrom)), \(s.hour.dirFrom) degrees, Beaufort \(Beaufort.step(kn: s.hour.kn)), now \(hero.kn) knots"
        }
        return Derivations.heroAccessibilityLabel(hour: hero, forecast: forecast) + ", " + Derivations.peakGustChipText(forecast: forecast, now: model.now)
    }
}
