import Foundation
import Testing
@testable import WindCore

@Suite("SavedLocation and LocationSettings")
struct SavedLocationTests {
    typealias Preferences = LocationSettings.Preferences

    func loc(_ name: String, _ lat: Double = 47.6, _ lon: Double = -122.3) -> SavedLocation {
        SavedLocation(name: name, lat: lat, lon: lon, tz: "America/Los_Angeles")
    }

    @Test func roundTripsThroughJSON() throws {
        let loc = SavedLocation(name: "Seattle", lat: 47.6062, lon: -122.3321, tz: "America/Los_Angeles",
                                suggestedNames: ["Elliott Bay", "Seattle"], createdAt: Date(timeIntervalSince1970: 1_000))
        let data = try JSONEncoder().encode(loc)
        #expect(try JSONDecoder().decode(SavedLocation.self, from: data) == loc)
        #expect(loc.customLocation == CustomLocation(lat: 47.6062, lon: -122.3321))
        #expect(loc.timeZone.identifier == "America/Los_Angeles")
    }

    @Test func decodesThePreListShape() throws {
        let old = Data(#"{"name":"Seattle","lat":47.6,"lon":-122.3,"tz":"America/Los_Angeles"}"#.utf8)
        let loc = try JSONDecoder().decode(SavedLocation.self, from: old)
        #expect(loc.name == "Seattle" && loc.lat == 47.6 && loc.lon == -122.3)
        #expect(loc.suggestedNames.isEmpty)
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

    @Test func serverDefaultIsByCoordinatesNotName() {
        var ptb = SavedLocation.portTownsendBay
        #expect(ptb.isServerDefault)
        ptb.name = "Home water"
        #expect(ptb.isServerDefault) // renaming keeps the KV fetch
        #expect(!loc("Port Townsend Bay", 48.1, -122.78).isServerDefault)
        var prefs = Preferences.default
        #expect(prefs.activeCustom == nil)
        do { let r = prefs.rename(ptb.id, to: "Home water"); #expect(r) }
        #expect(prefs.activeCustom == nil && prefs.selectedIsServerDefault)
    }

    // MARK: List rules

    @Test func defaultIsPortTownsendBaySelected() {
        let p = Preferences.default
        #expect(p.locations == [.portTownsendBay])
        #expect(p.selected == .portTownsendBay)
        #expect(!p.canDelete && !p.isFull && !p.hasNonDefault)
    }

    @Test func addsUpToTwelveThenRefuses() {
        var p = Preferences.default
        for i in 1..<12 { let r = p.add(loc("Spot \(i)", 47 + Double(i) / 100)); #expect(r) }
        #expect(p.count == 12 && p.isFull)
        #expect(p.selected.name == "Spot 11") // a new pin is selected
        do { let r = p.add(loc("Thirteen")); #expect(!r) }
        #expect(p.count == 12)
        // Same id twice is refused too.
        var q = Preferences.default
        do { let r = q.add(.portTownsendBay); #expect(!r) }
    }

    @Test func addNormalisesTheName() {
        var p = Preferences.default
        do { let r = p.add(loc("  Mystery   Bay \n")); #expect(r) }
        #expect(p.selected.name == "Mystery Bay")
    }

    @Test func initClampsAndRepairs() {
        let many = (0..<15).map { loc("S\($0)") }
        let p = Preferences(locations: many, selectedID: many[14].id)
        #expect(p.count == 12)
        #expect(p.selectedID == many[0].id) // selected row was dropped → first
        #expect(Preferences(locations: []).locations == [.portTownsendBay])
    }

    @Test func lastLocationCannotBeDeleted() {
        var p = Preferences.default
        do { let r = p.delete(SavedLocation.portTownsendBay.id); #expect(!r) }
        let a = loc("A")
        p.add(a)
        do { let r = p.delete(SavedLocation.portTownsendBay.id); #expect(r) } // the seeded default is ordinary
        #expect(p.locations == [p.location(id: a.id)!])
        do { let r = p.delete(a.id); #expect(!r) }
        do { let r = p.delete(UUID()); #expect(!r) }
    }

    @Test func deletingTheSelectedRowSelectsItsNeighbour() {
        let a = loc("A"), b = loc("B"), c = loc("C")
        var p = Preferences(locations: [a, b, c], selectedID: b.id)
        do { let r = p.delete(b.id); #expect(r) }
        #expect(p.selectedID == c.id) // the row that slid into place
        do { let r = p.delete(c.id); #expect(r) }
        #expect(p.selectedID == a.id) // was last → new last
        var q = Preferences(locations: [a, b, c], selectedID: a.id)
        do { let r = q.delete(c.id); #expect(r) }
        #expect(q.selectedID == a.id) // unselected delete keeps the selection
    }

    @Test func reorderFollowsListOnMove() {
        let a = loc("A"), b = loc("B"), c = loc("C"), d = loc("D")
        var p = Preferences(locations: [a, b, c, d], selectedID: c.id)
        p.move(fromOffsets: [0], toOffset: 3)
        #expect(p.locations.map(\.name) == ["B", "C", "A", "D"])
        p.move(fromOffsets: [3], toOffset: 0)
        #expect(p.locations.map(\.name) == ["D", "B", "C", "A"])
        p.move(fromOffsets: [1, 3], toOffset: 4)
        #expect(p.locations.map(\.name) == ["D", "C", "B", "A"])
        p.move(fromOffsets: [0], toOffset: 1) // no-op
        #expect(p.locations.map(\.name) == ["D", "C", "B", "A"])
        #expect(p.selectedID == c.id) // order means nothing to the selection
    }

    @Test func selectAndRename() {
        let a = loc("A", 48.1, -122.68)
        var p = Preferences(locations: [.portTownsendBay, a])
        do { let r = p.select(a.id); #expect(r) }
        do { let r = p.select(a.id); #expect(!r) } // already selected
        do { let r = p.select(UUID()); #expect(!r) }
        do { let r = p.rename(a.id, to: "  Marrowstone   Pt "); #expect(r) }
        #expect(p.selected.name == "Marrowstone Pt")
        #expect(p.selected.lat == 48.1 && p.selected.lon == -122.68) // the pin never moves
        do { let r = p.rename(a.id, to: "   "); #expect(!r) }
        do { let r = p.rename(a.id, to: String(repeating: "x", count: 41)); #expect(!r) }
        #expect(p.selected.name == "Marrowstone Pt")
    }

    // MARK: Names

    @Test func nameNormalisationAndValidation() {
        #expect(LocationName.normalize("  Point \t  Wilson\n") == "Point Wilson")
        #expect(LocationName.normalize("Admiralty Inlet mid") == "Admiralty Inlet mid")
        #expect(!LocationName.isValid(""))
        #expect(!LocationName.isValid("   \n"))
        #expect(LocationName.isValid("A"))
        #expect(LocationName.isValid(String(repeating: "x", count: 40)))
        #expect(!LocationName.isValid(String(repeating: "x", count: 41)))
        #expect(LocationName.isValid(" " + String(repeating: "x", count: 40) + "  ")) // trimmed first
        #expect(LocationName.clamp(String(repeating: "y", count: 45)).count == 40)
        #expect(LocationName.clamp("short") == "short")
        #expect(LocationName.normalize("Café · Ünïcode") == "Café · Ünïcode") // verbatim otherwise
    }

    @Test func duplicateGetsANumberSuggestedNotBlocked() {
        let names = ["Mystery Bay", "Oak Bay", "Oak Bay 2"]
        #expect(LocationName.duplicateSuggestion(for: "Point Wilson", existing: names) == nil)
        #expect(LocationName.duplicateSuggestion(for: "mystery  bay ", existing: names) == "mystery bay 2")
        #expect(LocationName.duplicateSuggestion(for: "Oak Bay", existing: names) == "Oak Bay 3")
        #expect(LocationName.duplicateSuggestion(for: "", existing: names) == nil)
        let long = String(repeating: "z", count: 40)
        let s = LocationName.duplicateSuggestion(for: long, existing: [long])
        #expect(s?.count == 40 && s?.hasSuffix(" 2") == true)
        // Not a block: the list takes the duplicate as typed.
        var p = Preferences.default
        do { let r = p.add(loc("Port Townsend Bay")); #expect(r) }
    }

    // MARK: Geocoder field order

    @Test func geocoderOrderAreasOfInterestFirst() {
        let g = GeocodedNames(areasOfInterest: ["Fort Flagler Historical State Park"], inlandWater: "Kilisut Harbor",
                              ocean: nil, locality: "Nordland", subLocality: nil, administrativeArea: "WA")
        #expect(g.suggestion == "Fort Flagler Historical State Park")
        #expect(g.chips == ["Kilisut Harbor", "Nordland", "WA"])
    }

    @Test func geocoderFallsThroughEmptyFieldsInOrder() {
        #expect(GeocodedNames(inlandWater: "Port Townsend Bay", locality: "Port Townsend").suggestion == "Port Townsend Bay")
        #expect(GeocodedNames(ocean: "Pacific Ocean", locality: "Neah Bay").suggestion == "Pacific Ocean")
        #expect(GeocodedNames(inlandWater: "Lake Union", ocean: "Pacific Ocean").chips == ["Pacific Ocean"])
        #expect(GeocodedNames(areasOfInterest: ["  "], locality: "Nordland", subLocality: "Marrowstone").suggestion == "Nordland")
        #expect(GeocodedNames(subLocality: "Marrowstone", administrativeArea: "Washington").suggestion == "Marrowstone")
        #expect(GeocodedNames(administrativeArea: "Washington").suggestion == "Washington")
        #expect(GeocodedNames().suggestion == nil)
        #expect(GeocodedNames().chips.isEmpty)
    }

    @Test func geocoderDeduplicatesAndCapsChipsAtFour() {
        let g = GeocodedNames(areasOfInterest: ["Marrowstone Island", "Fort Flagler", "marrowstone island"],
                              inlandWater: "Kilisut Harbor", ocean: "Salish Sea", locality: "Nordland",
                              subLocality: "Nordland", administrativeArea: "Washington")
        #expect(g.suggestion == "Marrowstone Island")
        #expect(g.chips == ["Fort Flagler", "Kilisut Harbor", "Salish Sea", "Nordland"])
    }

    // MARK: Storage and migration

    func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "WindCoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func defaultsRoundTrip() throws {
        try withDefaults { defaults in
            #expect(LocationSettings.load(from: defaults) == .default)
            let p = LocationSettings.fixture(count: 5)
            LocationSettings.save(p, to: defaults)
            #expect(LocationSettings.load(from: defaults) == p)
            #expect(p.selected.name == "Marrowstone Pt" && p.count == 5)
        }
    }

    @Test func migratesDefaultOnly() throws {
        #expect(LocationSettings.migrate(custom: nil, useCustom: false) == .default)
        #expect(LocationSettings.migrate(custom: nil, useCustom: true) == .default) // orphan flag
        try withDefaults { defaults in
            defaults.set(false, forKey: LocationSettings.legacyUseCustomKey)
            #expect(LocationSettings.load(from: defaults) == .default)
            #expect(defaults.object(forKey: LocationSettings.legacyUseCustomKey) == nil) // rewritten
            #expect(defaults.data(forKey: LocationSettings.locationsKey) != nil)
        }
    }

    @Test func migratesACustomLocationKeepingTheSelection() throws {
        let old = Data(#"{"name":"Seattle","lat":47.6,"lon":-122.3,"tz":"America/Los_Angeles"}"#.utf8)
        for useCustom in [true, false] {
            try withDefaults { defaults in
                defaults.set(old, forKey: LocationSettings.legacyCustomLocationKey)
                defaults.set(useCustom, forKey: LocationSettings.legacyUseCustomKey)
                let p = LocationSettings.load(from: defaults)
                #expect(p.locations.map(\.name) == ["Port Townsend Bay", "Seattle"])
                #expect(p.locations[1].lat == 47.6 && p.locations[1].lon == -122.3)
                #expect(p.selected.name == (useCustom ? "Seattle" : "Port Townsend Bay"))
                #expect(p.activeCustom == (useCustom ? CustomLocation(lat: 47.6, lon: -122.3) : nil))
                // Rewritten once: the legacy keys are gone and a second load is stable (same ids).
                #expect(defaults.data(forKey: LocationSettings.legacyCustomLocationKey) == nil)
                #expect(LocationSettings.load(from: defaults) == p)
            }
        }
    }

    @Test func applicationContextRoundTrip() {
        let p = LocationSettings.fixture(count: 12)
        let ctx = LocationSettings.applicationContext(p)
        #expect(ctx.count == 1 && ctx[LocationSettings.locationsKey] is Data) // plist-safe
        let back = LocationSettings.preferences(fromApplicationContext: ctx)
        #expect(back == p)
        #expect(back.locations.map(\.id) == p.locations.map(\.id)) // same order, same ids
        #expect(back.selectedID == p.selectedID)
        #expect(LocationSettings.preferences(fromApplicationContext: [:]) == .default)
        #expect(LocationSettings.preferences(fromApplicationContext: [LocationSettings.locationsKey: Data("junk".utf8)]) == .default)
    }

    @Test func applicationContextFromAPreListPhone() throws {
        let custom = loc("Seattle")
        let ctx: [String: Any] = [LocationSettings.legacyCustomLocationKey: try JSONEncoder().encode(custom),
                                  LocationSettings.legacyUseCustomKey: true]
        let p = LocationSettings.preferences(fromApplicationContext: ctx)
        #expect(p.locations.map(\.name) == ["Port Townsend Bay", "Seattle"])
        #expect(p.selected.name == "Seattle")
    }
}
