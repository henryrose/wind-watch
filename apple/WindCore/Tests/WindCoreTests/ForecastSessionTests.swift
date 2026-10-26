import Foundation
import Testing
@testable import WindCore

@Suite("ForecastSession (fixture and env handling)")
@MainActor
struct ForecastSessionTests {
    let info: [String: Any] = ["WWBundlePrefix": "com.example", "WWAPIBase": "https://example.test"]

    func session(_ state: String?, extra: [String: String] = [:]) -> ForecastSession {
        var env = ["WW_FIXTURE": "1"]
        if let state { env["WW_STATE"] = state }
        env.merge(extra) { _, new in new }
        return ForecastSession(bundleInfo: info, environment: env, mirrorFixtureToGroup: false)
    }

    @Test func fixtureStates() {
        let f = PreviewData.forecast
        #expect(session(nil).trustState == .fresh)
        #expect(session(nil).now == f.fetched.addingTimeInterval(1800))
        #expect(session(nil).hero == f.hours[0])
        #expect(session("stale").trustState == .stale)
        #expect(session("old").trustState == .old)
        #expect(session("old").ageTier == .old)
        #expect(session("old").hero == f.hours[7])
        #expect(session("offline").trustState == .offlineCached)
        #expect(session("horizon").trustState == .pastHorizon)
        #expect(session("horizon").hero == nil)
        #expect(session("firstrun").trustState == .firstRun)
        #expect(session("firstrun").forecast == nil)
        #expect(session("updating").trustState == .updating)
        #expect(session("updating").hero == f.hours[0])
    }

    @Test func welcomeOnlyOnTrueFirstLaunch() {
        #expect(Welcome.shouldShow(done: false, hasCustom: false, hasCache: false))
        #expect(!Welcome.shouldShow(done: true, hasCustom: false, hasCache: false))
        #expect(!Welcome.shouldShow(done: false, hasCustom: true, hasCache: false))
        #expect(!Welcome.shouldShow(done: false, hasCustom: false, hasCache: true))
    }

    @Test func welcomeInFixtureModeOnlyWhenForced() {
        #expect(!session("firstrun").needsWelcome)
        let s = session("firstrun", extra: ["WW_WELCOME": "1"])
        #expect(s.needsWelcome)
        s.completeWelcome()
        #expect(!s.needsWelcome)
    }

    @Test func fixtureClockIsFrozen() async {
        let s = session("stale")
        let before = s.now
        s.tick()
        #expect(s.now == before)
        #expect(await s.refreshIfNeeded(force: true) == false) // no client in fixture mode
        #expect(!s.canReachNetwork)
    }

    @Test func pinnedNow() {
        let s = session(nil, extra: ["WW_NOW": "2026-10-22T06:30:00Z"])
        #expect(s.now == Date(timeIntervalSince1970: 1_792_650_600))
        s.tick()
        #expect(s.now == Date(timeIntervalSince1970: 1_792_650_600))
        #expect(s.trustState == .old)
    }

    @Test func typeSizeOverride() {
        #expect(session(nil, extra: ["WW_TYPE_SIZE": "ax1"]).typeSizeOverride == .accessibility1)
        #expect(session(nil, extra: ["WW_TYPE_SIZE": "xxl"]).typeSizeOverride == .xxLarge)
        #expect(session(nil).typeSizeOverride == nil)
    }

    @Test func groupAndClientFromBundleInfo() {
        let s = ForecastSession(bundleInfo: info, environment: [:], mirrorFixtureToGroup: false)
        #expect(s.groupID == "group.com.example.windwatch")
        #expect(s.client?.baseURL.absoluteString == "https://example.test")
        #expect(!s.isFixture)
        let placeholder = ForecastSession(bundleInfo: ["WWAPIBase": "https:/REPLACE"], environment: [:], mirrorFixtureToGroup: false)
        #expect(placeholder.client == nil)
        #expect(placeholder.groupID == "group.com.example.windwatch")
    }

