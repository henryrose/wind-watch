import SwiftUI
import WindCore

/// Pushed screens. `WW_SCREEN=location|about` opens one at launch (screenshots).
enum Screen: Hashable {
    case location
    case about
}

/// iPhone main screen (HANDOFF §6.4, §6.4d, §8.1, `Phone-Main.dc.html`): header, the fixed-height
/// readout plate (now, or the scrubbed hour), the edge-to-edge chart, summary, the collapsible
/// hourly table, footer; everything scrolls together. Landscape (`verticalSizeClass == .compact`)
/// swaps to `LandscapeView` (§6.4b).
struct MainView: View {
    @Environment(ForecastSession.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var path: [Screen]
    @State private var scrub = ScrubState()

    init() {
        let env = ProcessInfo.processInfo.environment
        switch env["WW_SCREEN"] {
        case "location": _path = State(initialValue: [.location])
        case "about": _path = State(initialValue: [.about])
        default: _path = State(initialValue: [])
        }
        #if DEBUG
        // `WW_SCRUB=<hour index>` pins the scrub state; `WW_TABLE=1|0` presets the table disclosure.
        if let s = env["WW_SCRUB"], let i = Int(s) {
            _scrub = State(initialValue: ScrubState(index: i, pinned: true))
        }
        if let t = env["WW_TABLE"] {
            UserDefaults.standard.set(t == "1", forKey: HourTableDisclosure.storageKey)
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
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                if let forecast = model.forecast, model.trustState.showsNumbers {
                    ChartCard(forecast: forecast, scrub: $scrub, clamped: typeSize.isAccessibilitySize)
                        .padding(.bottom, 12)
                    Text(forecast.summary)
                        .font(Tokens.summaryFont(watch: false))
                        .foregroundStyle(Tokens.inkBody(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                    HourTableDisclosure(forecast: forecast, now: model.now, tier: model.ageTier)
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

    /// `Wind Watch · weather data by Open-Meteo.com` in `ink.disabled` 12 (HANDOFF §10a), with the About
    /// link on the right; the first-run spinner replaces the attribution while trying.
    private var footer: some View {
        HStack(spacing: 8) {
            if model.trustState == .firstRun {
                ProgressView().controlSize(.small)
                Text(TrustLine.firstRunFooterText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Tokens.inkSecondary(scheme))
            } else {
                Text("Wind Watch · weather data by Open-Meteo.com")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.inkDisabled(scheme))
            }
            Spacer()
            NavigationLink(value: Screen.about) {
                Text("About")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tokens.inkSecondary(scheme))
            }
            .frame(minHeight: 44)
            .accessibilityLabel("About Wind Watch")
        }
        .padding(.top, 10)
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

/// The chart block. Default sizes (`Phone-Main.dc.html`, §6.4d): edge to edge — `card` fill with
/// no radius, padding 12 top / 8 bottom, the title row (`Wed 9am → Fri 5am` + hint) keeps the
/// 16 pt inset, the plot is the full screen width and ignores the horizontal safe area. At
/// accessibility sizes (`Phone-Table-LargeType.dc.html`) it is the inset rounded card (radius 14,
/// padding 8/0/10) with the clamped 152 pt plot and no title row.
struct ChartCard: View {
    let forecast: Forecast
    @Binding var scrub: ScrubState
    let clamped: Bool

    @Environment(ForecastSession.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let chart = ChartModel(forecast: forecast, now: model.now, window: .all, scheme: scheme)
        if clamped {
            WindChart(model: chart, style: .phoneClamped, selection: scrub.index, onScrub: { scrub.apply($0) })
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Derivations.chartTitle(forecast: forecast))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Tokens.inkPrimary(scheme))
                    Spacer()
                    Text(scrub.index == nil ? "touch a bar for that hour" : "release to return to now")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tokens.inkSecondary(scheme))
                }
                .lineLimit(1)
                .padding(.horizontal, 16)
                WindChart(model: chart, style: .phonePortrait, selection: scrub.index, onScrub: { scrub.apply($0) })
                    .ignoresSafeArea(.container, edges: .horizontal)
            }
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Tokens.card(scheme))
            .ignoresSafeArea(.container, edges: .horizontal)
        }
    }
}

#Preview("Main · fixture") {
    MainView().environment(ForecastSession(bundleInfo: [:], environment: ["WW_FIXTURE": "1"]))
}
