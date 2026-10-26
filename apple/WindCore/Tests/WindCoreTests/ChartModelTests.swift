import Foundation
import SwiftUI
import Testing
@testable import WindCore

@Suite("ChartModel")
struct ChartModelTests {
    @Test func allWindowEarly() throws {
        let f = try Fixture.forecast()
        let now = f.start.addingTimeInterval(30 * 60)
        let m = ChartModel(forecast: f, now: now, window: .all, scheme: .dark)
        #expect(m.points.count == 45)
        #expect(m.points.first?.index == 0 && m.points.last?.index == 44)
        #expect(m.points[15] == HourPoint(index: 15, date: f.date(ofHour: 15), kn: 15, gust: 25, dirFrom: 283, step: 4,
                                          tempC: 7.9, cloud: 100, precip: 1.2))
        #expect(m.xRange == f.start...f.horizon.addingTimeInterval(3600))
        #expect(m.firstIndex == 0)
        #expect(m.slotCount == 45)
        #expect(m.yMax == 30)
        #expect(m.horizonEdgeSlot == 45)
        #expect(m.sunMarkers == [f.sun[0].sunset, f.sun[1].sunrise, f.sun[1].sunset])
        #expect(m.nowDate == now && m.showsNow)
        #expect(m.nowIndex == 0.5 && m.nowSlot == 0.5)
        #expect(m.ageTier == .fresh)
        #expect(m.twilightStops == Twilight.gradientStops(range: m.xRange, sun: f.sun))
        #expect(m.twilightStops.count == 8)
        #expect(m.maxGust == 25)
        #expect(m.timeZone.identifier == "America/Los_Angeles")
        #expect(m.dayLabels == [DayLabel(slot: 0, name: "Wed"), DayLabel(slot: 15, name: "Thu"), DayLabel(slot: 39, name: "Fri")])
        #expect(m.hourOfDay(slot: 0) == 9 && m.hourOfDay(slot: 15) == 0)
    }

    @Test func next12MidForecast() throws {
        let f = try Fixture.forecast()
        let now = Fixture.la(2026, 10, 21, 23, 30) // index 14.5
        let m = ChartModel(forecast: f, now: now, window: .next12, scheme: .dark)
        #expect(m.points.map(\.index) == Array(14...25))
        #expect(m.firstIndex == 14)
        #expect(m.xRange == f.date(ofHour: 14)...f.date(ofHour: 26))
        #expect(m.slotCount == 12)
        #expect(m.horizonEdgeSlot == nil)
        #expect(m.yMax == 30) // max gust 25 in hours 14…25
        #expect(m.sunMarkers == [f.sun[1].sunrise]) // Thu 07:41 within 23:00…11:00
        #expect(m.showsNow && m.nowSlot == 0.5)
        #expect(m.dayLabels == [DayLabel(slot: 0, name: "Wed"), DayLabel(slot: 1, name: "Thu")])
    }

    @Test func next12NearHorizon() throws {
        let f = try Fixture.forecast()
        let now = Fixture.la(2026, 10, 22, 22, 30) // index 37.5
        let m = ChartModel(forecast: f, now: now, window: .next12, scheme: .dark)
        #expect(m.points.map(\.index) == Array(37...44))
        #expect(m.points.count == 8)
        #expect(m.xRange == f.date(ofHour: 37)...f.date(ofHour: 49))
        #expect(m.slotCount == 12)
        #expect(m.horizonEdgeSlot == 8)
        #expect(m.yMax == 30) // gusts 20,20,20,18,18,20,21,21 → ceil(24/10)*10 = 30
        #expect(m.ageTier == .old)
    }

    @Test func next6RoundsToFiveAndEmptiesPastHorizon() throws {
        let f = try Fixture.forecast()
        let w = ChartModel(forecast: f, now: f.start.addingTimeInterval(13.9 * 3600), window: .next6, scheme: .dark)
        #expect(w.firstIndex == 13)
        #expect(w.points.map(\.index) == [13, 14, 15, 16, 17, 18])
        #expect(w.yMax == 25)
        #expect(w.xRange == f.date(ofHour: 13)...f.date(ofHour: 19))
        #expect(w.sunMarkers.isEmpty)
        #expect(w.ageTier == .old)
        let early = ChartModel(forecast: f, now: f.start, window: .next6, scheme: .dark)
        #expect(early.points.map(\.gust) == [4, 5, 3, 3, 4, 2])
        #expect(early.yMax == 5)
        let w2 = ChartModel(forecast: f, now: f.date(ofHour: 9), window: .next6, scheme: .dark)
        #expect(w2.points.map(\.gust) == [9, 13, 15, 18, 19, 24])
        #expect(w2.yMax == 25)
        #expect(w2.sunMarkers == [f.sun[0].sunset]) // 18:12 inside 18:00…24:00
        let tail = ChartModel(forecast: f, now: f.date(ofHour: 42), window: .next6, scheme: .dark)
        #expect(tail.points.map(\.index) == [42, 43, 44])
        #expect(tail.horizonEdgeSlot == 3)
        let gone = ChartModel(forecast: f, now: f.horizon.addingTimeInterval(1), window: .next6, scheme: .dark)
        #expect(gone.points.isEmpty)
        #expect(gone.yMax == 5)
    }

    @Test func oldTier() throws {
        let f = try Fixture.forecast()
        let m = ChartModel(forecast: f, now: f.fetched.addingTimeInterval(7 * 3600), window: .all, scheme: .dark)
        #expect(m.ageTier == .old)
        let fresh = ChartModel(forecast: f, now: f.fetched.addingTimeInterval(60), window: .all, scheme: .dark)
        #expect(fresh.ageTier == .fresh)
    }

    @Test func shadeStopsFollowScheme() throws {
        let f = try Fixture.forecast()
        let dark = ChartModel(forecast: f, now: f.start, window: .all, scheme: .dark)
        let light = ChartModel(forecast: f, now: f.start, window: .all, scheme: .light)
        #expect(dark.shadeStops.count == dark.twilightStops.count)
        #expect(dark.shadeStops.first?.color == Color.white.opacity(0.07))
        #expect(dark.shadeStops.last?.color == Color.white.opacity(0))
        #expect(light.shadeStops.first?.color == Color.black.opacity(0))
        #expect(light.shadeStops.last?.color == Color.black.opacity(0.08))
        #expect(dark.shadeStops.map { Double($0.location) } == dark.twilightStops.map(\.fraction))
    }

    @Test func beforeStartClampsWindow() throws {
        let f = try Fixture.forecast()
        let m = ChartModel(forecast: f, now: f.start.addingTimeInterval(-3600), window: .next12, scheme: .dark)
        #expect(m.points.map(\.index) == Array(0...11))
        #expect(!m.showsNow)
        #expect(ChartGeometry(model: m, style: .watchStrip, width: 198).nowX == nil)
    }
}

