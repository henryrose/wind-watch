import Foundation

/// One row of the location list (HANDOFF §8.3, location-naming §1), stored on device and synced
/// phone → watch. `name` is the user's: stored verbatim (after `LocationName.normalize`), never
/// re-geocoded, and renaming never touches `lat`/`lon`. The HRRR cell the forecast comes from is
/// derived from the pin (`HRRRCoverage.cell`), so it can never drift from it.
public struct SavedLocation: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// What the geocoder offered at pin time, best first; feeds the sheet's chips. Never shown as
    /// the title and never refreshed.
    public var suggestedNames: [String]
    /// The pin, as placed.
    public var lat: Double
    public var lon: Double
    /// IANA identifier, informational; the payload's `loc.tz` drives display.
    public var tz: String
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, lat: Double, lon: Double, tz: String,
                suggestedNames: [String] = [], createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.suggestedNames = suggestedNames
        self.lat = lat
        self.lon = lon
        self.tz = tz
        self.createdAt = createdAt
    }

    /// Decodes the current shape and the pre-list one (`name, lat, lon, tz` only, D5).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        suggestedNames = try c.decodeIfPresent([String].self, forKey: .suggestedNames) ?? []
        lat = try c.decode(Double.self, forKey: .lat)
        lon = try c.decode(Double.self, forKey: .lon)
        tz = try c.decodeIfPresent(String.self, forKey: .tz) ?? TimeZone.current.identifier
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
    }

    /// The server's baked default (DESIGN §0): Port Townsend Bay, the `cell_selection=sea` point.
    /// Seeded as row 1 on first install with a fixed id so phone and watch agree before any sync.
    public static let portTownsendBay = SavedLocation(
        id: UUID(uuidString: "00000000-0000-4000-8000-0000000000B1")!,
        name: "Port Townsend Bay", lat: 48.0907, lon: -122.7773, tz: "America/Los_Angeles",
        createdAt: Date(timeIntervalSince1970: 0))

    /// True for the pin at the server default's coordinates, whatever it is called: that one is
    /// fetched from `/v1/wind` (the KV bake), every other location with `?lat&lon`.
    public var isServerDefault: Bool {
        abs(lat - Self.portTownsendBay.lat) < 1e-6 && abs(lon - Self.portTownsendBay.lon) < 1e-6
    }

    public var customLocation: CustomLocation { CustomLocation(lat: lat, lon: lon) }
    public var timeZone: TimeZone { TimeZone(identifier: tz) ?? .current }

    /// `48.091, −122.777` (three decimals, true minus sign).
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

/// Name rules (location-naming §1): trimmed, internal whitespace collapsed to one space, 1–40
/// characters. Duplicates are allowed; the sheet only suggests a ` 2` suffix.
public enum LocationName {
    public static let maxLength = 40
    /// Shown in the empty field when the geocoder gave nothing (or timed out).
    public static let placeholder = "Name this spot"

    public static func normalize(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static func isValid(_ raw: String) -> Bool {
        let n = normalize(raw)
        return !n.isEmpty && n.count <= maxLength
    }

    /// Typing past 40 characters is blocked: the field keeps the first 40.
    public static func clamp(_ raw: String) -> String {
        raw.count > maxLength ? String(raw.prefix(maxLength)) : raw
    }

    /// `"Mystery Bay 2"` (or the first free number) when `raw` matches a name in `existing`
    /// (case-insensitive, after normalising); nil when it is unique or empty.
    public static func duplicateSuggestion(for raw: String, existing: [String]) -> String? {
        let name = normalize(raw)
        guard !name.isEmpty else { return nil }
        let taken = Set(existing.map { normalize($0).lowercased() })
        guard taken.contains(name.lowercased()) else { return nil }
        var n = 2
        while true {
            let suffix = " \(n)"
            let candidate = String(name.prefix(maxLength - suffix.count)) + suffix
            if !taken.contains(candidate.lowercased()) { return candidate }
            n += 1
        }
    }
}

/// The reverse-geocoder's fields, platform-neutral (`CLPlacemark` on iOS 18–25, `MKMapItem` on
/// iOS 26+), and the suggestion rule (location-naming §6): the first non-empty of
/// areasOfInterest → inlandWater / ocean → locality → subLocality → administrativeArea is the
/// suggestion; the rest, deduplicated, are the chips (at most 4).
public struct GeocodedNames: Sendable, Equatable {
    public var areasOfInterest: [String]
    public var inlandWater: String?
    public var ocean: String?
    public var locality: String?
    public var subLocality: String?
    public var administrativeArea: String?