    @Test func fixtureFlag() throws {
        let suite = "WindCoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!FixtureFlag.isSet(in: defaults))
        FixtureFlag.set(true, in: defaults)
        #expect(FixtureFlag.isSet(in: defaults))
        FixtureFlag.set(false, in: defaults)
        #expect(!FixtureFlag.isSet(in: defaults))
    }

    @Test func locationSelectionInFixtureMode() {
        let s = session(nil)
        let custom = SavedLocation(name: "Seattle", lat: 47.6, lon: -122.3, tz: "America/Los_Angeles")
        defer {
            for key in [LocationSettings.locationsKey, LocationSettings.selectedKey, LocationSettings.customLocationKey, LocationSettings.useCustomKey] {
                s.defaults.removeObject(forKey: key)
            }
        }
        LocationSettings.save(.default, to: s.defaults)
        s.reloadPreferences()
        #expect(s.add(custom))
        #expect(s.preferences.effectiveUseCustom)
        #expect(s.locationName == "Seattle")
        #expect(s.forecast?.location.isDefault == false)
        #expect(s.forecast != nil) // fixture keeps the payload
        s.selectDefault()
        #expect(!s.preferences.effectiveUseCustom)
        #expect(s.locationName == "Port Townsend Bay")
        #expect(s.forecast?.location.isDefault == true)
        s.select(custom.id)
        #expect(s.preferences.effectiveUseCustom)
        // Renaming the default row changes the name everywhere, not the fetched point.
        s.rename(SavedLocation.portTownsendBay.id, to: "Home bay")
        s.selectDefault()
        #expect(s.locationName == "Home bay")
        #expect(s.preferences.activeCustom == nil)
    }
}

