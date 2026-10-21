import Foundation

/// A user-chosen location as stored on device and synced phone → watch (D5).
public struct SavedLocation: Codable, Sendable, Hashable {
    public var name: String
    public var lat: Double
    public var lon: Double
    /// IANA identifier, informational; the payload's `loc.tz` drives display.
    public var tz: String

    public init(name: String, lat: Double, lon: Double, tz: String) {
        self.name = name
        self.lat = lat
        self.lon = lon
        self.tz = tz
    }

    /// The built-in default (DESIGN §0): Port Townsend Bay, the `cell_selection=sea` point.
    public static let portTownsendBay = SavedLocation(name: "Port Townsend Bay", lat: 48.0907, lon: -122.7773, tz: "America/Los_Angeles")

    public var customLocation: CustomLocation { CustomLocation(lat: lat, lon: lon) }
    public var timeZone: TimeZone { TimeZone(identifier: tz) ?? .current }

    /// `48.09, −122.78` (two decimals, true minus sign).
    public var coordinateText: String {
        Self.coordinateText(lat: lat, lon: lon)
    }

    public static func coordinateText(lat: Double, lon: Double) -> String {
        func f(_ v: Double) -> String {
            let s = String(format: "%.2f", abs(v))
            return v < 0 ? "\u{2212}" + s : s
        }
        return "\(f(lat)), \(f(lon))"
    }

    /// Parses `"48.1, -122.75"` style text; nil when the text is not two numbers.
    public static func parseCoordinates(_ text: String) -> (lat: Double, lon: Double)? {
        let cleaned = text.replacingOccurrences(of: "\u{2212}", with: "-")
        let parts = cleaned.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              (-90...90).contains(lat), (-180...180).contains(lon)
        else { return nil }
        return (lat, lon)
    }
}

/// Reads and writes the location preference in the shared (App Group) `UserDefaults`, and
/// encodes it for `WCSession` application context.
public enum LocationSettings {
    public static let customLocationKey = "customLocation"
    public static let useCustomKey = "useCustom"

    public struct Preferences: Sendable, Equatable {
        public var custom: SavedLocation?
        public var useCustom: Bool

        public init(custom: SavedLocation?, useCustom: Bool) {
            self.custom = custom
            self.useCustom = useCustom
        }

        public static let `default` = Preferences(custom: nil, useCustom: false)

        /// `useCustom` only counts when a custom location exists.
        public var effectiveUseCustom: Bool { useCustom && custom != nil }
        public var activeCustom: CustomLocation? { effectiveUseCustom ? custom?.customLocation : nil }
    }

    public static func load(from defaults: UserDefaults) -> Preferences {
        let custom = defaults.data(forKey: customLocationKey).flatMap { try? JSONDecoder().decode(SavedLocation.self, from: $0) }
        return Preferences(custom: custom, useCustom: defaults.bool(forKey: useCustomKey))
    }

    public static func save(_ prefs: Preferences, to defaults: UserDefaults) {
        if let custom = prefs.custom, let data = try? JSONEncoder().encode(custom) {
            defaults.set(data, forKey: customLocationKey)
        } else {
            defaults.removeObject(forKey: customLocationKey)
        }
        defaults.set(prefs.useCustom, forKey: useCustomKey)
    }

    /// Plist-safe dictionary for `WCSession.updateApplicationContext`.
    public static func applicationContext(_ prefs: Preferences) -> [String: Any] {
        var ctx: [String: Any] = [useCustomKey: prefs.useCustom]
        if let custom = prefs.custom, let data = try? JSONEncoder().encode(custom) {
            ctx[customLocationKey] = data
        }
        return ctx
    }

    public static func preferences(fromApplicationContext ctx: [String: Any]) -> Preferences {
        let custom = (ctx[customLocationKey] as? Data).flatMap { try? JSONDecoder().decode(SavedLocation.self, from: $0) }
        return Preferences(custom: custom, useCustom: ctx[useCustomKey] as? Bool ?? false)
    }
}
