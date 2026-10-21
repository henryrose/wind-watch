import SwiftUI
import WindCore

/// HANDOFF §7.2: location, hero row, direction row, summary, trust line. First paint from cache,
/// no spinner except on first run. The hero sits on solid black.
struct NowView: View {
    @Environment(ForecastSession.self) private var session

    private var ink: Color { Tokens.numberInk(.dark, tier: session.ageTier) }
    private var state: TrustState { session.trustState }

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
            Text(session.locationName)
                .font(Tokens.locationFont(watch: true))
                .foregroundStyle(Tokens.inkSecondary(.dark))
                .lineLimit(1)
            heroRow
                .padding(.top, 2)
            if let hero = session.hero {
                directionRow(hero)
                    .padding(.top, 5)
            }
            if state == .firstRun {
                Text(TrustLine.firstRunText)
                    .font(Tokens.summaryFont(watch: true))
                    .foregroundStyle(Tokens.inkBody(.dark))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)
            } else if state != .offlineCached, state.showsNumbers, let forecast = session.forecast {
                Text(forecast.summary)
                    .font(Tokens.summaryFont(watch: true))
                    .foregroundStyle(Tokens.inkBody(.dark))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)
            }
            Spacer(minLength: 2)
            footer
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .accessibilityElement(children: .contain)
    }

    private var heroRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 5) {
            if let hero = session.hero {
                Text("\(hero.kn)")
                    .font(Tokens.heroFont(watch: true))
                    .tracking(Tokens.heroTracking(watch: true))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("kn")
                    .font(Tokens.heroUnitFont(watch: true))
                    .foregroundStyle(Tokens.inkSecondary(.dark))
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text("G")
                            .font(Tokens.gustPrefixFont(watch: true))
                            .foregroundStyle(Tokens.inkSecondary(.dark))
                        Text("\(hero.gust)")
                            .font(Tokens.gustFont(watch: true))
                            .foregroundStyle(ink)
                    }
                    BeaufortPill.watch(step: Beaufort.step(kn: hero.kn))
                        .oldStateDesaturation(session.ageTier)
                }
            } else {
                Text("—")
                    .font(Tokens.heroFont(watch: true))
                    .foregroundStyle(Tokens.inkDisabled(.dark))
                Spacer()
            }
        }
        .frame(height: 70)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroAccessibility)
    }

    private func directionRow(_ hero: Forecast.Hour) -> some View {
        HStack(spacing: 5) {
            ArrowView(dirFrom: hero.dirFrom, size: 18, color: ink)
            Text(Compass.fromText(dirFrom: hero.dirFrom))
                .font(Tokens.directionFont(watch: true))
                .foregroundStyle(ink)
        }
        .accessibilityHidden(true)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if state == .firstRun {
                ProgressView().controlSize(.mini)
                Text(TrustLine.firstRunFooterText)
                    .font(Tokens.trustFont(watch: true, amber: false))
                    .foregroundStyle(Tokens.inkSecondary(.dark))
            } else {
                TrustLineView(state: state, forecast: session.forecast, now: session.now, compact: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var heroAccessibility: String {
        guard let hero = session.hero, let forecast = session.forecast else {
            return state == .firstRun ? TrustLine.firstRunText : "No forecast"
        }
        return Derivations.heroAccessibilityLabel(hour: hero, forecast: forecast)
    }
}