@Suite("ChartGeometry labels and selection")
struct ChartGeometryTests {
    @Test func phoneTicksAndLabels() throws {
        let f = try Fixture.forecast()
        let m = ChartModel(forecast: f, now: f.start.addingTimeInterval(0.4 * 3600), window: .all, scheme: .dark)
        let g = ChartGeometry(model: m, style: .phonePortrait, width: 402)
        #expect(g.tickPoints.map(\.index) == [0, 6, 12, 18, 24, 30, 36, 42])
        // The first label would clip at the edge-to-edge plot's left edge (26 Oct, item 3).
        #expect(g.tickPoints.map { g.tickLabel($0) } == [nil, "3pm", "9pm", "3am", "9am", "3pm", "9pm", "3am"])
        #expect(g.arrowPoints.map(\.index) == Array(stride(from: 0, through: 42, by: 3)))
        #expect(g.edgeLabel == "ends Fri 5am")
        // The first day's name is suppressed while `now` is drawn (the readout names the day).
        #expect(g.dayMarks.map(\.name) == ["Thu", "Fri"])
        #expect(g.dayMarks.map(\.divider) == [true, true])
        #expect(g.gridValues == [10, 20])
        #expect(g.height == 275)
        let land = ChartGeometry(model: m, style: .phoneLandscape, width: 834)
        #expect(land.tickPoints.map { land.tickLabel($0) }.prefix(5) == ["9am", "noon", "3pm", "6pm", "9pm"])
        #expect(land.tickPoints.map(\.index).contains(15))
        #expect(land.tickLabel(m.points[15]) == "12am")
        #expect(land.arrowPoints.count == 45)
    }

