import Foundation
import Testing
@testable import WindCore

@Suite("Twilight shading (HANDOFF §2, §6.2)")
struct TwilightTests {
    func range(_ f: Forecast) -> ClosedRange<Date> { f.start...f.start.addingTimeInterval(45 * 3600) }

    @Test func referenceStopsMatchHandoff62() throws {
        let f = try Fixture.forecast()
        let stops = Twilight.gradientStops(range: range(f), sun: f.sun)
        #expect(stops.count == 8)
        #expect(stops.first == TwilightStop(fraction: 0, value: 1))
        #expect(stops.last == TwilightStop(fraction: 1, value: 0))
        let expected: [(Double, Double)] = [
            (0.2044, 1), // sunset Wed 18:12
            (0.2163, 0), // civil dusk 18:44
            (0.4918, 0), // civil dawn Thu
            (0.5037, 1), // sunrise Thu
            (0.7370, 1), // sunset Thu 18:10
            (0.7489, 0), // civil dusk 18:42
        ]
        for (stop, e) in zip(stops.dropFirst().dropLast(), expected) {
            #expect(abs(stop.fraction - e.0) <= 0.002, "fraction \(stop.fraction) vs \(e.0)")
            #expect(stop.value == e.1)
        }
        // Sorted and strictly increasing.
        #expect(zip(stops, stops.dropFirst()).allSatisfy { $0.fraction < $1.fraction })
    }

    @Test func fridayDawnNotEmitted() throws {
        let f = try Fixture.forecast()
        let stops = Twilight.gradientStops(range: range(f), sun: f.sun)
        let fridayDawn = f.sun[2].civilDawn
        #expect(fridayDawn > range(f).upperBound)
        #expect(!stops.contains { $0.fraction > 0.75 && $0.fraction < 1 })
        // Wednesday dawn/rise precede `start` and are not emitted either.
        #expect(stops.filter { $0.fraction < 0.2 }.count == 1)
    }

    @Test func dayAtSpotChecks() throws {
        let f = try Fixture.forecast()
        #expect(Twilight.day(at: Fixture.la(2026, 10, 21, 12), sun: f.sun) == 1)
        #expect(abs(Twilight.day(at: Fixture.la(2026, 10, 21, 18, 28), sun: f.sun) - 0.5) <= 0.02)
        #expect(Twilight.day(at: Fixture.la(2026, 10, 22, 3), sun: f.sun) == 0)
        // Fixture Thursday dawn/rise are 07:09/07:41, so the midpoint is 07:25.
        #expect(abs(Twilight.day(at: Fixture.la(2026, 10, 22, 7, 25), sun: f.sun) - 0.5) <= 0.001)
        #expect(abs(Twilight.day(at: Fixture.la(2026, 10, 22, 7, 24), sun: f.sun) - 15.0 / 32.0) <= 0.002)
        // Exactly at the events.
        #expect(Twilight.day(at: f.sun[0].sunset, sun: f.sun) == 1)
        #expect(Twilight.day(at: f.sun[0].civilDusk, sun: f.sun) == 0)
        #expect(Twilight.day(at: f.sun[1].civilDawn, sun: f.sun) == 0)
        #expect(Twilight.day(at: f.sun[1].sunrise, sun: f.sun) == 1)
    }

    @Test func holdsOutsideCoveredDays() throws {
        let f = try Fixture.forecast()
        #expect(Twilight.day(at: f.sun[0].civilDawn.addingTimeInterval(-3600 * 10), sun: f.sun) == 0)
        #expect(Twilight.day(at: f.sun[2].civilDusk.addingTimeInterval(3600 * 30), sun: f.sun) == 0)
        #expect(Twilight.day(at: f.start, sun: []) == 1)
    }

    @Test func allDaytimeRangeIsTwoFullStops() throws {
        let f = try Fixture.forecast()
        let r = Fixture.la(2026, 10, 21, 10)...Fixture.la(2026, 10, 21, 16)
        let stops = Twilight.gradientStops(range: r, sun: f.sun)
        #expect(stops == [TwilightStop(fraction: 0, value: 1), TwilightStop(fraction: 1, value: 1)])
    }

    @Test func allNightRangeIsTwoZeroStops() throws {
        let f = try Fixture.forecast()
        let r = Fixture.la(2026, 10, 21, 20)...Fixture.la(2026, 10, 22, 6)
        let stops = Twilight.gradientStops(range: r, sun: f.sun)
        #expect(stops == [TwilightStop(fraction: 0, value: 0), TwilightStop(fraction: 1, value: 0)])
    }

    @Test func rangeBoundaryOnEventIsDeduplicated() throws {
        let f = try Fixture.forecast()
        let r = f.sun[0].sunset...f.sun[1].sunrise
        let stops = Twilight.gradientStops(range: r, sun: f.sun)
        #expect(stops.map(\.fraction).first == 0)
        #expect(stops.map(\.fraction).last == 1)
        #expect(stops.count == 4) // sunset(1), dusk(0), dawn(0), sunrise(1)
        #expect(stops.map(\.value) == [1, 0, 0, 1])
    }

    @Test func twelveHourWatchWindow() throws {
        // 12-slot window from hour 15 (Thu 00:00) to hour 27 (Thu 12:00): night → dawn → rise → day.
        let f = try Fixture.forecast()
        let r = f.date(ofHour: 15)...f.date(ofHour: 27)
        let stops = Twilight.gradientStops(range: r, sun: f.sun)
        #expect(stops.count == 4)
        #expect(stops.map(\.value) == [0, 0, 1, 1])
        #expect(abs(stops[1].fraction - (7.0 + 9.0 / 60.0) / 12.0) <= 0.001)
        #expect(abs(stops[2].fraction - (7.0 + 41.0 / 60.0) / 12.0) <= 0.001)
    }
}
