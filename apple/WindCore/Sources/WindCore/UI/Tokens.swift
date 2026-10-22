import SwiftUI

/// Ground, ink and accent colours (HANDOFF §4.2) and the type scale (§4.3).
///
/// Colours are hex-based so the package renders without an asset catalog; the app targets may
/// mirror them in a catalog under the same names. Watch surfaces always pass `.dark`.
public enum Tokens {
    // MARK: Colours (§4.2)

    /// Watch app background. Dark only.
    public static func groundWatch(_ scheme: ColorScheme) -> Color { Color(hex: "#000000") }
    /// Phone / web page background.
    public static func ground(_ scheme: ColorScheme) -> Color { pick(scheme, "#0B0E12", "#F4F5F7") }
    /// Chart card, settings cards, chips.
    public static func card(_ scheme: ColorScheme) -> Color { pick(scheme, "#171C23", "#FFFFFF") }
    /// Table rules.
    public static func hairline(_ scheme: ColorScheme) -> Color { pick(scheme, "#2A2F36", "#D9DDE3") }
    /// Numbers, titles.
    public static func inkPrimary(_ scheme: ColorScheme) -> Color { pick(scheme, "#FFFFFF", "#0B0E12") }
    /// Summary text.
    public static func inkBody(_ scheme: ColorScheme) -> Color { pick(scheme, "#C7CED8", "#3A414B") }
    /// Labels, fresh trust line.
    public static func inkSecondary(_ scheme: ColorScheme) -> Color { pick(scheme, "#9AA4B1", "#5F6975") }
    /// Numbers in the Old state.
    public static func inkOld(_ scheme: ColorScheme) -> Color { pick(scheme, "#B8BEC7", "#7A8390") }
    /// `—` placeholder.
    public static func inkDisabled(_ scheme: ColorScheme) -> Color { pick(scheme, "#5C6B7A", "#A0A8B2") }
    /// The readout's `Now ·` label bar (§6.4d): the Beaufort 2 blue; white while scrubbing.
    public static func nowBar(_ scheme: ColorScheme) -> Color { pick(scheme, "#4FA3D8", "#2A86C4") }
    /// Stale / old / offline trust line.
    public static func trustAmber(_ scheme: ColorScheme) -> Color { pick(scheme, "#FFB340", "#B86E00") }
    /// Sun markers.
    public static func sun(_ scheme: ColorScheme) -> Color { pick(scheme, "#FFB340", "#E08A00") }
    /// Rectangular / circular complication background.
    public static func complicationPlate(_ scheme: ColorScheme) -> Color { Color.white.opacity(0.10) }

    /// Ink for wind numbers and arrows given the age tier (Old drops to `ink.old`).
    public static func numberInk(_ scheme: ColorScheme, tier: AgeTier) -> Color {
        tier == .old ? inkOld(scheme) : inkPrimary(scheme)
    }

    private static func pick(_ scheme: ColorScheme, _ dark: String, _ light: String) -> Color {
        Color(hex: scheme == .dark ? dark : light)
    }

    // MARK: Type (§4.3)

    /// Hero sustained number: Rounded Heavy 84 (watch) / 72 (phone), monospaced digits.
    public static func heroFont(watch: Bool) -> Font {
        .system(size: watch ? 84 : 72, weight: .heavy, design: .rounded).monospacedDigit()
    }
    /// Tracking for the hero number: −3 % of the point size on watch.
    public static func heroTracking(watch: Bool) -> CGFloat { watch ? -0.03 * 84 : 0 }
    /// Hero unit "kn": Semibold 18 / 20, secondary.
    public static func heroUnitFont(watch: Bool) -> Font { .system(size: watch ? 18 : 20, weight: .semibold) }
    /// Gust value: Rounded Bold 27 / 26.
    public static func gustFont(watch: Bool) -> Font {
        .system(size: watch ? 27 : 26, weight: .bold, design: .rounded).monospacedDigit()
    }
    /// The "G" before the gust: Semibold 16 / 17, secondary.
    public static func gustPrefixFont(watch: Bool) -> Font { .system(size: watch ? 16 : 17, weight: .semibold) }
    /// Direction "from W": Semibold 18 / 17.
    public static func directionFont(watch: Bool) -> Font { .system(size: watch ? 18 : 17, weight: .semibold) }
    /// Summary: Regular 13 / 15.
    public static func summaryFont(watch: Bool) -> Font { .system(size: watch ? 13 : 15, weight: .regular) }
    /// Trust line: Medium 12 / 13, Semibold when amber.
    public static func trustFont(watch: Bool, amber: Bool) -> Font {
        .system(size: watch ? 12 : 13, weight: amber ? .semibold : .medium).monospacedDigit()
    }
    /// Location name: Semibold 11 secondary (watch) / Bold 28 (phone).
    public static func locationFont(watch: Bool) -> Font {
        watch ? .system(size: 11, weight: .semibold) : .system(size: 28, weight: .bold)
    }
    /// Axis ticks: Rounded Semibold 11.
    public static func axisFont(watch: Bool) -> Font {
        .system(size: 11, weight: .semibold, design: .rounded).monospacedDigit()
    }
    /// Table row body 17 / header 12.
    public static let tableRowFont: Font = .system(size: 17, weight: .regular).monospacedDigit()
    public static let tableRowNumberFont: Font = .system(size: 17, weight: .bold, design: .rounded).monospacedDigit()
    public static let tableHeaderFont: Font = .system(size: 12, weight: .semibold)

    /// Complication primary number: Rounded Heavy 30 (rectangular) / 18 (circular).
    public static func complicationPrimaryFont(circular: Bool) -> Font {
        .system(size: circular ? 18 : 30, weight: .heavy, design: .rounded).monospacedDigit()
    }
    /// Complication gust: Rounded Bold 15 (rectangular) / 8 (circular).
    public static func complicationGustFont(circular: Bool) -> Font {
        .system(size: circular ? 8 : 15, weight: .bold, design: .rounded).monospacedDigit()
    }
}

/// All colour tokens resolved for one scheme; handy in view bodies:
/// `let t = WindTheme(scheme)` then `t.inkPrimary`.
public struct WindTheme: Sendable, Equatable {
    public let scheme: ColorScheme

    public init(_ scheme: ColorScheme) { self.scheme = scheme }

    public var groundWatch: Color { Tokens.groundWatch(scheme) }
    public var ground: Color { Tokens.ground(scheme) }
    public var card: Color { Tokens.card(scheme) }
    public var hairline: Color { Tokens.hairline(scheme) }
    public var inkPrimary: Color { Tokens.inkPrimary(scheme) }
    public var inkBody: Color { Tokens.inkBody(scheme) }
    public var inkSecondary: Color { Tokens.inkSecondary(scheme) }
    public var inkOld: Color { Tokens.inkOld(scheme) }
    public var inkDisabled: Color { Tokens.inkDisabled(scheme) }
    public var trustAmber: Color { Tokens.trustAmber(scheme) }
    public var sun: Color { Tokens.sun(scheme) }
    public var complicationPlate: Color { Tokens.complicationPlate(scheme) }

    public func beaufort(step: Int) -> Color { Beaufort.color(step: step, scheme: scheme) }
}

extension View {
    /// The Old-state treatment for charts, pills and strips: `saturation 0.35, opacity 0.7`.
    public func oldStateDesaturation(_ tier: AgeTier) -> some View {
        saturation(tier == .old ? 0.35 : 1).opacity(tier == .old ? 0.7 : 1)
    }
}
