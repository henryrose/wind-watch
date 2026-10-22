import SwiftUI
import WindCore

/// Location name (Bold 22, HANDOFF §6.4), trust line 13 with `· ends Fri 5am`, and a 44 pt
/// `card` circle with the gear → Location settings (`Phone-Main.dc.html`).
struct HeaderView: View {
    @Environment(ForecastSession.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.locationName)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.22)
                    .foregroundStyle(Tokens.inkPrimary(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                TrustLineView(
                    state: model.trustState,
                    forecast: model.forecast,
                    now: model.now,
                    // AX sizes drop the horizon suffix (`Phone-Table-LargeType`).
                    suffix: typeSize.isAccessibilitySize ? nil : model.forecast.map { Derivations.horizonWeekdayLabel(forecast: $0) }
                )
            }
            Spacer(minLength: 0)
            NavigationLink(value: Screen.location) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Tokens.inkPrimary(scheme))
                    .frame(width: 44, height: 44)
                    .background(Tokens.card(scheme), in: Circle())
                    .contentShape(Circle())
            }
            .padding(.top, -6)
            .accessibilityLabel("Location settings")
        }
        .padding(.top, 6)
    }
}
