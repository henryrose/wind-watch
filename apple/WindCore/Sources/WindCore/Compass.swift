import Foundation

/// 8-point compass helpers (HANDOFF §2). Wind direction on the wire is FROM; arrows point TO.
public enum Compass {
    /// Sector labels, clockwise from north.
    public static let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    /// Spoken names for VoiceOver, same order as `points`.
    public static let spokenNames = [
        "north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest",
    ]

    /// SF Symbol names for an arrow pointing in each sector direction, same order as `points`.
    public static let arrowSymbols = [
        "arrow.up", "arrow.up.right", "arrow.right", "arrow.down.right",
        "arrow.down", "arrow.down.left", "arrow.left", "arrow.up.left",
    ]

    /// Reduces any integer bearing into `0..<360`.
    public static func normalized(_ degrees: Int) -> Int {
        let m = degrees % 360
        return m < 0 ? m + 360 : m
    }

    /// Sector index 0…7 for a bearing: `Int((deg + 22.5) / 45) % 8`.
    public static func sectorIndex(degrees: Int) -> Int {
        Int((Double(normalized(degrees)) + 22.5) / 45) % 8
    }

    /// 8-point label for a FROM bearing, e.g. `"W"`.
    public static func label(from dirFrom: Int) -> String {
        points[sectorIndex(degrees: dirFrom)]
    }

    /// Display text, always `"from W"` style.
    public static func fromText(dirFrom: Int) -> String {
        "from " + label(from: dirFrom)
    }

    /// Spoken form for VoiceOver, e.g. `"from the west"`.
    public static func spokenFromText(dirFrom: Int) -> String {
        "from the " + spokenNames[sectorIndex(degrees: dirFrom)]
    }

    /// Bearing the wind blows TO: `(dirFrom + 180) mod 360`.
    public static func toBearing(dirFrom: Int) -> Int {
        normalized(dirFrom + 180)
    }

    /// Rotation to apply to an up-pointing arrow glyph so it points where the wind blows TO.
    public static func arrowRotation(dirFrom: Int) -> Double {
        Double(toBearing(dirFrom: dirFrom))
    }

    /// SF Symbol name for the 8-point arrow pointing where the wind blows TO (inline complications).
    public static func arrowSymbolName(dirFrom: Int) -> String {
        arrowSymbols[sectorIndex(degrees: toBearing(dirFrom: dirFrom))]
    }
}
