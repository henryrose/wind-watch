import SwiftUI
import WindCore

/// Pushed screens. `WW_SCREEN=location|about` opens one at launch (screenshots).
enum Screen: Hashable {
    case location
    case about
}

/// HANDOFF §8.1: header, now block, summary, chart card, table; everything scrolls together.
struct MainView: View {
    @Environment(ForecastSession.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var path: [Screen]

    init() {
        switch ProcessInfo.processInfo.environment["WW_SCREEN"] {
        case "location": _path = State(initialValue: [.location])
        case "about": _path = State(initialValue: [.about])
        default: _path = State(initialValue: [])
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    HeaderView()
                        .padding(.bottom, 14)
                    NowBlock()
                        .padding(.bottom, 14)
                    if let forecast = model.forecast, model.trustState.showsNumbers {
                        Text(forecast.summary)
                            .font(Tokens.summaryFont(watch: false))
                            .foregroundStyle(Tokens.inkBody(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 14)
                        chartCard(forecast)
                            .padding(.bottom, 14)
                        HourTable(forecast: forecast, now: model.now, tier: model.ageTier)
                    } else {
                        emptyBody
                    }
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Tokens.ground(scheme))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Screen.self) { screen in
                switch screen {
                case .location: LocationSettingsView()
                case .about: AboutView()
                }
            }
        }
        .tint(Tokens.inkPrimary(scheme))
    }

    private func chartCard(_ forecast: Forecast) -> some View {
        let chart = ChartModel(forecast: forecast, now: model.now, window: .all, scheme: scheme)
        return WindChart(model: chart, style: .phone)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .padding(.horizontal, 10)
            .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var emptyBody: some View {
        switch model.trustState {
        case .firstRun:
            Text(TrustLine.firstRunText)
                .font(Tokens.summaryFont(watch: false))
                .foregroundStyle(Tokens.inkBody(scheme))
        case .pastHorizon:
            Text("The last HRRR run has ended. Open the app with a connection to fetch the next one.")
                .font(Tokens.summaryFont(watch: false))
                .foregroundStyle(Tokens.inkBody(scheme))
        default:
            EmptyView()
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.trustState == .firstRun {
                ProgressView().controlSize(.small)
                Text(TrustLine.firstRunFooterText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Tokens.inkSecondary(scheme))
            }
            Spacer()
            NavigationLink(value: Screen.about) {
                Label("About", systemImage: "info.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.inkSecondary(scheme))
            }
            .frame(minHeight: 44)
            .accessibilityLabel("About Wind Watch")
        }
        .padding(.top, 8)
    }
}

#Preview("Main · fixture") {
    MainView().environment(ForecastSession(bundleInfo: [:], environment: ["WW_FIXTURE": "1"]))
}
