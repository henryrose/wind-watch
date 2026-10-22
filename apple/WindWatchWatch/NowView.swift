import SwiftUI
import WatchKit
import WindCore

/// HANDOFF §7.2 / `Watch-Now.dc.html`: location, hero row, direction row, summary, trust line.
/// First paint from cache, no spinner except on first run. The hero sits on solid black.
///
/// Row rhythm on 46 mm (artboard px ÷ 2): location Semibold 11 → 2 → hero row (84 Rounded Heavy
/// on a 75 pt line, `kn` 18 baseline-aligned 5 right; right column `G` 16 + gust 27, pill 36×5
/// 3 under) → 5 → direction row (arrow 18 + `from W` 18, gap 6) → 9 → summary 13 → spacer →
/// trust 12. Insets 12 sides, 14 bottom; the top inset is the system's (under the clock).
/// 42 mm uses the artboard's fourth panel (hero 75 on 67, kn 16, G 14 / gust 24, direction 16,
/// summary 12, insets 11 / 13). The summary takes as many lines as fit (3 → 2 → 1), never clipped.
struct NowView: View {
    @Environment(ForecastSession.self) private var session

    private var ink: Color { Tokens.numberInk(.dark, tier: session.ageTier) }
    private var state: TrustState { session.trustState }
    private let m = NowMetrics.current

