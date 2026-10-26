import Foundation
import Testing
@testable import WindCore

@Suite("TimelineBuilder (DESIGN §5.2, HANDOFF §7.1)")
struct TimelineTests {
    @Test func earlyInForecast() throws {
        let f = try Fixture.forecast() // fetched = start = Wed 09:00 PDT, 45 hours
        let now = f.start.addingTimeInterval(30 * 60)
        let entries = TimelineBuilder.entries(forecast: f, now: now)

        #expect(entries.count == 47)
        #expect(entries.first == WindTimelineEntry(date: now, hourIndex: 0, trust: .fresh))

        // Strictly increasing dates.
        #expect(zip(entries, entries.dropFirst()).allSatisfy { $0.date < $1.date })

        // Hourly boundaries Wed 10:00 … Fri 05:00 (44) all present, each with its own index.
        for i in 1...44 {
            let date = f.date(ofHour: i)
            let e = try #require(entries.first { $0.date == date }, "missing hour \(i)")
            #expect(e.hourIndex == i)
        }

        // Flip entries.
        let stale = try #require(entries.first { $0.date == Fixture.la(2026, 10, 21, 10, 30) })
        #expect(stale.hourIndex == 1)
        #expect(stale.trust == .stale)
        let old = entries.filter { $0.date == Fixture.la(2026, 10, 21, 15) }
        #expect(old.count == 1) // coincides with an hour boundary → de-duplicated
        #expect(old.first?.trust == .old)
        #expect(old.first?.hourIndex == 6)

        // Trust progression along the timeline.
        #expect(entries.filter { $0.trust == .fresh }.count == 2)   // 09:30, 10:00
        #expect(entries.filter { $0.trust == .stale }.count == 5)   // 10:30, 11, 12, 13, 14
        #expect(entries.dropFirst(7).dropLast().allSatisfy { $0.trust == .old })

        // Final past-horizon entry.
        let last = try #require(entries.last)
        #expect(last == WindTimelineEntry(date: Fixture.la(2026, 10, 23, 6), hourIndex: nil, trust: .pastHorizon))
        #expect(entries.dropLast().allSatisfy { $0.hourIndex != nil })

        // Every non-final index is the hero index for its date.
        for e in entries.dropLast() {
            #expect(e.hourIndex == Derivations.heroIndex(forecast: f, now: e.date))
            #expect(e.trust == TrustState.compute(forecast: f, now: e.date, lastCheckOK: true))
        }
    }

    @Test func lateInForecast() throws {
        let f = try Fixture.forecast()
        let now = Fixture.la(2026, 10, 22, 20) // Thu 20:00 = hour 35
        let entries = TimelineBuilder.entries(forecast: f, now: now)
        #expect(entries.count == 11) // now + hours 36…44 + past-horizon
        #expect(entries.first?.date == now)
        #expect(entries.first?.hourIndex == 35)
        #expect(entries.dropLast().allSatisfy { $0.trust == .old })
        #expect(entries.dropLast().map(\.hourIndex) == [35, 36, 37, 38, 39, 40, 41, 42, 43, 44])
        #expect(entries.last == WindTimelineEntry(date: Fixture.la(2026, 10, 23, 6), hourIndex: nil, trust: .pastHorizon))
        // The old flips are in the past and not re-emitted.
        #expect(!entries.contains { $0.date == Fixture.la(2026, 10, 21, 10, 30) })
    }

    @Test func exactlyOnAnHourBoundary() throws {
        let f = try Fixture.forecast()
        let entries = TimelineBuilder.entries(forecast: f, now: f.start)
        #expect(entries.first?.date == f.start)
        #expect(entries.first?.hourIndex == 0)
        #expect(entries[1].date == f.date(ofHour: 1)) // strictly after now; start itself is not repeated
        #expect(entries.count == 47)
    }

    @Test func atHorizonIsStillAForecast() throws {
        let f = try Fixture.forecast()
        let entries = TimelineBuilder.entries(forecast: f, now: f.horizon)
        #expect(entries.count == 2)
        #expect(entries.first == WindTimelineEntry(date: f.horizon, hourIndex: 44, trust: .old))
        #expect(entries.last?.trust == .pastHorizon)
    }

    @Test func pastHorizonIsOneEntry() throws {
        let f = try Fixture.forecast()
        for now in [Fixture.la(2026, 10, 23, 6, 30), Fixture.la(2026, 10, 23, 5, 0, 1), Fixture.la(2026, 10, 25, 12)] {
            let entries = TimelineBuilder.entries(forecast: f, now: now)
            #expect(entries == [WindTimelineEntry(date: now, hourIndex: nil, trust: .pastHorizon)])
        }
    }

    @Test func beforeStartClampsToHourZero() throws {
        let f = try Fixture.forecast()
        let now = f.start.addingTimeInterval(-20 * 60)
        let entries = TimelineBuilder.entries(forecast: f, now: now)
        #expect(entries.first == WindTimelineEntry(date: now, hourIndex: 0, trust: .fresh))
        #expect(entries[1].date == f.start)
        #expect(entries[1].hourIndex == 0)
        #expect(entries.count == 1 + 45 + 1 + 1)
    }

    @Test func offlineFirstEntry() throws {
        let f = try Fixture.forecast()
        let now = f.start.addingTimeInterval(30 * 60)
        let entries = TimelineBuilder.entries(forecast: f, now: now, lastCheckOK: false)
        #expect(entries.first?.trust == .offlineCached)
        #expect(entries.dropLast().allSatisfy { $0.trust == .offlineCached })
        #expect(entries.last?.trust == .pastHorizon)
        #expect(entries.count == 47)
    }

