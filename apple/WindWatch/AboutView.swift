import SwiftUI
import WindCore

/// HANDOFF §8.4: model explanation, Beaufort legend, attribution.
struct AboutView: View {
    @Environment(\.colorScheme) private var scheme

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        return "Wind Watch \(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("About")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Tokens.inkPrimary(scheme))
                card {
                    Text("The model")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Tokens.inkPrimary(scheme))
                    Text("HRRR is NOAA's 3 km hourly forecast model, refreshed every hour and reaching 18 hours ahead, 48 at 00, 06, 12 and 18 UTC. Open-Meteo serves the grid point over Port Townsend Bay, picked so the wind is for water rather than shore. The app shows the latest run as it is and stops where the run ends; it never pads or blends.")
                        .font(.system(size: 15))
                        .foregroundStyle(Tokens.inkBody(scheme))
                }
                card {
                    Text("Beaufort colours")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Tokens.inkPrimary(scheme))
                    ForEach(legendSteps, id: \.self) { step in
                        HStack(spacing: 12) {
                            BeaufortChip(step: step, scheme: scheme)
                                .frame(width: 36, alignment: .leading)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Beaufort.color(step: step, scheme: scheme))
                                .frame(width: 40, height: 12)
                            Text(Beaufort.rangeText(step: step) + " kn")
                                .font(.system(size: 15).monospacedDigit())
                                .foregroundStyle(Tokens.inkBody(scheme))
                            Spacer()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Beaufort \(step), \(Beaufort.rangeText(step: step)) knots")
                    }
                    Text("Bars are sustained wind in knots, coloured by Beaufort step. The line with tick caps is the gust. Arrows point where the wind blows to; text says where it comes from.")
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.inkSecondary(scheme))
                        .padding(.top, 4)
                }
                card {
                    Text("Weather data by Open-Meteo.com · CC BY 4.0")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.inkPrimary(scheme))
                    Text(version)
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Tokens.inkSecondary(scheme))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Tokens.ground(scheme))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Tokens.ground(scheme), for: .navigationBar)
    }

    private var legendSteps: [Int] { [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