@Suite("ForecastSession preference sync (D5)")
@MainActor
struct ForecastSessionSyncTests {
    /// A session with its own defaults suite and (non-fixture) temp store, cleaned up after.
    @MainActor struct Harness {
        let session: ForecastSession
        let suite: String
        init(fixture: Bool, seeded: Bool = true) throws {
            let prefix = "test.\(UUID().uuidString.lowercased())"
            suite = AppGroupStore.groupID(bundlePrefix: prefix)
            let store = AppGroupStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("WindCoreSync-\(UUID().uuidString)", isDirectory: true))
            if seeded, !fixture { try store.save(payloadData: try PreviewData.payload.encoded(), etag: "\"e\"", at: .now) }
            session = ForecastSession(bundleInfo: ["WWBundlePrefix": prefix, "WWAPIBase": "https://example.test"],
                                      environment: fixture ? ["WW_FIXTURE": "1"] : [:],
                                      mirrorFixtureToGroup: false, store: store)
        }
        func cleanup() { session.defaults.removePersistentDomain(forName: suite); try? session.store.clear() }
    }

    let custom = SavedLocation(name: "Seattle", lat: 47.6, lon: -122.3, tz: "America/Los_Angeles")

    private func list(selecting selected: SavedLocation?) -> LocationSettings.Preferences {
        .init(locations: [.portTownsendBay, custom], selectedID: selected?.id)
    }

    @Test func reloadFlipsIsDefaultInFixtureMode() throws {
        let h = try Harness(fixture: true); defer { h.cleanup() }
        #expect(h.session.forecast?.location.isDefault == true)
        LocationSettings.save(list(selecting: custom), to: h.session.defaults)
        #expect(h.session.reloadPreferences() == true)
        #expect(h.session.preferences == list(selecting: custom))
        #expect(h.session.forecast != nil)
        #expect(h.session.forecast?.location.isDefault == false)
        #expect(h.session.locationName == "Seattle")
        #expect(h.session.reloadPreferences() == false) // nothing changed
    }

    @Test func reloadClearsCacheOnlyWhenActiveLocationChanges() throws {
        let h = try Harness(fixture: false); defer { h.cleanup() }
        #expect(h.session.forecast != nil)
        // A location added but not selected: preferences change, cache stays.
        LocationSettings.save(list(selecting: nil), to: h.session.defaults)
        #expect(h.session.reloadPreferences() == false)
        #expect(h.session.preferences.locations.count == 2)
        #expect(h.session.forecast != nil)
        #expect(h.session.store.load() != nil)
        // Now selected: active location changed → cache dropped.
        LocationSettings.save(list(selecting: custom), to: h.session.defaults)
        #expect(h.session.reloadPreferences() == true)
        #expect(h.session.store.load() == nil)
        #expect(h.session.forecast == nil)
        #expect(h.session.preferences.activeCustom == custom.customLocation)
    }

    @Test func localEditsFireTheHook() throws {
        let h = try Harness(fixture: true); defer { h.cleanup() }
        final class Box: @unchecked Sendable { var seen: [LocationSettings.Preferences] = [] }
        let box = Box()
        h.session.onPreferencesChanged = { prefs in box.seen.append(prefs) }
        h.session.add(custom)
        h.session.selectDefault()
        h.session.select(custom.id)
        h.session.select(custom.id) // no-op, already selected
        #expect(box.seen.map(\.effectiveUseCustom) == [true, false, true])
        #expect(box.seen.allSatisfy { $0.locations == [.portTownsendBay, custom] })
        #expect(LocationSettings.load(from: h.session.defaults) == list(selecting: custom))
    }

    @Test func deletingTheSelectedRowFallsBackToRowOneAndTheLastRowStays() throws {
        let h = try Harness(fixture: true); defer { h.cleanup() }
        h.session.add(custom)
        h.session.delete(custom.id)
        #expect(h.session.preferences.locations == [.portTownsendBay])
        #expect(h.session.preferences.selected == .portTownsendBay)
        h.session.delete(SavedLocation.portTownsendBay.id) // the last one
        #expect(h.session.preferences.locations == [.portTownsendBay])
        // Port Townsend Bay can go once something else is there; the other row becomes row 1.
        h.session.add(custom)
        h.session.delete(SavedLocation.portTownsendBay.id)
        #expect(h.session.preferences.locations == [custom])
        #expect(h.session.preferences.selected == custom)
    }

    @Test func tryAddRefusesAPointOutsideHRRRAndChangesNothing() async throws {
        let h = try Harness(fixture: false); defer { h.cleanup() }
        let london = SavedLocation(name: "London", lat: 51.5, lon: -0.12, tz: "Europe/London")
        let before = h.session.preferences
        #expect(await h.session.tryAdd(london) == .outsideCoverage)
        #expect(h.session.preferences == before)
        #expect(h.session.forecast != nil) // the cache is untouched
        #expect(h.session.store.load() != nil)
    }

    @Test func tryAddSavesInFixtureModeAndStopsAtTwelve() async throws {
        let h = try Harness(fixture: true); defer { h.cleanup() }
        #expect(await h.session.tryAdd(custom) == .saved)
        #expect(h.session.preferences == list(selecting: custom))
        for i in 0..<10 {
            #expect(await h.session.tryAdd(SavedLocation(name: "P\(i)", lat: 47 + Double(i) / 10, lon: -122, tz: "America/Los_Angeles")) == .saved)
        }
        #expect(h.session.preferences.locations.count == 12)
        #expect(h.session.preferences.isFull)
        #expect(await h.session.tryAdd(SavedLocation(name: "One more", lat: 45, lon: -122, tz: "America/Los_Angeles")) == .full)
        #expect(h.session.preferences.locations.count == 12)
    }

    @Test func payloadTimeZoneWinsOverSavedLocationTimeZone() throws {
        var p = PreviewData.payload
        p.loc.tz = "Europe/London"
        let f = Forecast(payload: p, isDefault: false)
        #expect(f.timeZone.identifier == "Europe/London")
        #expect(Derivations.horizonLabel(forecast: f) == "HRRR ends 13:00") // 12:00Z horizon in BST
        #expect(custom.timeZone.identifier == "America/Los_Angeles") // card only
    }
}