    @Test func watchTicksAndEdge() throws {
        let f = try Fixture.forecast()
        let m = ChartModel(forecast: f, now: f.start.addingTimeInterval(0.4 * 3600), window: .next12, scheme: .dark)
        let g = ChartGeometry(model: m, style: .watchStrip, width: 198)
        #expect(g.tickPoints.map { g.tickLabel($0) } == ["09", "12", "15", "18"])
        #expect(g.edgeX == nil && g.edgeLabel == nil)
        #expect(g.dayMarks.isEmpty)
        #expect(g.slot == 198.0 / 12)
        let short = ChartModel(forecast: f, now: f.date(ofHour: 39).addingTimeInterval(360), window: .next12, scheme: .dark)
        let gs = ChartGeometry(model: short, style: .watchStrip, width: 198)
        #expect(gs.tickPoints.map { gs.tickLabel($0) } == ["00", "03"])
        #expect(gs.edgeLabel == "ends 05:00")
        #expect(gs.edgeX == 6 * gs.slot)
        let mini = ChartGeometry(model: ChartModel(forecast: f, now: f.date(ofHour: 15), window: .next6, scheme: .dark), style: .mini, width: 75)
        #expect(mini.tickPoints.isEmpty && mini.arrowPoints.isEmpty && mini.gridValues.isEmpty && mini.edgeLabel == nil)
        #expect(mini.height == 31)
    }

    @Test func selectionAndHitTesting() throws {
        let f = try Fixture.forecast()
        let m = ChartModel(forecast: f, now: f.start, window: .all, scheme: .dark)
        let g = ChartGeometry(model: m, style: .phonePortrait, width: 402)
        #expect(g.index(atX: 0) == 0)
        #expect(g.index(atX: 15 * g.slot + 1) == 15)
        #expect(g.index(atX: -40) == 0)
        #expect(g.index(atX: 10_000) == 44)
        let p = m.points[15]
        let bar = g.barRect(p)
        let outline = g.selectionOutline(p)
        #expect(outline.minX == bar.minX - 1.5 && outline.width == bar.width + 3)
        #expect(outline.minY == bar.minY - 1.5 && outline.height == bar.height + 1.5)
        #expect(g.selectionRuleX(index: 15) == g.centreX(index: 15))
        let empty = ChartModel(forecast: f, now: f.horizon.addingTimeInterval(3600), window: .next6, scheme: .dark)
        #expect(ChartGeometry(model: empty, style: .mini, width: 75).index(atX: 10) == nil)
    }

    @Test func zeroKnotStub() throws {
        var f = try Fixture.forecast()
        f.hours[0] = Forecast.Hour(kn: 0, gust: 2, dirFrom: 90)
        let m = ChartModel(forecast: f, now: f.start, window: .all, scheme: .dark)
        let g = ChartGeometry(model: m, style: .phonePortrait, width: 402)
        #expect(g.barRect(m.points[0]).height == 1)
        #expect(m.points[0].step == 0)
    }
}

@Suite("View smoke tests")
struct ViewSmokeTests {
    @Test @MainActor func viewsConstruct() throws {
        let f = try Fixture.forecast()
        let now = f.start.addingTimeInterval(30 * 60)
        let chart = WindChart(model: ChartModel(forecast: f, now: now, window: .all, scheme: .dark), style: .phonePortrait, selection: 15, onScrub: { _ in })
        _ = chart.body
        let watchChart = WindChart(model: ChartModel(forecast: f, now: now, window: .next12, scheme: .dark), style: .watchStrip)
        _ = watchChart.body
        let strip = MiniStrip(forecast: f, now: now)
        _ = strip.body
        for state in TrustState.allCases {
            let line = TrustLineView(state: state, forecast: state == .firstRun ? nil : f, now: now, compact: state == .stale)
            _ = line.body
            #expect(line.text == TrustLine.text(state: state, forecast: state == .firstRun ? nil : f, now: now))
        }
        #expect(TrustLineView(state: .pastHorizon, forecast: f, now: now).isAmber)
        #expect(!TrustLineView(state: .fresh, forecast: f, now: now).isAmber)
        _ = ArrowView(dirFrom: 290, size: 18).body
        _ = BeaufortPill(step: 10).body
        _ = BeaufortChip(step: 4).body
        _ = TickCap(width: 10, lineWidth: 1.5).body
        _ = SunDot(radius: 3).body
        _ = WifiSlash().body
    }

