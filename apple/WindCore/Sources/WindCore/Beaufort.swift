import Foundation
import SwiftUI

/// One colour-set entry of the Beaufort ramp (HANDOFF §4.1).
///
/// `assetName` is the Asset Catalog colour-set name used by the app targets; the hex values let
/// package previews and macOS tests work without a catalog.
public struct BeaufortToken: Sendable, Hashable {
    /// Asset Catalog name: `bft.calm`, `bft.2` … `bft.10`.
    public let assetName: String
    /// Dark-mode / watch hex, e.g. `#4FA3D8`.
    public let darkHex: String
    /// Light-mode hex.
    public let lightHex: String
    /// Asset name of the 2 pt inset stroke (only `bft.10` has one; it uses `bft.8`).
    public let strokeAssetName: String?

    public init(assetName: String, darkHex: String, lightHex: String, strokeAssetName: String? = nil) {
        self.assetName = assetName
        self.darkHex = darkHex
        self.lightHex = lightHex
        self.strokeAssetName = strokeAssetName
    }

    public var darkColor: Color { Color(hex: darkHex) }
    public var lightColor: Color { Color(hex: lightHex) }

    /// Hex-based colour for the given scheme. Watch always uses `.dark`.
    public func color(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkColor : lightColor
    }

    /// Hex-based stroke colour for `bft.10` (the `bft.8` colour), nil otherwise.
    public func strokeColor(for scheme: ColorScheme) -> Color? {
        guard strokeAssetName != nil else { return nil }
        return Beaufort.colorToken(step: 8).color(for: scheme)
    }
}

/// Beaufort scale on sustained knots (HANDOFF §2) and the colour ramp (§4.1).
public enum Beaufort {
    /// True Beaufort number 0…12 from sustained knots.
    ///
    /// Bands follow the handoff: `≤3 → 0–1, 4–6 → 2, 7–10 → 3, 11–16 → 4, 17–21 → 5, 22–27 → 6,
    /// 28–33 → 7, 34–40 → 8, 41–47 → 9, 48+ → 10+`. Within the handoff's merged bands the true
    /// number is returned: 0 for `kn < 1`, 1 for `1…3`; 10 for `48…55`, 11 for `56…63`, 12 for `64+`.
    /// Colour never distinguishes 0 from 1 or 10 from 11/12 (see `colorToken(step:)`).
    public static func step(kn: Int) -> Int {
        switch kn {
        case ..<1: 0
        case 1...3: 1
        case 4...6: 2
        case 7...10: 3
        case 11...16: 4
        case 17...21: 5
        case 22...27: 6
        case 28...33: 7
        case 34...40: 8
        case 41...47: 9
        case 48...55: 10
        case 56...63: 11
        default: 12
        }
    }

    /// Knot range text for a legend row, by colour band: `"≤ 3"`, `"4–6"`, … `"48+"`.
    public static func rangeText(step: Int) -> String {
        switch step {
        case ...1: "≤ 3"
        case 2: "4–6"
        case 3: "7–10"
        case 4: "11–16"
        case 5: "17–21"
        case 6: "22–27"
        case 7: "28–33"
        case 8: "34–40"
        case 9: "41–47"
        default: "48+"
        }
    }

    /// The ten colour tokens in ramp order: calm (0–1), 2 … 9, 10+.
    public static let tokens: [BeaufortToken] = [
        BeaufortToken(assetName: "bft.calm", darkHex: "#5C6B7A", lightHex: "#8A97A6"),
        BeaufortToken(assetName: "bft.2", darkHex: "#4FA3D8", lightHex: "#2A86C4"),
        BeaufortToken(assetName: "bft.3", darkHex: "#3FC2A0", lightHex: "#1E9E80"),
        BeaufortToken(assetName: "bft.4", darkHex: "#8DD44A", lightHex: "#5FA82E"),
        BeaufortToken(assetName: "bft.5", darkHex: "#F2D13D", lightHex: "#C9A800"),
        BeaufortToken(assetName: "bft.6", darkHex: "#F59A2B", lightHex: "#E07F12"),
        BeaufortToken(assetName: "bft.7", darkHex: "#EC5A2A", lightHex: "#D6451A"),
        BeaufortToken(assetName: "bft.8", darkHex: "#E0245E", lightHex: "#C7154B"),
        BeaufortToken(assetName: "bft.9", darkHex: "#A32CD1", lightHex: "#8C1FB3"),
        BeaufortToken(assetName: "bft.10", darkHex: "#F5F5F7", lightHex: "#1B1B1F", strokeAssetName: "bft.8"),
    ]

    /// Colour token for a Beaufort step. 0 and 1 share `bft.calm`; 10, 11, 12 share `bft.10`.
    public static func colorToken(step: Int) -> BeaufortToken {
        let index = min(max(step, 1), 10) - 1
        return tokens[index]
    }

    /// Colour token straight from sustained knots.
    public static func colorToken(kn: Int) -> BeaufortToken {
        colorToken(step: step(kn: kn))
    }

    /// Hex colour for a step and scheme (previews, charts without an asset catalog).
    public static func color(step: Int, scheme: ColorScheme = .dark) -> Color {
        colorToken(step: step).color(for: scheme)
    }
}

extension Color {
    /// Builds a colour from `#RRGGBB` or `#RRGGBBAA` (the `#` is optional).
    public init(hex: String) {
        var s = Substring(hex)
        if s.hasPrefix("#") { s = s.dropFirst() }
        guard let value = UInt64(s, radix: 16), s.count == 6 || s.count == 8 else {
            self = .clear
            return
        }
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
