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
    /// The chart range (§12a), remembered; 48 h by default.
    @AppStorage(ChartRange.storageKey) private var range: ChartRange = .hours48
    /// Screen width: the portrait plot is edge to edge, and the 7-day slot rule needs it.
    @State private var width: CGFloat = 402

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
        // `WW_RANGE=48h|7d` presets the chart range; `WW_UNIT=f|c` the temperature unit.
        if let r = env["WW_RANGE"], let value = ChartRange(rawValue: r) {
            UserDefaults.standard.set(value.rawValue, forKey: ChartRange.storageKey)
        }
        if let u = env["WW_UNIT"]?.uppercased(), let value = TemperatureUnit(rawValue: u) {
            UserDefaults.windShared.set(value.rawValue, forKey: TemperatureUnit.storageKey)
        }
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if verticalSizeClass == .compact {
                    LandscapeView(scrub: $scrub, range: $range)
                } else {
                    portrait
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onChange(of: range) { scrub = ScrubState() }
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
                let chart = chartModel
                HeaderView(range: range)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                NowBlock(scrubbed: chart?.selected(scrub.index), chart: chart)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                if let forecast = model.forecast, let chart {
                    ChartCard(forecast: forecast, chart: chart, scrub: $scrub, range: $range, clamped: typeSize.isAccessibilitySize)
                        .padding(.bottom, 12)
                    Text(forecast.summary)
                        .font(Tokens.summaryFont(watch: false))
                        .foregroundStyle(Tokens.inkBody(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                    HourTableDisclosure(forecast: forecast, now: model.now, tier: model.ageTier, range: range)
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

    /// The portrait chart for the current range, sized for the slot rule: edge to edge, or the
    /// inset clamped card (16 pt margins) at accessibility sizes. Nil when no numbers are shown.
    private var chartModel: ChartModel? {
        guard let forecast = model.forecast, model.trustState.showsNumbers else { return nil }
        let plotWidth = typeSize.isAccessibilitySize ? width - 32 : width
        return ChartModel(forecast: forecast, now: model.now, window: range.window, scheme: scheme, plotWidth: plotWidth)
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

extension ChartModel {
    /// The plotted slot a scrub index selects (`WW_SCRUB` may name any hour inside a block).
    func selected(_ index: Int?) -> HourPoint? { index.flatMap { point(containing: $0) } }
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

/// The chart block. Default sizes (`Phone-Main.dc.html`, `Phone-Main-7d.dc.html`, §6.4d): edge to
/// edge — `card` fill with no radius, padding 12 top / 8 bottom. The title row keeps the 16 pt
/// inset: the range title (`Wed 9am → Fri 5am`, Bold 15) over an 11 pt secondary line (the hint
/// in 48 h; `HRRR hourly · NBM 3-hourly after Fri 5am` in 7 d; `release to return to now` while
/// scrubbing either), and the `48 h | 7 d` control right. Then the sky band (14 pt + 2) when the
/// payload has sky data, and the plot at the full screen width, ignoring the horizontal safe area.
/// At accessibility sizes (`Phone-Table-LargeType.dc.html`) it is the inset rounded card (radius
/// 14, padding 8/0/10) with the clamped 152 pt plot; the range control stays above it.
struct ChartCard: View {
    let forecast: Forecast
    let chart: ChartModel
    @Binding var scrub: ScrubState
    @Binding var range: ChartRange
    let clamped: Bool

    @Environment(\.colorScheme) private var scheme

    private var selection: Int? { chart.selected(scrub.index)?.index }

    var body: some View {
        let week = range == .days7
        if clamped {
            VStack(alignment: .trailing, spacing: 8) {
                SegmentedPicker(range: $range)
                    .padding(.horizontal, 16)
                VStack(spacing: 2) {
                    SkyBand(model: chart, style: .phoneClamped)
                    WindChart(model: chart, style: week ? .phoneClampedWeek : .phoneClamped, selection: selection, onScrub: { scrub.apply($0) })
                }
                .padding(.top, 8)
                .padding(.bottom, 10)
                .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(week ? Derivations.weekTitle(forecast: forecast) : Derivations.chartTitle(forecast: forecast))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Tokens.inkPrimary(scheme))
                            .frame(height: 20)
                        Text(subtitle(week: week))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Tokens.inkSecondary(scheme))
                            .frame(height: 14)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    Spacer(minLength: 8)
                    SegmentedPicker(range: $range)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                VStack(spacing: 2) {
                    SkyBand(model: chart, style: .phonePortrait)
                    WindChart(model: chart, style: week ? .phonePortraitWeek : .phonePortrait, selection: selection, onScrub: { scrub.apply($0) })
                }
                .ignoresSafeArea(.container, edges: .horizontal)
            }
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Tokens.card(scheme))
            .ignoresSafeArea(.container, edges: .horizontal)
        }
    }

    private func subtitle(week: Bool) -> String {
        if scrub.index != nil { return "release to return to now" }
        return week ? Derivations.weekSubtitle(forecast: forecast) : "touch a bar for that hour"
    }
}

#Preview("Main · fixture") {
    MainView().environment(ForecastSession(bundleInfo: [:], environment: ["WW_FIXTURE": "1"]))
}
