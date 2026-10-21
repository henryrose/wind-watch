import SwiftUI
import WindCore

/// HANDOFF §8.1 item 2: hero 72 + `kn`, `G 25` over arrow + `from W`, peak-gust chip over the
/// Beaufort pill. Past horizon / first run: `—`, nothing else.
struct NowBlock: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    private var numberInk: Color { Tokens.numberInk(scheme, tier: model.ageTier) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            heroNumber
            if let hero = model.hero {
                gustColumn(hero)
                Spacer(minLength: 8)
                peakColumn(hero)
            } else {
                Spacer()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var heroNumber: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let hero = model.hero {
                Text("\(hero.kn)")
                    .font(Tokens.heroFont(watch: false))
                    .foregroundStyle(numberInk)
                Text("kn")
                    .font(Tokens.heroUnitFont(watch: false))
                    .foregroundStyle(Tokens.inkSecondary(scheme))
            } else {
                Text("—")
                    .font(Tokens.heroFont(watch: false))
                    .foregroundStyle(Tokens.inkDisabled(scheme))
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func gustColumn(_ hero: Forecast.Hour) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("G")
                    .font(Tokens.gustPrefixFont(watch: false))
                    .foregroundStyle(Tokens.inkSecondary(scheme))
                Text("\(hero.gust)")
                    .font(Tokens.gustFont(watch: false))
                    .foregroundStyle(numberInk)
            }
            HStack(spacing: 6) {
                ArrowView(dirFrom: hero.dirFrom, size: 18, color: numberInk)
                Text(Compass.fromText(dirFrom: hero.dirFrom))
                    .font(Tokens.directionFont(watch: false))
                    .foregroundStyle(numberInk)
            }
        }
        .padding(.top, 14)
        .fixedSize()
    }

    private func peakColumn(_ hero: Forecast.Hour) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let forecast = model.forecast {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Beaufort.color(step: Beaufort.step(kn: forecast.peakGust.kn), scheme: scheme))
                        .frame(width: 10, height: 10)
                    Text(Derivations.peakGustChipText(forecast: forecast, now: model.now))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Tokens.inkPrimary(scheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Tokens.card(scheme), in: Capsule())
                .oldStateDesaturation(model.ageTier)
            }
            BeaufortPill(step: Beaufort.step(kn: hero.kn), width: 48, height: 6, scheme: scheme)
                .oldStateDesaturation(model.ageTier)
                .padding(.trailing, 4)
        }
        .padding(.top, 14)
        .frame(maxWidth: 180, alignment: .trailing)
    }

    private var accessibilityText: String {
        guard let hero = model.hero, let forecast = model.forecast else {
            return model.trustState == .firstRun ? TrustLine.firstRunText : "No forecast"
        }
        return Derivations.heroAccessibilityLabel(hour: hero, forecast: forecast)
    }
}
