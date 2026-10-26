import Foundation
import Testing
@testable import WindCore

@Suite("SavedLocation and LocationSettings")
struct SavedLocationTests {
    @Test func roundTripsThroughJSON() throws {
        let loc = SavedLocation(name: "Seattle", lat: 47.6062, lon: -122.3321, tz: "America/Los_Angeles")
        let data = try JSONEncoder().encode(loc)
        #expect(try JSONDecoder().decode(SavedLocation.self, from: data) == loc)
        #expect(loc.customLocation == CustomLocation(lat: 47.6062, lon: -122.3321))
        #expect(loc.timeZone.identifier == "America/Los_Angeles")
    }

    @Test func coordinateText() {
        #expect(SavedLocation.portTownsendBay.coordinateText == "48.091, \u{2212}122.777")
        #expect(SavedLocation.coordinateText(lat: -33.8688, lon: 151.2093) == "\u{2212}33.869, 151.209")
    }

    @Test func parsesPastedCoordinates() {
        #expect(SavedLocation.parseCoordinates("48.1, -122.75")! == (48.1, -122.75))
        #expect(SavedLocation.parseCoordinates(" 48.1 ,\u{2212}122.75 ")! == (48.1, -122.75))
        #expect(SavedLocation.parseCoordinates("Port Townsend") == nil)
        #expect(SavedLocation.parseCoordinates("91, 0") == nil)
        #expect(SavedLocation.parseCoordinates("1, 2, 3") == nil)
    }

    let seattle = SavedLocation(name: "Seattle", lat: 47.6, lon: -122.3, tz: "America/Los_Angeles")

    @Test func freshInstallSeedsPortTownsendBayOnly() throws {
        let suite = "WindCoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = LocationSettings.load(from: defaults)
        #expect(prefs == .default)
        #expect(prefs.locations == [.portTownsendBay])
        #expect(prefs.selected == .portTownsendBay)
        #expect(!prefs.effectiveUseCustom && prefs.activeCustom == nil)
        #expect(!prefs.canDelete)
    }

    @Test func defaultsRoundTrip() throws {
        let suite = "WindCoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(locations: [.portTownsendBay, seattle], selectedID: seattle.id)
        LocationSettings.save(prefs, to: defaults)
        let loaded = LocationSettings.load(from: defaults)
        #expect(loaded == prefs)
        #expect(loaded.effectiveUseCustom)
        #expect(loaded.activeCustom == seattle.customLocation)
        // The legacy pair is written too, for a watch app on build ≤ 7.
        #expect(defaults.bool(forKey: LocationSettings.useCustomKey))
        #expect(defaults.data(forKey: LocationSettings.customLocationKey) != nil)
    }

    @Test func migratesTheBuild7Preference() throws {
        let suite = "WindCoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Build ≤ 7 stored a SavedLocation without an id plus useCustom.
        let old = #"{"name":"Seattle","lat":47.6,"lon":-122.3,"tz":"America/Los_Angeles"}"#.data(using: .utf8)!
        defaults.set(old, forKey: LocationSettings.customLocationKey)
        defaults.set(true, forKey: LocationSettings.useCustomKey)
        let migrated = LocationSettings.load(from: defaults)
        #expect(migrated.locations.map(\.name) == ["Port Townsend Bay", "Seattle"])
        #expect(migrated.selected.name == "Seattle")
        #expect(migrated.activeCustom == CustomLocation(lat: 47.6, lon: -122.3))
        defaults.set(false, forKey: LocationSettings.useCustomKey)
        #expect(LocationSettings.load(from: defaults).selected == .portTownsendBay)
    }

    @Test func listRules() {
        var p = Preferences.default
        let deletedLast = p.delete(SavedLocation.portTownsendBay.id)
        #expect(!deletedLast) // last row
        for i in 0..<11 {
            let added = p.add(SavedLocation(name: "P\(i)", lat: 47, lon: -122 + Double(i) / 10, tz: "UTC"))
            #expect(added)
        }
        #expect(p.isFull && p.locations.count == 12)
        let addedThirteenth = p.add(seattle)
        #expect(!addedThirteenth)
        #expect(p.selected.name == "P10") // add selects
        p.move(fromOffsets: IndexSet(integer: 0), toOffset: 12)
        #expect(p.locations.last == .portTownsendBay)
        #expect(p.locations.first?.name == "P0")
        p.rename(SavedLocation.portTownsendBay.id, to: "  Home  ")
        #expect(p.locations.last?.name == "Home")
        #expect(p.locations.last?.isDefaultPoint == true)
        p.rename(SavedLocation.portTownsendBay.id, to: "   ")
        #expect(p.locations.last?.name == "Home") // blank names are ignored
        let selected = p.selectedID
        let deleted = p.delete(selected)
        #expect(deleted)
        #expect(p.selectedID == p.locations[0].id) // falls back to row 1
        // An unknown selection falls back to row 1 as well.
        #expect(Preferences(locations: [seattle, .portTownsendBay], selectedID: UUID()).selected == seattle)
    }

    @Test func applicationContextRoundTrip() {
        let prefs = Preferences(locations: [.portTownsendBay, seattle], selectedID: seattle.id)
        let ctx = LocationSettings.applicationContext(prefs)
        #expect(ctx[LocationSettings.locationsKey] is Data)
        #expect(ctx[LocationSettings.useCustomKey] as? Bool == true)
        #expect(ctx[LocationSettings.customLocationKey] is Data) // legacy pair for older watch apps
        #expect(LocationSettings.preferences(fromApplicationContext: ctx) == prefs)
        #expect(LocationSettings.preferences(fromApplicationContext: [:]) == .default)
        // A context from a phone on build ≤ 7 (legacy keys only).
        let legacyCtx: [String: Any] = [LocationSettings.useCustomKey: true,
                                        LocationSettings.customLocationKey: try! JSONEncoder().encode(seattle)]
        let fromOld = LocationSettings.preferences(fromApplicationContext: legacyCtx)
        #expect(fromOld.locations == [.portTownsendBay, seattle])
        #expect(fromOld.selected == seattle)
        // Plist-safe: only Bool, String and Data values.
        #expect(ctx.values.allSatisfy { $0 is Bool || $0 is Data || $0 is String })
    }

    typealias Preferences = LocationSettings.Preferences
}
