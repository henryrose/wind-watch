import Foundation

/// One row of the Locations list (HANDOFF §8.3 round four): stored on device and synced
/// phone → watch. Every row is equal; Port Townsend Bay is only the seed.
public struct SavedLocation: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var lat: Double
    public var lon: Double
    /// IANA identifier, informational; the payload's `loc.tz` drives display.
    public var tz: String

    public init(id: UUID = UUID(), name: String, lat: Double, lon: Double, tz: String) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lon = lon
        self.tz = tz
    }

    /// Rows saved before the list existed (builds ≤ 7) have no `id`; they get a fresh one.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        lat = try c.decode(Double.self, forKey: .lat)
        lon = try c.decode(Double.self, forKey: .lon)
        tz = try c.decode(String.self, forKey: .tz)
    }

    /// The seed row (DESIGN §0): Port Townsend Bay, the `cell_selection=sea` point. Its id is fixed
    /// so the phone and watch seed the same row.
    public static let portTownsendBay = SavedLocation(
        id: UUID(uuidString: "6F1D4E2A-0000-4000-8000-000000000001")!,
        name: "Port Townsend Bay", lat: 48.0907, lon: -122.7773, tz: "America/Los_Angeles")

    /// True for the Port Townsend Bay sea point, whatever the row is called: that point is fetched
    /// from the baked default `/v1/wind`, every other point from `?lat&lon`.
    public var isDefaultPoint: Bool {
        abs(lat - Self.portTownsendBay.lat) < 0.0005 && abs(lon - Self.portTownsendBay.lon) < 0.0005
    }

    public var customLocation: CustomLocation { CustomLocation(lat: lat, lon: lon) }
    public var timeZone: TimeZone { TimeZone(identifier: tz) ?? .current }

    /// `48.09, −122.78` (two decimals, true minus sign).
    public var coordinateText: String {
        Self.coordinateText(lat: lat, lon: lon)
    }

    public static func coordinateText(lat: Double, lon: Double) -> String {
        func f(_ v: Double) -> String {
            let s = String(format: "%.3f", abs(v))
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

/// Reads and writes the Locations list in the shared (App Group) `UserDefaults`, and encodes it
/// for `WCSession` application context. Builds ≤ 7 stored one optional custom location plus a
/// `useCustom` flag; those keys are migrated on load and still written so an older watch app can
/// follow a newer phone.
public enum LocationSettings {
    public static let locationsKey = "locations"
    public static let selectedKey = "selectedLocationID"
    public static let customLocationKey = "customLocation"
    public static let useCustomKey = "useCustom"
    /// HANDOFF §8.3: up to 12 locations.
    public static let maxCount = 12

    public struct Preferences: Sendable, Equatable {
        /// Never empty; at most `maxCount`.
        public private(set) var locations: [SavedLocation]
        public private(set) var selectedID: UUID

        public init(locations: [SavedLocation], selectedID: UUID? = nil) {
            let list = Array((locations.isEmpty ? [SavedLocation.portTownsendBay] : locations).prefix(LocationSettings.maxCount))
            self.locations = list
            self.selectedID = selectedID.flatMap { id in list.contains { $0.id == id } ? id : nil } ?? list[0].id
        }

        /// A fresh install: Port Townsend Bay as the only row, selected.
        public static let `default` = Preferences(locations: [.portTownsendBay])

        /// The pre-list preference (builds ≤ 7): Port Townsend Bay first, then the custom spot.
        public static func legacy(custom: SavedLocation?, useCustom: Bool) -> Preferences {
            guard let custom else { return .default }
            let list = custom.isDefaultPoint ? [custom] : [.portTownsendBay, custom]
            return Preferences(locations: list, selectedID: useCustom ? custom.id : list[0].id)
        }

        public var selected: SavedLocation { locations.first { $0.id == selectedID } ?? locations[0] }
        public var isFull: Bool { locations.count >= LocationSettings.maxCount }
        public var canDelete: Bool { locations.count > 1 }

        /// The selected point is not the baked default, so it is fetched with `?lat&lon`.
        public var effectiveUseCustom: Bool { !selected.isDefaultPoint }
        public var activeCustom: CustomLocation? { effectiveUseCustom ? selected.customLocation : nil }

        // MARK: Edits (callers persist and sync)

        public mutating func select(_ id: UUID) {
            if locations.contains(where: { $0.id == id }) { selectedID = id }
        }

        /// Appends and selects; false when the list is full.
        @discardableResult
        public mutating func add(_ location: SavedLocation) -> Bool {
            guard !isFull else { return false }
            locations.append(location)
            selectedID = location.id
            return true
        }

        /// Deletes a row unless it is the last one. Deleting the selected row selects row 1 (the fallback).
        @discardableResult
        public mutating func delete(_ id: UUID) -> Bool {
            guard canDelete, let i = locations.firstIndex(where: { $0.id == id }) else { return false }
            locations.remove(at: i)
            if selectedID == id { selectedID = locations[0].id }
            return true
        }

        public mutating func rename(_ id: UUID, to name: String) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let i = locations.firstIndex(where: { $0.id == id }) else { return }
            locations[i].name = String(trimmed.prefix(40))
        }

        public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
            var list = locations
            let moving = source.sorted().map { list[$0] }
            for i in source.sorted(by: >) { list.remove(at: i) }
            let before = source.filter { $0 < destination }.count
            list.insert(contentsOf: moving, at: max(0, min(destination - before, list.count)))
            locations = list
        }

        /// The legacy pair an older watch app understands: the selected spot when it isn't the
        /// default point, else the first row that isn't.
        var legacyCustom: SavedLocation? {
            effectiveUseCustom ? selected : locations.first { !$0.isDefaultPoint }
        }
    }

    public static func load(from defaults: UserDefaults) -> Preferences {
        if let data = defaults.data(forKey: locationsKey),
           let list = try? JSONDecoder().decode([SavedLocation].self, from: data), !list.isEmpty {
            let id = defaults.string(forKey: selectedKey).flatMap(UUID.init(uuidString:))
            return Preferences(locations: list, selectedID: id)
        }
        let custom = defaults.data(forKey: customLocationKey).flatMap { try? JSONDecoder().decode(SavedLocation.self, from: $0) }
        return .legacy(custom: custom, useCustom: defaults.bool(forKey: useCustomKey))
    }

    public static func save(_ prefs: Preferences, to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(prefs.locations) {
            defaults.set(data, forKey: locationsKey)
        }
        defaults.set(prefs.selectedID.uuidString, forKey: selectedKey)
        if let custom = prefs.legacyCustom, let data = try? JSONEncoder().encode(custom) {
            defaults.set(data, forKey: customLocationKey)
        } else {
            defaults.removeObject(forKey: customLocationKey)
        }
        defaults.set(prefs.effectiveUseCustom, forKey: useCustomKey)
    }

    /// Plist-safe dictionary for `WCSession.updateApplicationContext`: the list, the selection,
    /// and the legacy pair for watch apps from builds ≤ 7.
    public static func applicationContext(_ prefs: Preferences) -> [String: Any] {
        var ctx: [String: Any] = [useCustomKey: prefs.effectiveUseCustom, selectedKey: prefs.selectedID.uuidString]
        if let data = try? JSONEncoder().encode(prefs.locations) { ctx[locationsKey] = data }
        if let custom = prefs.legacyCustom, let data = try? JSONEncoder().encode(custom) {
            ctx[customLocationKey] = data
        }
        return ctx
    }

    /// Reads a context from this build or from a phone on builds ≤ 7 (legacy keys only).
    public static func preferences(fromApplicationContext ctx: [String: Any]) -> Preferences {
        if let data = ctx[locationsKey] as? Data,
           let list = try? JSONDecoder().decode([SavedLocation].self, from: data), !list.isEmpty {
            let id = (ctx[selectedKey] as? String).flatMap(UUID.init(uuidString:))
            return Preferences(locations: list, selectedID: id)
        }
        let custom = (ctx[customLocationKey] as? Data).flatMap { try? JSONDecoder().decode(SavedLocation.self, from: $0) }
        return .legacy(custom: custom, useCustom: ctx[useCustomKey] as? Bool ?? false)
    }
}