    @Test func arrowShapeGeometry() {
        let p = ArrowShape().path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        let b = p.boundingRect
        #expect(abs(b.minX - 12) < 0.01 && abs(b.maxX - 88) < 0.01)
        #expect(abs(b.minY - 0) < 0.01 && abs(b.maxY - 100) < 0.01)
    }

    @Test func previewDataLoads() {
        #expect(PreviewData.forecast.hours.count == 45)
        #expect(PreviewData.forecast.run == "HRRR 15Z")
        #expect(PreviewData.now == PreviewData.forecast.start.addingTimeInterval(1800))
        #expect(PreviewData.chart(window: .all).points.count == 45)
    }

    @Test func tokensAndFonts() {
        #expect(Tokens.ground(.dark) == Color(hex: "#0B0E12"))
        #expect(Tokens.ground(.light) == Color(hex: "#F4F5F7"))
        #expect(Tokens.trustAmber(.light) == Color(hex: "#B86E00"))
        #expect(Tokens.numberInk(.dark, tier: .old) == Tokens.inkOld(.dark))
        #expect(Tokens.numberInk(.dark, tier: .stale) == Tokens.inkPrimary(.dark))
        #expect(WindTheme(.dark).beaufort(step: 4) == Color(hex: "#8DD44A"))
        _ = Tokens.heroFont(watch: true)
        _ = Tokens.trustFont(watch: false, amber: true)
        #expect(Tokens.heroTracking(watch: true) < 0)
    }
}

@Suite("12-hour labels (HANDOFF §6.4a)")
struct TwelveHourLabelTests {
    @Test func hourForms() throws {
        #expect(TimeFormat.hour12Tick(hour: 0) == "12am")
        #expect(TimeFormat.hour12Tick(hour: 9) == "9am")
        #expect(TimeFormat.hour12Tick(hour: 12) == "noon")
        #expect(TimeFormat.hour12Tick(hour: 15) == "3pm")
        #expect(TimeFormat.hour12(hour: 12) == "12pm")
        #expect(TimeFormat.hour12(hour: 23) == "11pm")
        let f = try Fixture.forecast()
        let now = f.start.addingTimeInterval(1800)
        #expect(Derivations.chartTitle(forecast: f) == "Wed 9am → Fri 5am")
        #expect(Derivations.horizonWeekdayLabel(forecast: f) == "ends Fri 5am")
        #expect(Derivations.scrubLabel(forecast: f, index: 15) == "Thu 12am · midnight")
        #expect(Derivations.scrubLabel(forecast: f, index: 27) == "Thu 12pm · noon")
        #expect(Derivations.scrubLabel(forecast: f, index: 30) == "Thu 3pm")
        #expect(TrustLineView(state: .fresh, forecast: f, now: now, suffix: Derivations.horizonWeekdayLabel(forecast: f)).text == "as of 09:00 · HRRR 15Z · ends Fri 5am")
        #expect(TrustLineView(state: .offlineCached, forecast: f, now: now, suffix: "ends Fri 5am").text == "Couldn't reach server · showing data from 09:00")
        #expect(TrustLineView(state: .pastHorizon, forecast: f, now: f.horizon.addingTimeInterval(60), suffix: "x").text == "No forecast · last run HRRR 15Z Wed")
        #expect(TrustLineView(state: .firstRun, forecast: nil, now: now, suffix: "x").text == "No data yet. Needs cellular or Wi-Fi once.")
    }
}
