import SwiftUI
import WindCore

/// Readout row (HANDOFF §6.4d, 26 Oct item 3, `Phone-Main.dc.html` / `Phone-Main-Scrub.dc.html` /
/// `Phone-Main-7d*.dc.html` / `Phone-Main-Sky-Scrub.dc.html`): a fixed 96 pt `card` plate (radius
/// 12, padding 10/12) with the same structure in both states so nothing above the chart moves
/// while a finger is down. A 13 pt label line (`Now · Wed 9:25am` with a blue 2 pt bar, or the
/// scrubbed slot with a white one — `Thu 12am · midnight · Overcast · rain · 48°F`, or
/// `Sat 12–3pm · NBM` for an NBM block); under it the 56 pt hero + `kn` in a 124 pt column, then
/// `G 4` over arrow + `from W` (+ `283°` Medium 13 secondary while scrubbing), and a right column
/// with `peak G25 · 12am` (`now 3 kn` while scrubbing) over the Beaufort chip. Scrubbing adds a
/// 1.5 pt white inset ring. Every text is single-line (`lineLimit(1)`, `minimumScaleFactor`).
struct NowBlock: View {
    /// The scrubbed slot (an hour, an HRRR 3-hour block or an NBM block), nil at rest.
    var scrubbed: HourPoint?
    /// The chart being shown (the 7-day peak reads across it).
    var chart: ChartModel?

    @Environment(ForecastSession.self) private var model
    @Environment(\.colorScheme) private var scheme
    @AppStorage(TemperatureUnit.storageKey, store: .windShared) private var unit: TemperatureUnit = .fahrenheit

    private var numberInk: Color { Tokens.numberInk(scheme, tier: model.ageTier) }
    private var tz: TimeZone { model.forecast?.timeZone ?? .current }

    var body: some View {
        let shown = scrubbed?.hour ?? model.hero
        VStack(alignment: .leading, spacing: 4) {
            labelLine
            HStack(alignment: .bottom, spacing: 12) {
                heroNumber(shown?.kn)
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
                            // Degrees only while scrubbing (and in the table).
                            if scrubbed != nil {
                                Text("\(shown.dirFrom)°")
                                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                                    .foregroundStyle(Tokens.inkSecondary(scheme))
                            }
                        }
                        .frame(height: 20)
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.bottom, 2)
                    Spacer(minLength: 4)
                } else {
                    Spacer(minLength: 0)
                }
            }
            // Right column: the peak text over the chip. An overlay, so a long 7-day peak
            // (`peak G32 · Sat 1pm · NBM`) may run left over the short `G 4` line instead of
            // truncating; the artboard's column is too narrow for it at 12 pt.
            .overlay(alignment: .bottomTrailing) {
                if let shown {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(rightText)
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(Tokens.inkSecondary(scheme))
                            .lineLimit(1)
                            .fixedSize()
                            .frame(height: 16)
                        BeaufortChip(step: Beaufort.step(kn: shown.kn), scheme: scheme)
                            .oldStateDesaturation(model.ageTier)
                            .frame(height: 20)
                    }
                    .padding(.bottom, 4)
                }
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

    /// `Now · Wed 9:25am` (blue bar) or the scrubbed slot (white bar; the NBM blue for an NBM
    /// block) with `· NBM` and the sky detail in Medium secondary; 13 Bold on a 16 pt line.
    private var labelLine: some View {
        let bar: Color = {
            guard let p = scrubbed else { return Tokens.nowBar(scheme) }
            return p.isNBM ? Tokens.nbmLabel(scheme) : Tokens.inkPrimary(scheme)
        }()
        return HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(bar)
                .frame(width: 2, height: 14)
            labelText
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(Tokens.inkPrimary(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(height: 16)
    }

    private var labelText: Text {
        guard let p = scrubbed else { return Text(Derivations.nowLabel(now: model.now, tz: tz)) }
        var t = Text(Derivations.slotLabel(p, tz: tz))
        if p.isNBM { t = t + Text(" · NBM").foregroundStyle(Tokens.nbmLabel(scheme)) }
        if let detail = Derivations.skyDetail(p.hour, unit: unit) {
            t = t + Text(" · " + detail).fontWeight(.medium).foregroundStyle(Tokens.inkSecondary(scheme))
        }
        return t
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
        .fixedSize()
        .frame(height: 52)
    }

    /// Right column top line: the peak text at rest, `now 3 kn` while scrubbing.
    private var rightText: String {
        if scrubbed != nil, let hero = model.hero { return "now \(hero.kn) kn" }
        if let forecast = model.forecast { return Derivations.peakText(forecast: forecast, chart: chart, now: model.now) }
        return ""
    }

    private var accessibilityText: String {
        guard let hero = model.hero, let forecast = model.forecast else {
            return model.trustState == .firstRun ? TrustLine.firstRunText : "No forecast"
        }
        if let p = scrubbed {
            var text = "\(Derivations.spokenSlot(p, tz: tz)), \(p.kn) knots gusting \(p.gust) \(Compass.spokenFromText(dirFrom: p.dirFrom)), \(p.dirFrom) degrees, Beaufort \(p.step)"
            if let detail = Derivations.skyDetailSpoken(p.hour, unit: unit) { text += ", " + detail }
            return text + ", now \(hero.kn) knots"
        }
        return Derivations.heroAccessibilityLabel(hour: hero, forecast: forecast) + ", " + Derivations.peakSpoken(forecast: forecast, chart: chart, now: model.now)
    }
}
