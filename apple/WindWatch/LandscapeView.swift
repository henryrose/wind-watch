import SwiftUI
import WindCore

/// iPhone landscape (HANDOFF §6.4b, §6.4d, `Phone-Landscape.dc.html`): one fixed 48 pt header line
/// (location + trust line left, the readout right; the same structure at rest and while
/// scrubbing, the plate gaining a ring), then the chart fills the rest at screen width − 40 so
/// the first and last hour clear the Dynamic Island. Table, summary and peak chip hidden.
struct LandscapeView: View {
    @Binding var scrub: ScrubState

    @Environment(ForecastSession.self) private var model
    @Environment(\.colorScheme) private var scheme

    private var numberInk: Color { Tokens.numberInk(scheme, tier: model.ageTier) }

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 8) {
                header
                    .frame(height: 48)
                if let forecast = model.forecast, model.trustState.showsNumbers {
                    chart(forecast)
                        // Plot width = screen − 40 (§6.4d): 20 pt in from each screen edge,
                        // whatever the side safe-area inset is (59 on a Dynamic Island phone).
                        .padding(.horizontal, -(geo.safeAreaInsets.leading - 20))
                } else {
                    Spacer()
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(model.locationName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Tokens.inkPrimary(scheme))
                    .lineLimit(1)
                    .fixedSize()
                TrustLineView(state: model.trustState, forecast: model.forecast, now: model.now,
                              suffix: model.forecast.map { Derivations.horizonWeekdayLabel(forecast: $0) })
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if let forecast = model.forecast, let hero = model.hero {
                readout(forecast: forecast, hero: hero)
            }
        }
    }

    /// `Now · Wed 9:25am` and the now numbers, or the touched hour on a ringed plate with
    /// `now 3 kn` as the anchor (`Phone-Landscape.dc.html`).
    private func readout(forecast: Forecast, hero: Forecast.Hour) -> some View {
        let index = scrub.index.flatMap { forecast.hours.indices.contains($0) ? $0 : nil }
        let h = index.map { forecast.hours[$0] } ?? hero
        return HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(index == nil ? Tokens.nowBar(scheme) : Tokens.inkPrimary(scheme))
                    .frame(width: 2, height: 14)
                Text(index.map { Derivations.scrubLabel(forecast: forecast, index: $0) }
                     ?? Derivations.nowLabel(now: model.now, tz: forecast.timeZone))
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(Tokens.inkPrimary(scheme))
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(h.kn)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                    .tracking(-0.68)
                    .foregroundStyle(numberInk)
                Text("kn")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tokens.inkSecondary(scheme))
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("G").font(.system(size: 14, weight: .semibold)).foregroundStyle(Tokens.inkSecondary(scheme))
                Text("\(h.gust)").font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(numberInk)
            }
            HStack(spacing: 6) {
                ArrowView(dirFrom: h.dirFrom, size: 16, color: numberInk)
                Text(Compass.fromText(dirFrom: h.dirFrom))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(numberInk)
                // Round five: degrees only while scrubbing, small and secondary.
                if index != nil {
                    Text("\(h.dirFrom)°")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(Tokens.inkSecondary(scheme))
                }
            }
            BeaufortChip(step: Beaufort.step(kn: h.kn), scheme: scheme)
                .oldStateDesaturation(model.ageTier)
            if index != nil {
                Text("now \(hero.kn) kn")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Tokens.inkSecondary(scheme))
                    .padding(.leading, 4)
                    .overlay(alignment: .leading) { Rectangle().fill(Tokens.hairline(scheme)).frame(width: 1) }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Tokens.card(scheme).opacity(index == nil ? 0 : 1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if index != nil {
                RoundedRectangle(cornerRadius: 12, style: .continuous).inset(by: 0.75).stroke(Tokens.inkPrimary(scheme), lineWidth: 1.5)
            }
        }
    }

    /// The plot takes whatever height is left under the header (236 pt on a 402-pt-tall phone with
    /// no status bar); the hint sits under the tick labels. The card is the plot's width.
    private func chart(_ forecast: Forecast) -> some View {
        let chart = ChartModel(forecast: forecast, now: model.now, window: .all, scheme: scheme)
        return GeometryReader { geo in
            var style = ChartStyle.phoneLandscape
            let fixed = style.topInset + style.bottomInset + style.labelBand + 8 + 6 + 18
            let _ = style.plotHeight = max(120, min(236, geo.size.height - fixed))
            VStack(spacing: 0) {
                WindChart(model: chart, style: style, selection: scrub.index, onScrub: { scrub.apply($0) })
                    .padding(.top, 8)
                Text(scrub.index == nil ? "touch a bar for that hour · rotate back for the table" : "release to return to now · rotate back for the table")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Tokens.inkSecondary(scheme))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(height: 18)
                    .padding(.trailing, 24)
                    .padding(.bottom, 6)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