    public init(areasOfInterest: [String] = [], inlandWater: String? = nil, ocean: String? = nil,
                locality: String? = nil, subLocality: String? = nil, administrativeArea: String? = nil) {
        self.areasOfInterest = areasOfInterest
        self.inlandWater = inlandWater
        self.ocean = ocean
        self.locality = locality
        self.subLocality = subLocality
        self.administrativeArea = administrativeArea
    }

    public static let maxChips = 4

    /// Every name in priority order, normalised and clamped, empties and repeats (case-insensitive)
    /// dropped.
    public var ordered: [String] {
        let raw = areasOfInterest + [inlandWater, ocean, locality, subLocality, administrativeArea].compactMap { $0 }
        var seen = Set<String>()
        var out: [String] = []
        for name in raw.map({ LocationName.clamp(LocationName.normalize($0)) }) where !name.isEmpty {
            if seen.insert(name.lowercased()).inserted { out.append(name) }
        }
        return out
    }

    /// The pre-filled name; nil when the geocoder found nothing.
    public var suggestion: String? { ordered.first }

    /// The other nearby names for the chips.
    public var chips: [String] { Array(ordered.dropFirst().prefix(Self.maxChips)) }
}

/// Reads and writes the location list in the shared (App Group) `UserDefaults`, migrates the
/// pre-list preference, and encodes the list for `WCSession` application context.
public enum LocationSettings {
    /// JSON `Preferences` (`{"locations":[…],"selectedID":"…"}`).
    public static let locationsKey = "locations"
    /// Pre-list keys (one custom location + a flag), read once for migration and then removed.
    public static let legacyCustomLocationKey = "customLocation"
    public static let legacyUseCustomKey = "useCustom"

    /// The list and which row is selected. Always non-empty, at most `maxCount`, and `selectedID`
    /// always names a row; every mutation keeps that true. Order is the user's and means nothing
    /// else: the selected row drives every surface.
    public struct Preferences: Codable, Sendable, Equatable {
        public static let maxCount = 12

        public private(set) var locations: [SavedLocation]
        public private(set) var selectedID: UUID

        public init(locations: [SavedLocation], selectedID: UUID? = nil) {
            var list = Array(locations.prefix(Self.maxCount))
            if list.isEmpty { list = [SavedLocation.portTownsendBay] }
            self.locations = list
            self.selectedID = selectedID.flatMap { id in list.contains { $0.id == id } ? id : nil } ?? list[0].id
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(locations: try c.decode([SavedLocation].self, forKey: .locations),
                      selectedID: try c.decodeIfPresent(UUID.self, forKey: .selectedID))
        }

        /// Fresh install: Port Townsend Bay, selected.
        public static let `default` = Preferences(locations: [.portTownsendBay])

        public var selected: SavedLocation { locations.first { $0.id == selectedID } ?? locations[0] }
        public var count: Int { locations.count }
        public var isFull: Bool { locations.count >= Self.maxCount }

        /// The server-default row is selected (fetch `/v1/wind` with no query).
        public var selectedIsServerDefault: Bool { selected.isServerDefault }
        /// The point to fetch with `?lat&lon`, nil for the server default.
        public var activeCustom: CustomLocation? { selectedIsServerDefault ? nil : selected.customLocation }
        /// Anything beyond the seeded default (Welcome treats this as "already chosen").
        public var hasNonDefault: Bool { locations.contains { !$0.isServerDefault } }

        /// The last remaining location cannot be deleted.
        public var canDelete: Bool { locations.count > 1 }

        public func location(id: UUID) -> SavedLocation? { locations.first { $0.id == id } }

        @discardableResult
        public mutating func select(_ id: UUID) -> Bool {
            guard id != selectedID, location(id: id) != nil else { return false }
            selectedID = id
            return true
        }

        /// Appends (and by default selects) a location; false when the list is full.
        @discardableResult
        public mutating func add(_ location: SavedLocation, select: Bool = true) -> Bool {
            guard !isFull, self.location(id: location.id) == nil else { return false }
            var stored = location
            stored.name = LocationName.normalize(location.name)
            locations.append(stored)
            if select { selectedID = stored.id }
            return true
        }

        /// Removes a row. Deleting the selected one selects the row that slides into its place
        /// (or the new last row). False for the last remaining location or an unknown id.
        @discardableResult
        public mutating func delete(_ id: UUID) -> Bool {
            guard canDelete, let index = locations.firstIndex(where: { $0.id == id }) else { return false }
            locations.remove(at: index)
            if id == selectedID { selectedID = locations[min(index, locations.count - 1)].id }
            return true
        }

