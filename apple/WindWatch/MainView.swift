import SwiftUI
import WindCore

/// Pushed screens. `WW_SCREEN=location|about` opens one at launch (screenshots).
enum Screen: Hashable {
    case location
    case about
}

/// iPhone main screen (HANDOFF §6.4, §8.1, `Phone-Main.dc.html`): header, readout row (now, or
/// the scrubbed hour), full-bleed chart card, summary, table; everything scrolls together.
/// Landscape (`verticalSizeClass == .compact`) swaps to `LandscapeView` (§6.4b).
struct MainView: View {
    @Environment(ForecastSession.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var path: [Screen]
    @State private var scrub = ScrubState()

    init() {
        switch ProcessInfo.processInfo.environment["WW_SCREEN"] {
        case "location": _path = State(initialValue: [.location])
        case "about": _path = State(initialValue: [.about])
        default: _path = State(initialValue: [])
        }
        #if DEBUG
        // `WW_SCRUB=<hour index>` pins the scrub state for screenshots.
        if let s = ProcessInfo.processInfo.environment["WW_SCRUB"], let i = Int(s) {
            _scrub = State(initialValue: ScrubState(index: i, pinned: true))
        }
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if verticalSizeClass == .compact {
                    LandscapeView(scrub: $scrub)
                } else {
                    portrait
                }
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

    private var portrait: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                HeaderView()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                NowBlock(scrub: scrub.index)
                    .padding(.horizontal, scrub.index == nil ? 16 : 12)
                    .padding(.bottom, 12)
                if let forecast = model.forecast, model.trustState.showsNumbers {
                    ChartCard(forecast: forecast, scrub: $scrub, style: typeSize.isAccessibilitySize ? .phoneClamped : .phonePortrait)
                        .padding(.bottom, 12)
                    Text(forecast.summary)
                        .font(Tokens.summaryFont(watch: false))
                        .foregroundStyle(Tokens.inkBody(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    HourTable(forecast: forecast, now: model.now, tier: model.ageTier)
                        .padding(.horizontal, 16)
                } else {
                    emptyBody
                        .padding(.horizontal, 16)
                }
                footer
                    .padding(.horizontal, 16)
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
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

/// The hour under the finger (HANDOFF §6.4). `pinned` keeps a DEBUG screenshot selection alive.
struct ScrubState {
    var index: Int?
    var pinned = false

    /// Applies a chart callback; a light haptic marks each hour change.
    mutating func apply(_ new: Int?) {
        if pinned { return }
        if new != index, new != nil {
            #if canImport(UIKit) && !os(watchOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
        index = new
    }
}

/// Full-bleed chart card (`Phone-Main.dc.html`): `card` fill, padding 12/16/10, title row
/// `Wed 9am → Fri 5am` + hint, then the chart.
struct ChartCard: View {
    let forecast: Forecast
    @Binding var scrub: ScrubState
    let style: ChartStyle

    @Environment(ForecastSession.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let chart = ChartModel(forecast: forecast, now: model.now, window: .all, scheme: scheme)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(Derivations.chartTitle(forecast: forecast))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Tokens.inkPrimary(scheme))
                Spacer()
                Text(scrub.index == nil ? "touch a bar for that hour" : "release to return to now")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Tokens.inkSecondary(scheme))
            }
            WindChart(model: chart, style: style, selection: scrub.index, onScrub: { scrub.apply($0) })
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
        .padding(.horizontal, 16)
        .background(Tokens.card(scheme))
    }
}

#Preview("Main · fixture") {
    MainView().environment(ForecastSession(bundleInfo: [:], environment: ["WW_FIXTURE": "1"]))
}
