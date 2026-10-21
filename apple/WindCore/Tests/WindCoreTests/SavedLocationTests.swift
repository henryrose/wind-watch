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
        #expect(SavedLocation.portTownsendBay.coordinateText == "48.09, \u{2212}122.78")
        #expect(SavedLocation.coordinateText(lat: -33.8688, lon: 151.2093) == "\u{2212}33.87, 151.21")
    }

    @Test func parsesPastedCoordinates() {
        #expect(SavedLocation.parseCoordinates("48.1, -122.75")! == (48.1, -122.75))
        #expect(SavedLocation.parseCoordinates(" 48.1 ,\u{2212}122.75 ")! == (48.1, -122.75))
        #expect(SavedLocation.parseCoordinates("Port Townsend") == nil)
        #expect(SavedLocation.parseCoordinates("91, 0") == nil)
        #expect(SavedLocation.parseCoordinates("1, 2, 3") == nil)
    }

    @Test func defaultsRoundTrip() throws {
        let suite = "WindCoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(LocationSettings.load(from: defaults) == .default)
        let custom = SavedLocation(name: "Seattle", lat: 47.6, lon: -122.3, tz: "America/Los_Angeles")
        LocationSettings.save(Preferences(custom: custom, useCustom: true), to: defaults)
        let loaded = LocationSettings.load(from: defaults)
        #expect(loaded == Preferences(custom: custom, useCustom: true))
        #expect(loaded.effectiveUseCustom)
        #expect(loaded.activeCustom == custom.customLocation)

        LocationSettings.save(Preferences(custom: custom, useCustom: false), to: defaults)
        #expect(LocationSettings.load(from: defaults).activeCustom == nil)

        LocationSettings.save(Preferences(custom: nil, useCustom: true), to: defaults)
        let orphan = LocationSettings.load(from: defaults)
        #expect(orphan.custom == nil && orphan.useCustom && !orphan.effectiveUseCustom)
    }

    @Test func applicationContextRoundTrip() {
        let custom = SavedLocation(name: "Seattle", lat: 47.6, lon: -122.3, tz: "America/Los_Angeles")
        let prefs = Preferences(custom: custom, useCustom: true)
        let ctx = LocationSettings.applicationContext(prefs)
        #expect(ctx["useCustom"] as? Bool == true)
        #expect(ctx["customLocation"] is Data)
        #expect(LocationSettings.preferences(fromApplicationContext: ctx) == prefs)
        #expect(LocationSettings.preferences(fromApplicationContext: [:]) == .default)
    }

    typealias Preferences = LocationSettings.Preferences
}