    var body: some View {
        GeometryReader { geo in
            ViewThatFits(in: .vertical) {
                content(summaryLines: m.maxSummaryLines)
                content(summaryLines: max(m.maxSummaryLines - 1, 1))
                content(summaryLines: 1)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea(edges: .bottom)
        .background(Tokens.groundWatch(.dark))
    }

    private func content(summaryLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(session.locationName)
                .font(m.locationFont)
                .foregroundStyle(Tokens.inkSecondary(.dark))
                .lineLimit(1)
            heroRow
                .padding(.top, 2)
            if let hero = session.hero {
                // Artboard: 5 pt (4 on 42 mm) under the hero row's box, whose bottom is the pill
                // hanging ~6 pt below the hero line.
                directionRow(hero)
                    .padding(.top, m.directionTop)
            }
            if state == .firstRun {
                Text(TrustLine.firstRunTitle)
                    .font(m.firstRunTitleFont)
                    .foregroundStyle(Tokens.inkPrimary(.dark))
                    .padding(.top, m.firstRunTitleTop)
                Text(TrustLine.firstRunBody)
                    .font(m.summaryFont)
                    .foregroundStyle(Tokens.inkBody(.dark))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 3)
            } else if state != .offlineCached, state.showsNumbers, let forecast = session.forecast {
                Text(forecast.summary)
                    .font(m.summaryFont)
                    .foregroundStyle(Tokens.inkBody(.dark))
                    .lineLimit(summaryLines)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, m.summaryTop)
            }
            Spacer(minLength: 0)
            footer
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, m.sideInset)
        .padding(.bottom, m.bottomInset)
        .accessibilityElement(children: .contain)
    }

    /// The hero line is 75 pt tall (artboard `line-height: 150px`); the 84 pt glyphs overhang it
    /// by their ascender/descender, which is empty space. Only 3-digit values scale down.
    private var heroRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 5) {
            if let hero = session.hero {
                Text("\(hero.kn)")
                    .font(m.heroFont)
                    .tracking(m.heroTracking)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(hero.kn >= 100 ? 0.7 : 1)
                Text("kn")
                    .font(m.heroUnitFont)
                    .foregroundStyle(Tokens.inkSecondary(.dark))
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text("G")
                            .font(m.gustPrefixFont)
                            .foregroundStyle(Tokens.inkSecondary(.dark))
                        Text("\(hero.gust)")
                            .font(m.gustFont)
                            .foregroundStyle(ink)
                    }
                    BeaufortPill(step: Beaufort.step(kn: hero.kn), width: m.pillWidth, height: m.pillHeight, scheme: .dark)
                        .oldStateDesaturation(session.ageTier)
                }
            } else {
                Text("—")
                    .font(m.heroFont)
                    .tracking(m.heroTracking)
                    .foregroundStyle(Tokens.inkDisabled(.dark))
                    .lineLimit(1)
                Text("kn")
                    .font(m.heroUnitFont)
                    .foregroundStyle(Tokens.inkDisabled(.dark))
                Spacer(minLength: 0)
            }
        }
        .frame(height: m.heroLine)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heroAccessibility)
    }

    private func directionRow(_ hero: Forecast.Hour) -> some View {
        HStack(spacing: m.directionGap) {
            ArrowView(dirFrom: hero.dirFrom, size: m.arrowSize, color: ink)
            Text(Compass.fromText(dirFrom: hero.dirFrom))
                .font(m.directionFont)
                .foregroundStyle(ink)
        }
        .accessibilityHidden(true)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            if state == .firstRun {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
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

/// Per-case-size values for the Now screen. `large` is the 46 mm design (the `Tokens` watch
/// scale); `small` is the artboard's 42 mm panel (`Watch-Now-States.dc.html`, 374×446 px).
private struct NowMetrics {
    var locationFont: Font
    var heroFont: Font
    var heroTracking: CGFloat
    var heroLine: CGFloat
    var heroUnitFont: Font
    var gustPrefixFont: Font
    var gustFont: Font
    var pillWidth: CGFloat
    var pillHeight: CGFloat
    var directionTop: CGFloat
    var directionFont: Font
    var arrowSize: CGFloat
    var directionGap: CGFloat
    var summaryTop: CGFloat
    var summaryFont: Font
    var firstRunTitleFont: Font
    var firstRunTitleTop: CGFloat
    var maxSummaryLines: Int
    var sideInset: CGFloat
    var bottomInset: CGFloat

    static let large = NowMetrics(
        locationFont: Tokens.locationFont(watch: true),
        heroFont: Tokens.heroFont(watch: true),
        heroTracking: Tokens.heroTracking(watch: true),
        heroLine: 75,
        heroUnitFont: Tokens.heroUnitFont(watch: true),
        gustPrefixFont: Tokens.gustPrefixFont(watch: true),
        gustFont: Tokens.gustFont(watch: true),
        pillWidth: 36, pillHeight: 5,
        directionTop: 11,
        directionFont: Tokens.directionFont(watch: true),
        arrowSize: 18, directionGap: 6,
        summaryTop: 9,
        summaryFont: Tokens.summaryFont(watch: true),
        firstRunTitleFont: .system(size: 15, weight: .semibold),
        firstRunTitleTop: 12,
        maxSummaryLines: 3,
        sideInset: 12, bottomInset: 14
    )

    static let small = NowMetrics(
        locationFont: .system(size: 10, weight: .semibold),
        heroFont: .system(size: 75, weight: .heavy, design: .rounded).monospacedDigit(),
        heroTracking: -0.03 * 75,
        heroLine: 67,
        heroUnitFont: .system(size: 16, weight: .semibold),
        gustPrefixFont: .system(size: 14, weight: .semibold),
        gustFont: .system(size: 24, weight: .bold, design: .rounded).monospacedDigit(),
        pillWidth: 32, pillHeight: 4.5,
        directionTop: 10,
        directionFont: .system(size: 16, weight: .semibold),
        arrowSize: 16, directionGap: 5,
        summaryTop: 7,
        summaryFont: .system(size: 12, weight: .regular),
        firstRunTitleFont: .system(size: 14, weight: .semibold),
        firstRunTitleTop: 7,
        maxSummaryLines: 2,
        sideInset: 11, bottomInset: 13
    )

    /// 46 mm is 208 pt wide; 42 mm is 187.
    static var current: NowMetrics {
        WKInterfaceDevice.current().screenBounds.width >= 200 ? large : small
    }
}
