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

    @Test func nextReload() {
        let now = Date(timeIntervalSince1970: 1_792_600_000)
        #expect(TimelineBuilder.nextReload(after: now) == now.addingTimeInterval(1800))
        #expect(TimelineBuilder.nextReload(after: now, interval: 600) == now.addingTimeInterval(600))
    }
}
