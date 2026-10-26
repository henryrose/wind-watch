import Foundation
import SwiftUI
import Testing
@testable import WindCore

/// The 26 Oct additions (spec §12a, §12b, §5): the 7-day HRRR→NBM chart against
/// `mixed_reference.py`, the sky band against `sky_reference.py`, sun rise/set markers against
/// `chart_reference.py`, and the derivations behind the readout, peak chip and table.
///
/// `p7.svg`, `p7sel.svg`, `l7.svg` come from `mixed_svg(..., total=144)`: the fixture's NBM blocks end
/// at hour 144 (`ends Tue 9am`) and the chart stops where the forecast stops. `sky48.svg` is
/// `band_svg(402, 0)`.
@Suite("Seam, sky band and sun markers")
struct ModelSeamSkyTests {
    struct SVG {
        let text: String

        init(_ name: String) throws {
            let url = try #require(Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "charts"))
            text = try String(contentsOf: url, encoding: .utf8)
        }

        func numbers(_ pattern: String) -> [[Double]] {
            let re = try! NSRegularExpression(pattern: pattern)
            return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
                (1..<m.numberOfRanges).compactMap { Range(m.range(at: $0), in: text) }.compactMap { Double(text[$0]) }
            }
        }

        var bars: [(x: Double, y: Double, w: Double, h: Double, opacity: Double)] {
            let re = try! NSRegularExpression(pattern: ##"<rect x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" height="([\d.]+)" rx="1.5" fill="#[0-9A-F]+"( fill-opacity="([\d.]+)")?/>"##)
            return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
                func d(_ i: Int) -> Double? { Range(m.range(at: i), in: text).flatMap { Double(text[$0]) } }
                return (d(1)!, d(2)!, d(3)!, d(4)!, d(6) ?? 1)
            }
        }
        var polylines: [(dashed: Bool, points: [(Double, Double)])] {
            let re = try! NSRegularExpression(pattern: ##"<polyline points="([^"]+)"[^>]*?( stroke-dasharray="4 3")?/>"##)
            return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
                let pts = text[Range(m.range(at: 1), in: text)!].split(separator: " ").map { pair in
                    let xy = pair.split(separator: ",").compactMap { Double($0) }
                    return (xy[0], xy[1])
                }
                return (m.range(at: 2).location != NSNotFound, pts)
            }
        }
        var caps: [(x1: Double, x2: Double, y: Double)] {
            numbers(##"<line x1="([\d.-]+)" x2="([\d.]+)" y1="([\d.]+)" y2="[\d.]+" stroke="#FFFFFF" stroke-width="1.5" stroke-linecap="round"/>"##).map { ($0[0], $0[1], $0[2]) }
        }
        var arrows: [(x: Double, y: Double, rot: Double)] { numbers(##"<g transform="translate\(([\d.]+),([\d.]+)\) rotate\((\d+)\)">"##).map { ($0[0], $0[1], $0[2]) } }
        /// Sun markers: `(cx, cy, isRise)`; a sunset is the ring (`fill="none"`).
        var suns: [(x: Double, y: Double, isRise: Bool)] {
            let re = try! NSRegularExpression(pattern: ##"<circle cx="([\d.]+)" cy="([\d.-]+)" r="([\d.]+)" fill="(none|#FFB340)""##)
            return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
                func s(_ i: Int) -> String { String(text[Range(m.range(at: i), in: text)!]) }
                return (Double(s(1))!, Double(s(2))!, s(4) != "none")
            }
        }
        var gridlines: [Double] { numbers(##"<line x1="0" x2="[\d.]+" y1="([\d.]+)" y2="[\d.]+" stroke="#FFFFFF" stroke-opacity="0.12""##).map { $0[0] } }
        var dashedRules: [Double] { numbers(##"<line x1="([\d.]+)" x2="[\d.]+" y1="[\d.-]+" y2="[\d.]+" stroke="#FFFFFF" stroke-opacity="0.7" stroke-width="1" stroke-dasharray="3 3"/>"##).map { $0[0] } }
        var dividers: [Double] { numbers(##"<line x1="([\d.]+)" x2="[\d.]+" y1="[\d.-]+" y2="[\d.]+" stroke="#FFFFFF" stroke-opacity="0.28""##).map { $0[0] } }
        var nbmTint: (x: Double, w: Double)? { numbers(##"<rect x="([\d.]+)" y="[\d.]+" width="([\d.]+)" height="[\d.]+" fill="#4FA3D8" fill-opacity="0.045"/>"##).first.map { ($0[0], $0[1]) } }
        var stops: [(Double, Double)] { numbers(##"<stop offset="([\d.]+)" stop-color="#FFFFFF" stop-opacity="([\d.]+)"/>"##).map { ($0[0], $0[1]) } }
        var bottomDays: [(x: Double, name: String)] {
            let re = try! NSRegularExpression(pattern: ##"<text x="([\d.]+)" y="[\d.]+" text-anchor="middle" font-size="\d+" font-weight="600" fill="#FFFFFF" fill-opacity="0.6"[^>]*>(\w+)</text>"##)
            return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
                (Double(text[Range(m.range(at: 1), in: text)!])!, String(text[Range(m.range(at: 2), in: text)!]))
            }
        }
        var selectionOutline: (x: Double, y: Double, w: Double, h: Double)? {
            numbers(##"<rect x="([\d.-]+)" y="([\d.]+)" width="([\d.]+)" height="([\d.]+)" rx="2.5" fill="none""##).first.map { ($0[0], $0[1], $0[2], $0[3]) }
        }
        var skyRects: [(x: Double, w: Double, fill: String, opacity: Double)] {
            let re = try! NSRegularExpression(pattern: ##"<rect x="([\d.]+)" y="2" width="([\d.]+)" height="10" rx="2" fill="(#[0-9A-F]+)" fill-opacity="([\d.]+)"/>"##)
            return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
                func s(_ i: Int) -> String { String(text[Range(m.range(at: i), in: text)!]) }
                return (Double(s(1))!, Double(s(2))!, s(3), Double(s(4))!)
            }
        }
        var rainTicks: [Double] { numbers(##"<line x1="([\d.]+)" x2="[\d.]+" y1="8" y2="13" stroke="#4FA3D8""##).map { $0[0] } }
    }

    private func close(_ a: Double, _ b: CGFloat, _ tolerance: Double = 0.06) -> Bool { abs(a - Double(b)) <= tolerance }

    private func week(width: CGFloat, now: Double = 0.4) throws -> (Forecast, ChartModel) {
        let f = try Fixture.forecast()
        return (f, ChartModel(forecast: f, now: f.start.addingTimeInterval(now * 3600), window: .week, scheme: .dark, plotWidth: width))
    }

    /// Everything `mixed_svg` draws, against the port.
    private func compareMixed(_ svg: SVG, _ g: ChartGeometry, sourceLocation: SourceLocation = #_sourceLocation) {
        let m = g.model
        let bars = svg.bars
        #expect(bars.count == m.points.count, sourceLocation: sourceLocation)
        for (b, p) in zip(bars, m.points) {
            let r = g.barRect(p)
            #expect(close(b.x, r.minX) && close(b.w, r.width) && close(b.y, r.minY) && close(b.h, r.height), "bar \(p.index)", sourceLocation: sourceLocation)
            #expect(abs(b.opacity - (p.isNBM ? 0.7 : 1)) < 1e-9 || svg.selectionOutline != nil, "bar opacity \(p.index)", sourceLocation: sourceLocation)
        }
        // Two gust polylines: solid through the HRRR caps, dashed 4/3 through the NBM caps; not joined.
        let lines = svg.polylines
        #expect(lines.count == 2 && !lines[0].dashed && lines[1].dashed, sourceLocation: sourceLocation)
        let hrrr = m.points.filter { !$0.isNBM }, nbm = m.points.filter(\.isNBM)
        for (line, pts) in zip(lines, [hrrr, nbm]) {
            #expect(line.points.count == pts.count, sourceLocation: sourceLocation)
            for (v, p) in zip(line.points, pts) {
                let pt = g.gustPoint(p)
                #expect(close(v.0, pt.x) && close(v.1, pt.y), "gust \(p.index)", sourceLocation: sourceLocation)
            }
        }
        let caps = svg.caps
        #expect(caps.count == m.points.count, sourceLocation: sourceLocation)
        for (c, p) in zip(caps, m.points) {
            #expect(close(c.x2 - c.x1, g.capWidth(p), 0.11) && close(c.y, g.gustPoint(p).y), "cap \(p.index)", sourceLocation: sourceLocation)
        }
        let arrows = svg.arrows
        #expect(arrows.count == g.arrowPoints.count, sourceLocation: sourceLocation)
        for (a, p) in zip(arrows, g.arrowPoints) {
            #expect(close(a.x, g.centreX(p)) && close(a.y, g.arrowY), "arrow \(p.index)", sourceLocation: sourceLocation)
            // The reference rounds the float vector mean once; the port rounds the direction, then adds 180.
            #expect(abs(a.rot - Compass.arrowRotation(dirFrom: p.dirFrom)) <= 1, "arrow rotation \(p.index)", sourceLocation: sourceLocation)
        }
        #expect(svg.gridlines.count == g.gridValues.count, sourceLocation: sourceLocation)
        for (y, v) in zip(svg.gridlines, g.gridValues) { #expect(close(y, g.y(Double(v))), sourceLocation: sourceLocation) }
        // Seam first, then the end rule.
        #expect(svg.dashedRules.count == 2, sourceLocation: sourceLocation)
        #expect(close(svg.dashedRules[0], g.seamX ?? -1) && close(svg.dashedRules[1], g.edgeX ?? -1), sourceLocation: sourceLocation)
        let tint = svg.nbmTint
        #expect(tint != nil && close(tint!.x, g.nbmRegion?.minX ?? -1) && close(tint!.w, g.nbmRegion?.width ?? -1), sourceLocation: sourceLocation)
        #expect(svg.dividers.count == g.dayMarks.filter(\.divider).count, sourceLocation: sourceLocation)
        for (d, mark) in zip(svg.dividers, g.dayMarks.filter(\.divider)) { #expect(close(d, mark.x), sourceLocation: sourceLocation) }
        // The reference drops a partial last day (`cx < W − 10` at `X(h + 12)`); the port centres
        // it on its visible part, so it may have one more.
        let days = svg.bottomDays
        for (d, mark) in zip(days, g.bottomDayMarks) {
            #expect(d.name == mark.name && close(d.x, mark.x), "day \(d.name)", sourceLocation: sourceLocation)
        }
        #expect(g.bottomDayMarks.count - days.count <= 1, sourceLocation: sourceLocation)
        // Sun: the reference approximates the later days (±1 min/day); the port computes them.
        let suns = svg.suns
        #expect(suns.map(\.isRise) == g.sunMarks.map(\.isRise), sourceLocation: sourceLocation)
        for (s, mark) in zip(suns, g.sunMarks) {
            #expect(close(s.x, mark.point.x, 1.5) && close(s.y, mark.point.y), "sun", sourceLocation: sourceLocation)
        }
        let stops = svg.stops
        #expect(stops.count == m.twilightStops.count, sourceLocation: sourceLocation)
        for (s, t) in zip(stops, m.twilightStops) {
            #expect(abs(s.0 - t.fraction) < 0.004 && abs(s.1 - 0.07 * t.value) < 0.002, "stop", sourceLocation: sourceLocation)
        }
    }

    @Test("p7: iPhone portrait 7 d, everything 3-hourly (402×262)") func phoneWeek() throws {
        let (_, m) = try week(width: 402)
        #expect(m.aggregatesHRRR && m.slotCount == 144 && m.seamSlot == 45 && m.horizonEdgeSlot == 144)
        #expect(m.points.count == 15 + 33 && m.yMax == 40)
        let g = ChartGeometry(model: m, style: .phonePortraitWeek, width: 402)
        compareMixed(try SVG("p7"), g)
        #expect(g.edgeLabel == "ends Tue 9am")
        #expect(g.bottomDayMarks.map(\.name) == ["Wed", "Thu", "Fri", "Sat", "Sun", "Mon", "Tue"])
    }

    @Test("p7sel: Sat 12–3pm NBM block selected") func phoneWeekSelected() throws {
        let (f, m) = try week(width: 402)
        let g = ChartGeometry(model: m, style: .phonePortraitWeek, width: 402)
        let svg = try SVG("p7sel")
        let p = try #require(m.point(index: 75))
        #expect(p.isNBM && p.kn == 18 && p.gust == 32 && p.dirFrom == 205 && p.span == 3)
        let outline = try #require(svg.selectionOutline)
        let mine = g.selectionOutline(p)
        #expect(close(outline.x, mine.minX) && close(outline.y, mine.minY) && close(outline.w, mine.width) && close(outline.h, mine.height))
        // A touch anywhere over the block selects its start.
        #expect(g.index(atX: g.x(index: 76)) == 75 && g.index(atX: g.x(index: 77) + 1) == 75)
        #expect(Derivations.slotLabel(p, tz: f.timeZone) == "Sat 12–3pm")
        #expect(Derivations.spokenSlot(p, tz: f.timeZone) == "Saturday 12 to 3pm, NBM")
    }

    @Test("l7: iPhone landscape 7 d keeps HRRR hourly to the seam (834×296)") func landscapeWeek() throws {
        let (_, m) = try week(width: 834)
        #expect(!m.aggregatesHRRR && m.points.count == 45 + 33)
        let g = ChartGeometry(model: m, style: .phoneLandscapeWeek, width: 834)
        compareMixed(try SVG("l7"), g)
    }

    @Test("Slot rule: under 4 pt per hour the whole chart is 3-hourly") func slotRule() throws {
        let f = try Fixture.forecast()
        func agg(_ w: CGFloat) -> Bool { ChartModel(forecast: f, now: f.start, window: .week, scheme: .dark, plotWidth: w).aggregatesHRRR }
        #expect(agg(402) && agg(575) && !agg(576) && !agg(834))
        // Without NBM the 7-day chart is the HRRR hours (402 / 45 ≥ 4: hourly) and says so at the edge.
        var bare = f
        bare.extended = nil
        let m = ChartModel(forecast: bare, now: f.start, window: .week, scheme: .dark, plotWidth: 402)
        #expect(m.slotCount == 45 && m.points.count == 45 && m.seamSlot == nil && m.nbmUnavailable && m.horizonEdgeSlot == 45)
        #expect(ChartGeometry(model: m, style: .phonePortraitWeek, width: 402).edgeLabel == "ends Fri 5am · NBM unavailable")
    }

    @Test("HRRR owns its hours: NBM never appears before the seam") func hrrrOwnsItsHours() throws {
        let (f, m) = try week(width: 402)
        #expect(m.points.filter(\.isNBM).allSatisfy { $0.index >= f.hours.count })
        #expect(m.points.filter { !$0.isNBM }.allSatisfy { $0.index + $0.span <= f.hours.count })
        // 48 h and the watch never see NBM.
        for w in [ChartWindow.all, .next12, .next6] {
            #expect(ChartModel(forecast: f, now: f.start, window: w, scheme: .dark).points.allSatisfy { !$0.isNBM })
        }
        // An `extended` that would overlap HRRR is dropped on decode.
        var p = try Fixture.payload()
        p.extended?.from -= 3 * 3600
        #expect(Forecast(payload: p, isDefault: true).extended == nil)
        // Missing or null `extended`, sky and temperature decode as nil.
        var obj = try #require(try JSONSerialization.jsonObject(with: Fixture.data()) as? [String: Any])
        obj["extended"] = NSNull()
        obj.removeValue(forKey: "temp")
        obj.removeValue(forKey: "cloud")
        let bare = Forecast(payload: try Payload.decode(try JSONSerialization.data(withJSONObject: obj)), isDefault: true)
        #expect(bare.extended == nil && bare.hours[15].tempC == nil && bare.hours[15].cloud == nil && bare.hours[15].precip == 1.2)
        #expect(ChartModel(forecast: bare, now: bare.start, window: .all, scheme: .dark).skyCells.isEmpty)
    }

    @Test("Extended decodes into 3-hour blocks with its own run label") func extendedDecodes() throws {
        let f = try Fixture.forecast()
        let e = try #require(f.extended)
        #expect(e.blocks.count == 33 && e.step == 3 && e.run == "NBM 13Z")
        #expect(e.from == f.date(ofHour: 45) && e.end == f.date(ofHour: 144))
        #expect(e.blocks[10].wind.kn == 18 && e.blocks[10].wind.gust == 32 && e.blocks[10].start == f.date(ofHour: 75))
        #expect(Derivations.weekTitle(forecast: f) == "Wed 9am → Tue 9am")
        #expect(Derivations.weekEndLabel(forecast: f) == "ends Tue 9am")
        #expect(Derivations.weekSubtitle(forecast: f) == "HRRR hourly · NBM 3-hourly after Fri 5am")
        #expect(Derivations.weekTableCaption(forecast: f, now: f.start) == "7 days · NBM after Fri 5am")
        #expect(Derivations.nbmTableHeader(forecast: f) == "NBM from Fri 6am · 3-hourly")
    }

    @Test("Peak chip: 48 h names the hour; 7 d reads across the range and tags NBM") func peakChip() throws {
        let f = try Fixture.forecast()
        let now = f.start.addingTimeInterval(1500)
        #expect(Derivations.peakText(forecast: f, chart: nil, now: now) == "peak G25 · 12am")
        let all = ChartModel(forecast: f, now: now, window: .all, scheme: .dark)
        #expect(Derivations.peakText(forecast: f, chart: all, now: now) == "peak G25 · 12am")
        let wk = ChartModel(forecast: f, now: now, window: .week, scheme: .dark, plotWidth: 402)
        #expect(Derivations.peakText(forecast: f, chart: wk, now: now) == "peak G32 · Sat 1pm · NBM")
        #expect(Derivations.peakSpoken(forecast: f, chart: wk, now: now) == "peak gust 32, Sat 1pm, NBM")
        // Thursday afternoon, the 48 h peak (Thu 12am) is behind; a later peak would carry its day.
        let late = f.date(ofHour: 30)
        #expect(Derivations.peakText(forecast: f, chart: nil, now: late) == "peak G25 · Thu 12am")
    }

    @Test("Spans, sky detail and temperature") func readoutText() throws {
        let la = Fixture.la
        #expect(TimeFormat.span(Fixture.la(2026, 10, 24, 12), hours: 3, tz: la) == "Sat 12–3pm")
        #expect(TimeFormat.span(Fixture.la(2026, 10, 24, 9), hours: 3, tz: la) == "Sat 9am–12pm")
        #expect(TimeFormat.span(Fixture.la(2026, 10, 24, 21), hours: 3, tz: la) == "Sat 9pm–12am")
        #expect(TimeFormat.span(Fixture.la(2026, 10, 25, 0), hours: 3, tz: la) == "Sun 12–3am")
        let f = try Fixture.forecast()
        let h = f.hours[15]
        #expect(Derivations.skyDetail(h, unit: .fahrenheit) == "Overcast · rain · 46°F")
        #expect(Derivations.skyDetail(h, unit: .celsius) == "Overcast · rain · 8°C")
        #expect(Derivations.skyDetailSpoken(h, unit: .fahrenheit) == "overcast, rain, 46 degrees Fahrenheit")
        #expect(Derivations.skyDetail(f.hours[0], unit: .fahrenheit) == "Clear · 50°F")
        #expect(Derivations.skyDetail(Forecast.Hour(kn: 1, gust: 2, dirFrom: 0), unit: .fahrenheit) == nil)
        #expect([0.0, 0.1, 0.5, 1.4, 1.5].map { Rain(mmPerHour: $0).ticks } == [0, 1, 2, 2, 3])
        #expect([24, 25, 69, 70].map { SkyCondition(cloud: $0) } == [.clear, .partlyCloudy, .partlyCloudy, .overcast])
        #expect(TemperatureUnit.fahrenheit.degrees(celsius: -40) == -40 && TemperatureUnit.fahrenheit.degrees(celsius: 0) == 32)
    }

    @Test("sky48: the band's cells and rain ticks (402 wide, 45 h)") func skyBand() throws {
        let f = try Fixture.forecast()
        let m = ChartModel(forecast: f, now: f.start, window: .all, scheme: .dark)
        let g = ChartGeometry(model: m, style: .phonePortrait, width: 402)
        let svg = try SVG("sky48")
        let rects = svg.skyRects
        #expect(rects.count == m.skyCells.count && rects.count == 15)
        for (r, c) in zip(rects, m.skyCells) {
            let mine = g.skyRect(c)
            #expect(close(r.x, mine.minX) && close(r.w, mine.width), "sky cell \(c.slot)")
            let expected: (String, Double) = switch c.sky {
            case .clear: ("#FFB340", 0.22)
            case .partlyCloudy: ("#9AA4B1", 0.28)
            case .overcast: ("#9AA4B1", 0.6)
            }
            #expect(r.fill == expected.0 && abs(r.opacity - expected.1) < 1e-9, "sky tone \(c.slot)")
        }
        let ticks = svg.rainTicks
        let mine = m.skyCells.flatMap { g.rainTickXs($0) }
        #expect(ticks.count == mine.count)
        for (t, x) in zip(ticks, mine) { #expect(close(t, x)) }
        // 7 d: the HRRR cells, then one per NBM block.
        let wk = ChartModel(forecast: f, now: f.start, window: .week, scheme: .dark, plotWidth: 402)
        #expect(wk.skyCells.count == 15 + 33 && wk.skyCells[15].slot == 45 && wk.skyCells[15].hours == 3)
    }

    @Test("Sun markers: sunrise filled, sunset ring, on every chart") func sunMarkers() throws {
        let f = try Fixture.forecast()
        let m = ChartModel(forecast: f, now: f.start.addingTimeInterval(0.4 * 3600), window: .all, scheme: .dark)
        #expect(m.sunEvents.map(\.isRise) == [false, true, false])
        let g = ChartGeometry(model: m, style: .phonePortrait, width: 402)
        #expect(g.sunsetRingRadius == 2.25)
        let svg = try SVG("phonebig")
        #expect(svg.suns.map(\.isRise) == g.sunMarks.map(\.isRise))
        let watch = ChartModel(forecast: f, now: f.start.addingTimeInterval(0.4 * 3600), window: .next12, scheme: .dark)
        let wg = ChartGeometry(model: watch, style: .watchStrip, width: 198)
        #expect(try SVG("watch12").suns.map(\.isRise) == wg.sunMarks.map(\.isRise) && wg.sunsetRingRadius == 2.125)
        // 7 d has a rise and a set every day, computed past the payload's three days.
        let wk = ChartModel(forecast: f, now: f.start, window: .week, scheme: .dark, plotWidth: 402)
        #expect(wk.sunEvents.filter(\.isRise).count == 6 && wk.sunEvents.filter { !$0.isRise }.count == 6)
    }

    @Test("Solar port matches the server's sun days") func solar() throws {
        let f = try Fixture.forecast()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = f.timeZone
        for day in f.sun {
            let computed = Solar.day(lat: f.location.lat, lon: f.location.lon, midnight: cal.startOfDay(for: day.sunrise))
            #expect(abs(computed.sunrise.timeIntervalSince(day.sunrise)) < 90)
            #expect(abs(computed.sunset.timeIntervalSince(day.sunset)) < 90)
            #expect(abs(computed.civilDawn.timeIntervalSince(day.civilDawn)) < 90)
            #expect(abs(computed.civilDusk.timeIntervalSince(day.civilDusk)) < 90)
        }
        #expect(f.sunDays(through: f.date(ofHour: 144)).count == 7)
    }
}
