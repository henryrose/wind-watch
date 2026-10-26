import SwiftUI
import WindCore

/// HANDOFF §7.4 / §8.3: `Locations` Rounded Bold 13 (4 pt side inset), then the iPhone's list
/// in the iPhone's order, Crown-scrolled: one full-width button per location (44 pt min, radius 12,
/// plates 14 % / 8 % white, padding 0 10) with a two-line label (name Semibold 14 · coordinates
/// Regular 10 secondary), a filled blue check on the selected row and an empty ring on the others.
/// Tapping selects; editing stays on the iPhone. Then the brand footer (HANDOFF §10a): round mark +
/// `Wind Watch 1.0` Rounded Bold 11 over `Weather data by Open-Meteo.com` Regular 10 secondary.
struct SettingsView: View {
    @Environment(ForecastSession.self) private var session

    private var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        ScrollView {
            content
        }
        .background(Tokens.groundWatch(.dark))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Locations")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Tokens.inkPrimary(.dark))
                .padding(.horizontal, 4)
            VStack(spacing: 5) {
                ForEach(session.preferences.locations) { location in
                    let selected = location.id == session.preferences.selectedID
                    plate(name: location.name, sub: location.coordinateText, selected: selected, enabled: true) {
                        session.select(location.id)
                    }
                    .accessibilityLabel(location.name)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    BrandMark(size: 12, round: true)
                    Text("Wind Watch \(shortVersion)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Tokens.inkBody(.dark))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Wind Watch \(shortVersion)")
                Text("Weather data by Open-Meteo.com")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Tokens.inkSecondary(.dark))
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
    }

    private func plate(name: String, sub: String, selected: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(enabled ? Tokens.inkPrimary(.dark) : Tokens.inkDisabled(.dark))
                    Text(sub)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(enabled ? Tokens.inkSecondary(.dark) : Tokens.inkDisabled(.dark))
                }
                .lineLimit(1)
                .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                mark(selected: selected)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.white.opacity(selected ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// Selected: `checkmark.circle.fill`, black check on the default blue (`bft.2`).
    /// Unselected: `circle` in `ink.secondary`. 14 pt.
    @ViewBuilder
    private func mark(selected: Bool) -> some View {
        if selected {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Tokens.groundWatch(.dark), Beaufort.color(step: 2, scheme: .dark))
                .font(.system(size: 14, weight: .bold))
        } else {
            Image(systemName: "circle")
                .foregroundStyle(Tokens.inkSecondary(.dark))
                .font(.system(size: 14, weight: .medium))
        }
    }
}
