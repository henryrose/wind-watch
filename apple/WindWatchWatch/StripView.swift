import SwiftUI
import WatchKit
import WindCore

/// The launch screen (HANDOFF §6.4d, §7.3, `Watch-Strip.dc.html`): a compact hero line so the one
/// job lands on wrist raise — `3 kn · G 4 · ▸ from W` (Rounded Heavy 32 / Bold 17 / Semibold 13) —
/// a secondary line `Next 12 h · gusts to 15 · Port Townsend Bay` (Medium 10, truncating tail),
/// the 198×115 strip 6 pt below, and the trust line in the footer. Short horizon: `Next 6 h ·
/// gusts to 21 · ends 05:00`, the axis keeps 12 slots, `ends 05:00` at the edge. Artboard px ÷ 2:
/// side inset 7, hero line 28, chart gap 6, bottom inset 11. Page dots are the system's.
struct StripView: View {
    @Environment(ForecastSession.self) private var session

    private var ink: Color { Tokens.numberInk(.dark, tier: session.ageTier) }

    var body: some View {
        GeometryReader { geo in
            content
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea(edges: .bottom)
        .background(Tokens.groundWatch(.dark))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroLine
                .padding(.horizontal, 7)
            if let forecast = session.forecast, session.trustState.showsNumbers {
                let model = ChartModel(forecast: forecast, now: session.now, window: .next12, scheme: .dark)
                Text(secondaryLine(forecast: forecast, model: model))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Tokens.inkSecondary(.dark))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 2)
                    .padding(.horizontal, 7)
                WindChart(model: model, style: chartStyle)
                    .padding(.top, 6)
            } else {
                Text(session.trustState == .firstRun ? TrustLine.firstRunTitle : "No forecast")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Tokens.inkSecondary(.dark))
                    .padding(.top, 2)
                    .padding(.horizontal, 7)
            }
            Spacer(minLength: 0)
            HStack {
                TrustLineView(state: session.trustState, forecast: session.forecast, now: session.now, compact: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 5)
        .padding(.bottom, 11)
    }

    /// 46 mm draws the artboard's 92 pt plot. 42 mm (187×223 pt) has no room for it under the
    /// hero line and above the trust line, so the plot drops to 74 pt; slots and type stay.
    private var chartStyle: ChartStyle {
        var style = ChartStyle.watchStrip
        if WKInterfaceDevice.current().screenBounds.width < 200 { style.plotHeight = 74 }
        return style
    }

    /// `3 kn   G 4            ▸ from W` on a 28 pt line; `—` without a hero.
    private var heroLine: some View {
        HStack(alignment: .lastTextBaseline, spacing: 5) {
            if let hero = session.hero {
                Text("\(hero.kn)")
                    .font(.system(size: 32, weight: .heavy, design: .rounded).monospacedDigit())
                    .tracking(-0.03 * 32)
                    .foregroundStyle(ink)
                Text("kn")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tokens.inkSecondary(.dark))
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text("G")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Tokens.inkSecondary(.dark))
                    Text("\(hero.gust)")
                        .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(ink)
                }
                .padding(.leading, 3)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    ArrowView(dirFrom: hero.dirFrom, size: 13, color: ink)
                    Text(Compass.fromText(dirFrom: hero.dirFrom))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ink)
                }
            } else {
                Text("—")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(Tokens.inkDisabled(.dark))
                Text("kn")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tokens.inkDisabled(.dark))
                Spacer(minLength: 0)
            }
        }
        .lineLimit(1)
        .frame(height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroAccessibility)
    }

    /// `Next 12 h · gusts to 15 · Port Townsend Bay`; near the horizon `Next 6 h · gusts to 21 ·
    /// ends 05:00`. The location goes last so it is what truncates on a long name.
    private func secondaryLine(forecast: Forecast, model: ChartModel) -> String {
        let hours = hoursRemaining(forecast)
        let tail = hours < 12 ? Derivations.horizonLabel(forecast: forecast, short: true) : session.locationName
        return "Next \(hours) h · gusts to \(model.maxGust) · \(tail)"
    }

    /// Whole hours left before the horizon, capped at the 12-slot window.
    private func hoursRemaining(_ forecast: Forecast) -> Int {
        let left = Int((forecast.horizon.timeIntervalSince(session.now) / 3600).rounded(.down))
        return min(max(left, 0), 12)
    }

    private var heroAccessibility: String {
        guard let hero = session.hero, let forecast = session.forecast else {
            return session.trustState == .firstRun ? TrustLine.firstRunText : "No forecast"
        }
        return Derivations.heroAccessibilityLabel(hour: hero, forecast: forecast)
    }
}
