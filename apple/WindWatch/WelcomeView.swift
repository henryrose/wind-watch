import SwiftUI
import WindCore

/// First launch on iPhone: pick Port Townsend Bay (one tap) or any point HRRR covers. "Somewhere
/// else" pushes the Location screen, which closes this on Save; its back chevron returns here.
/// Shown once (`Welcome`); afterwards the gear on the main screen changes the location.
/// `WW_WELCOME=1` forces it (screenshots).
struct WelcomeView: View {
    @Environment(ForecastSession.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var path: [Step] = []

    private enum Step: Hashable { case pick }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BrandLockup(tile: 30, type: 26, gap: 10, scheme: scheme)
                        .padding(.top, 24)
                    Text("Where’s your water?")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Tokens.inkPrimary(scheme))
                        .padding(.top, 20)
                    Text("Wind Watch shows the hourly HRRR wind forecast for one spot, on your iPhone, watch and complications. Start with Port Townsend Bay or choose anywhere HRRR covers: the continental US and nearby Canada and Mexico.")
                        .font(.system(size: 17))
                        .lineSpacing(3)
                        .foregroundStyle(Tokens.inkBody(scheme))

                    choice(
                        title: SavedLocation.portTownsendBay.name,
                        detail: "Default · \(SavedLocation.portTownsendBay.coordinateText)",
                        symbol: "checkmark.circle.fill", tint: Color(hex: "#4FA3D8")
                    ) {
                        model.selectDefault()
                        model.completeWelcome()
                    }
                    .accessibilityLabel("Use the default, \(SavedLocation.portTownsendBay.name)")
                    .padding(.top, 8)

                    choice(
                        title: "Somewhere else",
                        detail: "Search a place, paste lat, lon, or drop a pin",
                        symbol: "chevron.right", tint: Tokens.inkSecondary(scheme)
                    ) {
                        path = [.pick]
                    }
                    .accessibilityLabel("Choose another location")

                    Text("Change it any time with the gear on the main screen.")
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.inkSecondary(scheme))
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Tokens.ground(scheme))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Step.self) { _ in
                LocationSettingsView { model.completeWelcome() }
            }
        }
        .tint(Tokens.inkPrimary(scheme))
    }

    private func choice(title: String, detail: String, symbol: String, tint: Color,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Tokens.inkPrimary(scheme))
                    Text(detail)
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Tokens.inkSecondary(scheme))
                }
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: symbol == "chevron.right" ? 17 : 24, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
