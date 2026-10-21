import SwiftUI
import WindCore

/// Location name, trust line (with `· ends Fri 05:00`), gear button → Location settings.
struct HeaderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.locationName)
                    .font(Tokens.locationFont(watch: false))
                    .foregroundStyle(Tokens.inkPrimary(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                TrustLineView(
                    state: model.trustState,
                    forecast: model.forecast,
                    now: model.now,
                    suffix: model.forecast.map { Derivations.horizonWeekdayLabel(forecast: $0) }
                )
            }
            Spacer(minLength: 0)
            NavigationLink(value: AppModel.Screen.location) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Tokens.inkSecondary(scheme))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Location settings")
        }
        .padding(.top, 6)
    }
}
