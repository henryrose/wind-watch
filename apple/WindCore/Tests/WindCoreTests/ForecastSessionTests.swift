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
        defer { s.defaults.removeObject(forKey: LocationSettings.customLocationKey); s.defaults.removeObject(forKey: LocationSettings.useCustomKey) }
        s.saveCustom(custom)
        #expect(s.preferences.effectiveUseCustom)
        #expect(s.locationName == "Seattle")
        #expect(s.forecast?.location.isDefault == false)
        #expect(s.forecast != nil) // fixture keeps the payload
        s.selectDefault()
        #expect(!s.preferences.useCustom)
        #expect(s.locationName == "Port Townsend Bay")
        #expect(s.forecast?.location.isDefault == true)
        s.selectCustom()
        #expect(s.preferences.effectiveUseCustom)
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

    @Test func reloadFlipsIsDefaultInFixtureMode() throws {
        let h = try Harness(fixture: true); defer { h.cleanup() }
        #expect(h.session.forecast?.location.isDefault == true)
        LocationSettings.save(.init(custom: custom, useCustom: true), to: h.session.defaults)
        #expect(h.session.reloadPreferences() == true)
        #expect(h.session.preferences == .init(custom: custom, useCustom: true))
        #expect(h.session.forecast != nil)
        #expect(h.session.forecast?.location.isDefault == false)
        #expect(h.session.locationName == "Seattle")
        #expect(h.session.reloadPreferences() == false) // nothing changed
    }

    @Test func reloadClearsCacheOnlyWhenActiveLocationChanges() throws {
        let h = try Harness(fixture: false); defer { h.cleanup() }
        #expect(h.session.forecast != nil)
        // A custom location saved but not selected: preferences change, cache stays.
        LocationSettings.save(.init(custom: custom, useCustom: false), to: h.session.defaults)
        #expect(h.session.reloadPreferences() == false)
        #expect(h.session.preferences.custom == custom)
        #expect(h.session.forecast != nil)
        #expect(h.session.store.load() != nil)
        // Now selected: active location changed → cache dropped.
        LocationSettings.save(.init(custom: custom, useCustom: true), to: h.session.defaults)
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
        h.session.saveCustom(custom)
        h.session.selectDefault()
        h.session.selectCustom()
        h.session.selectCustom() // no-op, already selected
        #expect(box.seen.map(\.useCustom) == [true, false, true])
        #expect(box.seen.allSatisfy { $0.custom == custom })
        #expect(LocationSettings.load(from: h.session.defaults) == .init(custom: custom, useCustom: true))
    }

    @Test func trySaveCustomRefusesAPointOutsideHRRRAndChangesNothing() async throws {
        let h = try Harness(fixture: false); defer { h.cleanup() }
        let london = SavedLocation(name: "London", lat: 51.5, lon: -0.12, tz: "Europe/London")
        let before = h.session.preferences
        #expect(await h.session.trySaveCustom(london) == .outsideCoverage)
        #expect(h.session.preferences == before)
        #expect(h.session.forecast != nil) // the cache is untouched
        #expect(h.session.store.load() != nil)
    }

    @Test func trySaveCustomSavesInFixtureMode() async throws {
        let h = try Harness(fixture: true); defer { h.cleanup() }
        #expect(await h.session.trySaveCustom(custom) == .saved)
        #expect(h.session.preferences == .init(custom: custom, useCustom: true))
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
