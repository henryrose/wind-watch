import SwiftUI
import WindCore

/// iPhone landscape (HANDOFF §6.4b, §6.4d, `Phone-Landscape.dc.html`): one fixed 48 pt header line
/// (location + trust line left, the readout right; the same structure at rest and while
/// scrubbing, the plate gaining a ring), then the chart fills the rest at screen width − 40 so
/// the first and last hour clear the Dynamic Island. Table, summary and peak chip hidden.
/// 7 d (`Phone-Landscape-7d.dc.html`, §12a): location 15 over the full trust line 11 left, the
/// readout centre (no degrees; `now 3`), the range control right; HRRR stays hourly to the seam
/// and the plot keeps 48 pt side margins so the Dynamic Island never covers `now`.
struct LandscapeView: View {
    @Binding var scrub: ScrubState
    @Binding var range: ChartRange

    @Environment(ForecastSession.self) private var model
    @Environment(\.colorScheme) private var scheme

    private var numberInk: Color { Tokens.numberInk(scheme, tier: model.ageTier) }

    var body: some View {
        GeometryReader { geo in
            // Plot width = screen − 40 (§6.4d): 20 pt in from each screen edge, whatever the side
            // safe-area inset is (59 on a Dynamic Island phone); 48 pt in 7 d (§12a).
            let margin: CGFloat = range == .days7 ? 48 : 20
            let plotWidth = geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing - 2 * margin
            let chart = model.forecast.flatMap { f in
                model.trustState.showsNumbers
                    ? ChartModel(forecast: f, now: model.now, window: range.window, scheme: scheme, plotWidth: plotWidth) : nil
            }
            VStack(alignment: .leading, spacing: 8) {
                header(chart)
                    .frame(height: 48)
                if let chart {
                    self.chart(chart)
                        .padding(.horizontal, -(geo.safeAreaInsets.leading - margin))
                } else {
                    Spacer()
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
    }

    /// One 48 pt line in both ranges (`Phone-Landscape-7d.dc.html`): location 15 over the trust line
    /// 11 left (giving way first), the readout centre, the range control right. The 48 h board has
    /// no control; with it the 48 h line takes the 7 d layout so everything fits.
    private func header(_ chart: ChartModel?) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.locationName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Tokens.inkPrimary(scheme))
                TrustLineView(state: model.trustState, forecast: model.forecast, now: model.now, showsNBM: range == .days7)
                    .font(.system(size: 11, weight: .medium))
            }
            .lineLimit(1)
            .truncationMode(.tail)
            // The identity gives way first when the readout is wide (scrubbing an NBM block).
            .layoutPriority(-1)
            Spacer(minLength: 4)
            if let forecast = model.forecast, let hero = model.hero {
                readout(forecast: forecast, hero: hero, chart: chart)
            }
            Spacer(minLength: 4)
            SegmentedPicker(range: $range, track: Tokens.card(scheme))
        }
    }

    /// `Now · Wed 9:25am` and the now numbers, or the touched hour on a ringed plate with
    /// `now 3 kn` as the anchor (`Phone-Landscape.dc.html`).
    private func readout(forecast: Forecast, hero: Forecast.Hour, chart: ChartModel?) -> some View {
        let point = chart?.selected(scrub.index)
        let index = point?.index
        let h = point?.hour ?? hero
        // Compact since the range control joined the line (`Phone-Landscape-7d`): no degrees, `now 3`.
        return HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(point == nil ? Tokens.nowBar(scheme) : (point?.isNBM == true ? Tokens.nbmLabel(scheme) : Tokens.inkPrimary(scheme)))
                    .frame(width: 2, height: 14)
                (point.map { p in
                    Text(Derivations.slotLabel(p, tz: forecast.timeZone))
                        + (p.isNBM ? Text(" · NBM").foregroundStyle(Tokens.nbmLabel(scheme)) : Text(""))
                } ?? Text(Derivations.nowLabel(now: model.now, tz: forecast.timeZone)))
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(Tokens.inkPrimary(scheme))
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(h.kn)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                    .tracking(-0.6)
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
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(numberInk)
            }
            BeaufortChip(step: Beaufort.step(kn: h.kn), scheme: scheme)
                .oldStateDesaturation(model.ageTier)
            if index != nil {
                Text("now \(hero.kn)")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Tokens.inkSecondary(scheme))
                    .padding(.leading, 4)
                    .overlay(alignment: .leading) { Rectangle().fill(Tokens.hairline(scheme)).frame(width: 1) }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
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
    private func chart(_ chart: ChartModel) -> some View {
        let week = range == .days7
        let selection = chart.selected(scrub.index)?.index
        return GeometryReader { geo in
            var style = week ? ChartStyle.phoneLandscapeWeek : ChartStyle.phoneLandscape
            // 7 d has no hint line (§12a), so the plot takes its room.
            let fixed = style.topInset + style.bottomInset + style.labelBand + 8 + (week ? 8 : 6 + 18)
            let _ = style.plotHeight = max(120, min(236, geo.size.height - fixed))
            VStack(spacing: 0) {
                WindChart(model: chart, style: style, selection: selection, onScrub: { scrub.apply($0) })
                    .padding(.top, 8)
                if !week {
                    Text(scrub.index == nil ? "touch a bar for that hour · rotate back for the table" : "release to return to now · rotate back for the table")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Tokens.inkSecondary(scheme))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .frame(height: 18)
                        .padding(.trailing, 24)
                        .padding(.bottom, 6)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