    func synthetic(hours: Int) throws -> Forecast {
        var p = try Fixture.payload()
        p.hours = hours
        p.kn = Array(repeating: 10, count: hours)
        p.gust = Array(repeating: 15, count: hours)
        p.dir = Array(repeating: 270, count: hours)
        return Forecast(payload: p, isDefault: true)
    }

    @Test func fortyEightHoursFitsUnderCap() throws {
        let f = try synthetic(hours: 48)
        let entries = TimelineBuilder.entries(forecast: f, now: f.start)
        #expect(entries.count == 1 + 47 + 1 + 1) // now, 47 boundaries, 10:30 flip (15:00 dedups), past-horizon
        #expect(entries.count <= TimelineBuilder.maxEntries)
        #expect(entries.last == WindTimelineEntry(date: f.horizon.addingTimeInterval(3600), hourIndex: nil, trust: .pastHorizon))
    }

    @Test func capKeepsPastHorizonEntry() throws {
        let f = try synthetic(hours: 80)
        let entries = TimelineBuilder.entries(forecast: f, now: f.start)
        #expect(entries.count == TimelineBuilder.maxEntries)
        #expect(entries.last?.trust == .pastHorizon)
        #expect(entries.last?.date == f.horizon.addingTimeInterval(3600))
        #expect(entries.dropLast().allSatisfy { $0.hourIndex != nil })
        #expect(entries[entries.count - 2].hourIndex == 57) // now(0), 10:30(1), hours 1…57 → 59 entries + final
        #expect(zip(entries, entries.dropFirst()).allSatisfy { $0.date < $1.date })
    }

    @Test("Strip domain: floor 20, rounds to 5, never shrinks across entries (§6.3)") func stripDomainsGrowOnly() throws {
        let f = try Fixture.forecast()
        let entries = TimelineBuilder.entries(forecast: f, now: f.start)
        let domains = TimelineBuilder.stripDomains(forecast: f, entries: entries)
        #expect(domains.count == entries.count)
        #expect(domains.last! == nil) // past-horizon entry
        let shown = domains.dropLast().compactMap { $0 }
        #expect(shown.count == entries.count - 1)
        #expect(zip(shown, shown.dropFirst()).allSatisfy { $0 <= $1 })
        // Hours 0–2 see max gust 15–18 → 20; hour 3's window reaches the 24 kn gust → 25.
        #expect(entries.firstIndex { $0.hourIndex == 3 }.map { domains[$0] } == 25)
        #expect(domains.first! == 20)
        // Hour 20's own window (max 19 → 20) keeps 25: the peak scrolled out but the scale holds.
        let h20 = try #require(entries.firstIndex { $0.hourIndex == 20 })
        let own = ChartModel(forecast: f, now: entries[h20].date, window: .complication, scheme: .dark)
        #expect(own.yMax == 20 && domains[h20] == 25)
        #expect(ChartModel(forecast: f, now: entries[h20].date, window: .complication, scheme: .dark, yMaxFloor: domains[h20]).yMax == 25)
    }

    @Test("Strip domain carried between reloads of the same run; reset on a new run or place") func stripDomainsCarried() throws {
        let f = try Fixture.forecast()
        // A reload at hour 20: on its own the window gives 20.
        let late = TimelineBuilder.entries(forecast: f, now: f.date(ofHour: 20))
        #expect(TimelineBuilder.stripDomains(forecast: f, entries: late).first! == 20)
        // Carried from the previous build at hour 0 (domain 20): the hours the old timeline showed
        // since then (windows 0–19, peak 25) are folded in.
        let fromStart = StripScale(forecast: f, yMax: 20, asOf: f.start)
        #expect(TimelineBuilder.stripDomains(forecast: f, entries: late, carried: fromStart).first! == 25)
        // A carried higher value holds.
        let high = StripScale(forecast: f, yMax: 35, asOf: f.date(ofHour: 19))
        #expect(TimelineBuilder.stripDomains(forecast: f, entries: late, carried: high).compactMap { $0 }.allSatisfy { $0 == 35 })
        // New run: starts again from its own window.
        var newRun = high
        newRun.runDate = f.runDate.addingTimeInterval(3600)
        #expect(TimelineBuilder.stripDomains(forecast: f, entries: late, carried: newRun).first! == 20)
        // Another place: also a fresh scale.
        var elsewhere = high
        elsewhere.lat += 1
        #expect(!elsewhere.matches(f))
        #expect(TimelineBuilder.stripDomains(forecast: f, entries: late, carried: elsewhere).first! == 20)
        // Round-trips through defaults.
        let defaults = try #require(UserDefaults(suiteName: "StripScaleTests"))
        defaults.removePersistentDomain(forName: "StripScaleTests")
        #expect(StripScale.load(from: defaults) == nil)
        high.save(to: defaults)
        #expect(StripScale.load(from: defaults) == high)
        defaults.removePersistentDomain(forName: "StripScaleTests")
    }

    @Test func stripDomainsPastHorizonOnly() throws {
        let f = try Fixture.forecast()
        let entries = TimelineBuilder.entries(forecast: f, now: f.horizon.addingTimeInterval(7200))
        #expect(TimelineBuilder.stripDomains(forecast: f, entries: entries) == [nil])
    }

    @Test func nextReload() {
        let now = Date(timeIntervalSince1970: 1_792_600_000)
        #expect(TimelineBuilder.nextReload(after: now) == now.addingTimeInterval(1800))
        #expect(TimelineBuilder.nextReload(after: now, interval: 600) == now.addingTimeInterval(600))
    }
}
