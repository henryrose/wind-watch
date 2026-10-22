import SwiftUI
import WindCore

/// Readout row (`Phone-Main.dc.html`, HANDOFF §6.4): hero 60 + `kn`, `G 4` over arrow + `from W`,
/// peak-gust chip over the Beaufort pill. While scrubbing (`scrub != nil`) the row shows that hour
/// on a `card` plate with a 1.5 pt white inset stroke: `Thu 12am · midnight`, `15 kn`, `G 25`,
/// `from W · 283°`, the Beaufort chip, and `now 3 kn` as the anchor. Past horizon / first run: `—`.
struct NowBlock: View {
    var scrub: Int?

    @Environment(ForecastSession.self) private var model
    @Environment(\.colorScheme) private var scheme

    private var numberInk: Color { Tokens.numberInk(scheme, tier: model.ageTier) }
    private var rounded: Font.Design { .rounded }

    var body: some View {
        Group {
            if let forecast = model.forecast, let index = scrub, forecast.hours.indices.contains(index), let hero = model.hero {
                scrubRow(forecast: forecast, index: index, hero: hero)
            } else {
                nowRow
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Now

    private var nowRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            heroNumber(model.hero?.kn)
            if let hero = model.hero {
                gustColumn(gust: hero.gust, dirFrom: hero.dirFrom, degrees: false)
                    .padding(.bottom, 3)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    if let forecast = model.forecast { peakChip(forecast) }
                    BeaufortPill(step: Beaufort.step(kn: hero.kn), width: 48, height: 6, scheme: scheme)
                        .oldStateDesaturation(model.ageTier)
                }
                .layoutPriority(1)
                .padding(.bottom, 3)
            } else {
                Spacer()
            }
        }
    }

    // MARK: Scrub

    private func scrubRow(forecast: Forecast, index: Int, hero: Forecast.Hour) -> some View {
        let h = forecast.hours[index]
        return HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Tokens.inkPrimary(scheme))
                        .frame(width: 2, height: 14)
                    Text(Derivations.scrubLabel(forecast: forecast, index: index))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Tokens.inkPrimary(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                heroNumber(h.kn)
            }
            .layoutPriority(1)
            gustColumn(gust: h.gust, dirFrom: h.dirFrom, degrees: true)
                .padding(.bottom, 3)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Text("now \(hero.kn) kn")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Tokens.inkSecondary(scheme))
                HStack(spacing: 6) {
                    BeaufortChip(step: Beaufort.step(kn: h.kn), scheme: scheme)
                    Text("Beaufort")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tokens.inkSecondary(scheme))
                }
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.bottom, 3)
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .padding(.horizontal, 12)
        .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).inset(by: 0.75).stroke(Tokens.inkPrimary(scheme), lineWidth: 1.5))
    }

    // MARK: Pieces

    private func heroNumber(_ kn: Int?) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 5) {
            if let kn {
                Text("\(kn)")
                    .font(.system(size: 60, weight: .heavy, design: rounded).monospacedDigit())
                    .tracking(-1.8)
                    .foregroundStyle(numberInk)
                Text("kn")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Tokens.inkSecondary(scheme))
            } else {
                Text("—")
                    .font(.system(size: 60, weight: .heavy, design: rounded))
                    .foregroundStyle(Tokens.inkDisabled(scheme))
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func gustColumn(gust: Int, dirFrom: Int, degrees: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("G")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Tokens.inkSecondary(scheme))
                Text("\(gust)")
                    .font(.system(size: 24, weight: .bold, design: rounded).monospacedDigit())
                    .foregroundStyle(numberInk)
            }
            HStack(spacing: 6) {
                ArrowView(dirFrom: dirFrom, size: degrees ? 16 : 18, color: numberInk)
                Text(degrees ? "\(Compass.fromText(dirFrom: dirFrom)) · \(dirFrom)°" : Compass.fromText(dirFrom: dirFrom))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(numberInk)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func peakChip(_ forecast: Forecast) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Beaufort.color(step: Beaufort.step(kn: forecast.peakGust.kn), scheme: scheme))
                .frame(width: 9, height: 9)
            Text(Derivations.peakGustChipText(forecast: forecast, now: model.now))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Tokens.inkPrimary(scheme))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Tokens.card(scheme), in: Capsule())
        .oldStateDesaturation(model.ageTier)
    }

    private var accessibilityText: String {
        guard let hero = model.hero, let forecast = model.forecast else {
            return model.trustState == .firstRun ? TrustLine.firstRunText : "No forecast"
        }
        if let index = scrub, forecast.hours.indices.contains(index) {
            let h = forecast.hours[index]
            let date = forecast.date(ofHour: index)
            return "\(TimeFormat.weekdayLong(date, tz: forecast.timeZone)) \(TimeFormat.hhmm(date, tz: forecast.timeZone)), \(h.kn) knots gusting \(h.gust) \(Compass.spokenFromText(dirFrom: h.dirFrom)), Beaufort \(Beaufort.step(kn: h.kn))"
        }
        return Derivations.heroAccessibilityLabel(hour: hero, forecast: forecast)
    }
}