        /// `List.onMove` semantics: `destination` is an index in the list before the move.
        public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
            let indices = source.sorted().filter { locations.indices.contains($0) }
            guard !indices.isEmpty else { return }
            let moving = indices.map { locations[$0] }
            let before = indices.filter { $0 < destination }.count
            for index in indices.reversed() { locations.remove(at: index) }
            locations.insert(contentsOf: moving, at: max(0, min(destination - before, locations.count)))
        }

        /// Stores the normalised name; never touches the pin. False when the name is invalid.
        @discardableResult
        public mutating func rename(_ id: UUID, to raw: String) -> Bool {
            guard LocationName.isValid(raw), let index = locations.firstIndex(where: { $0.id == id }) else { return false }
            locations[index].name = LocationName.normalize(raw)
            return true
        }
    }

    /// The pre-list preference → the list: `[Port Townsend Bay]`, plus the custom location when
    /// one was saved, with the previous selection kept (custom only when `useCustom` was on).
    public static func migrate(custom: SavedLocation?, useCustom: Bool) -> Preferences {
        guard let custom else { return .default }
        let selected = useCustom ? custom.id : SavedLocation.portTownsendBay.id
        return Preferences(locations: [.portTownsendBay, custom], selectedID: selected)
    }

    /// The stored list; migrates (and rewrites) the pre-list keys on first read; `.default` when
    /// nothing is stored.
    public static func load(from defaults: UserDefaults) -> Preferences {
        if let data = defaults.data(forKey: locationsKey), let prefs = try? JSONDecoder().decode(Preferences.self, from: data) {
            return prefs
        }
        let legacyCustom = defaults.data(forKey: legacyCustomLocationKey).flatMap { try? JSONDecoder().decode(SavedLocation.self, from: $0) }
        guard legacyCustom != nil || defaults.object(forKey: legacyUseCustomKey) != nil else { return .default }
        let migrated = migrate(custom: legacyCustom, useCustom: defaults.bool(forKey: legacyUseCustomKey))
        save(migrated, to: defaults)
        return migrated
    }

    /// Writes the list and drops the pre-list keys.
    public static func save(_ prefs: Preferences, to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: locationsKey)
        }
        defaults.removeObject(forKey: legacyCustomLocationKey)
        defaults.removeObject(forKey: legacyUseCustomKey)
    }

    /// Plist-safe dictionary for `WCSession.updateApplicationContext`: the whole list as JSON.
    public static func applicationContext(_ prefs: Preferences) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(prefs) else { return [:] }
        return [locationsKey: data]
    }

    /// Decodes a context from this build or from a pre-list iPhone build (migrated on the fly).
    public static func preferences(fromApplicationContext ctx: [String: Any]) -> Preferences {
        if let data = ctx[locationsKey] as? Data, let prefs = try? JSONDecoder().decode(Preferences.self, from: data) {
            return prefs
        }
        let custom = (ctx[legacyCustomLocationKey] as? Data).flatMap { try? JSONDecoder().decode(SavedLocation.self, from: $0) }
        return migrate(custom: custom, useCustom: ctx[legacyUseCustomKey] as? Bool ?? false)
    }

    /// `WW_LOCATIONS=<n>`: the design's sample list (`Phone-Location*.dc.html`), Port Townsend
    /// Bay first and Marrowstone Pt selected. Screenshots and tests only.
    public static func fixture(count: Int) -> Preferences {
        let samples: [(String, Double, Double)] = [
            ("Marrowstone Pt", 48.100, -122.683), ("Point Wilson", 48.144, -122.755),
            ("Mystery Bay", 48.059, -122.693), ("Kilisut Harbor", 48.071, -122.705),
            ("Admiralty Inlet mid", 48.140, -122.660), ("Port Ludlow", 47.924, -122.684),
            ("Fort Flagler", 48.093, -122.712), ("Discovery Bay", 48.040, -122.860),
            ("Protection Island", 48.128, -122.926), ("Mats Mats Bay", 47.958, -122.680),
            ("Oak Bay", 47.996, -122.699),
        ]
        let rows = samples.prefix(max(0, min(count, Preferences.maxCount) - 1)).enumerated().map { i, s in
            SavedLocation(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", i + 1))!,
                          name: s.0, lat: s.1, lon: s.2, tz: "America/Los_Angeles",
                          suggestedNames: i == 0 ? ["Marrowstone Island", "Nordland", "Kilisut Harbor"] : [],
                          createdAt: Date(timeIntervalSince1970: 0))
        }
        return Preferences(locations: [.portTownsendBay] + rows, selectedID: rows.first?.id)
    }
}
