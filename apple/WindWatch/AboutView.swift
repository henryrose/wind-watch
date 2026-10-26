import SwiftUI
import WindCore

/// HANDOFF §8.4 / `Phone-About.dc.html`: the Temperature card (`°F | °C`, §12b), then three
/// cards — the model, the Beaufort legend (step · swatch bar · knots), attribution with the
/// version line.
struct AboutView: View {
    @Environment(\.colorScheme) private var scheme
    /// Shared with the watch through the App Group defaults (it shows no temperature today).
    @AppStorage(TemperatureUnit.storageKey, store: .windShared) private var unit: TemperatureUnit = .fahrenheit

    static let contactEmail = "windwatch@wilder-roses.com"
    static let privacyURL = URL(string: "https://windwatch.wilder-roses.com/privacy.html")!

    private var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// Body copy on cards is a touch brighter than `ink.body` in the design (`#E6E9ED`).
    private var cardBody: Color { scheme == .dark ? Color(hex: "#E6E9ED") : Tokens.inkPrimary(scheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BackHeader {
                    // Phone-About.dc.html: centred row, version nudged 4 pt down.
                    HStack(alignment: .center, spacing: 10) {
                        BrandLockup(tile: 30, type: 26, gap: 10, scheme: scheme)
                        Text(shortVersion)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Tokens.inkSecondary(scheme))
                            .padding(.top, 4)
                            .accessibilityLabel("version \(shortVersion)")
                    }
                }
                // Temperature: 17 Semibold title over the 13 caption, the 30 pt control right.
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Temperature")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Tokens.inkPrimary(scheme))
                        Text("Wind is always knots.")
                            .font(.system(size: 13))
                            .foregroundStyle(Tokens.inkSecondary(scheme))
                    }
                    Spacer(minLength: 8)
                    SegmentedPicker(unit: $unit)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                card(spacing: 8) {
                    sectionLabel("The model")
                    Text("HRRR is NOAA's 3 km hourly-updating forecast for the continental US; each run looks 18 hours ahead, and every 6 hours a run looks 48. Wind Watch shows the latest run that reaches furthest, so the chart's horizon moves between about 40 and 47 hours as runs come and go. The run label (\"HRRR 15Z\") is the model's start time in UTC; \"as of\" is when this device last got new data.")
                        .font(.system(size: 17))
                        .lineSpacing(3)
                        .foregroundStyle(cardBody)
                }
                card(spacing: 10) {
                    sectionLabel("Beaufort colours · sustained wind, knots")
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                        ForEach(legendRows, id: \.label) { row in
                            GridRow {
                                Text(row.label)
                                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                                    .foregroundStyle(Tokens.inkPrimary(scheme))
                                    .frame(width: 36, alignment: .leading)
                                swatch(step: row.step)
                                Text(row.range)
                                    .font(.system(size: 15).monospacedDigit())
                                    .foregroundStyle(Tokens.inkSecondary(scheme))
                                    .frame(width: 70, alignment: .trailing)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Beaufort \(row.label), \(row.range) knots")
                        }
                    }
                    Text("Gusts are the white line with a cap over each bar. Arrows point where the wind is going.")
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.inkSecondary(scheme))
                }
                card(spacing: 6) {
                    HStack(spacing: 0) {
                        Text("Weather data by ")
                            .foregroundStyle(cardBody)
                        Link("Open-Meteo.com", destination: URL(string: "https://open-meteo.com")!)
                            .foregroundStyle(Color(hex: "#9BB7D4"))
                        Text(" · CC BY 4.0")
                            .foregroundStyle(cardBody)
                    }
                    .font(.system(size: 15))
                    Text("Sunrise and twilight computed on device. Built for Port Townsend Bay; works anywhere HRRR covers.")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Tokens.inkSecondary(scheme))
                    HStack(spacing: 0) {
                        Link("Privacy", destination: Self.privacyURL)
                        Text(" · ").foregroundStyle(Tokens.inkSecondary(scheme))
                        Link(Self.contactEmail, destination: URL(string: "mailto:\(Self.contactEmail)")!)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#9BB7D4"))
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Tokens.ground(scheme))
        .toolbar(.hidden, for: .navigationBar)
    }

    private struct LegendRow { let label: String; let step: Int; let range: String }

    private var legendRows: [LegendRow] {
        [LegendRow(label: "0–1", step: 1, range: "< 4")]
            + (2...9).map { LegendRow(label: "\($0)", step: $0, range: Beaufort.rangeText(step: $0)) }
            + [LegendRow(label: "10+", step: 10, range: "48+")]
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Tokens.inkSecondary(scheme))
    }

    /// Full-width 18 pt swatch bar, radius 5; `bft.10` keeps its 2 pt `bft.8` inset stroke.
    private func swatch(step: Int) -> some View {
        let token = Beaufort.colorToken(step: step)
        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(token.color(for: scheme))
            .overlay {
                if let stroke = token.strokeColor(for: scheme) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).inset(by: 1).stroke(stroke, lineWidth: 2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 18)
    }

    private func card<Content: View>(spacing: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.card(scheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
