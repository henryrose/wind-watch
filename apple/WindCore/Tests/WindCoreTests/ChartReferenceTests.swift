import Foundation
import Testing
@testable import WindCore

/// `ChartGeometry` against the SVG fragments `chart_reference.py` produced for the reference
/// payload (`docs/design/reference/charts/*.svg`). Every number the reference emits — bar
/// rectangles, gust vertices, caps, sun dots, gridlines, now and edge rules, gradient stops —
/// must come out of the port within rounding (the SVG prints one decimal).
@Suite("Chart reference SVGs")
struct ChartReferenceTests {
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

        /// Bars: `<rect x y width height rx fill="#…"/>` (the shading rect has a url fill and no rx).
        var bars: [(x: Double, y: Double, w: Double, h: Double)] {
            numbers(##"<rect x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" height="([\d.]+)" rx="[\d.]+" fill="#"##).map { ($0[0], $0[1], $0[2], $0[3]) }
        }
        var gustVertices: [(Double, Double)] {
            let re = try! NSRegularExpression(pattern: ##"<polyline points="([^"]+)""##)
            guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let r = Range(m.range(at: 1), in: text) else { return [] }
            return text[r].split(separator: " ").map { pair in
                let xy = pair.split(separator: ",").compactMap { Double($0) }
                return (xy[0], xy[1])
            }
        }
        var caps: [(x1: Double, x2: Double, y: Double)] {
            numbers(##"<line x1="([\d.]+)" x2="([\d.]+)" y1="([\d.]+)" y2="[\d.]+" stroke="#FFFFFF" stroke-width="[\d.]+" stroke-linecap="round"/>"##).map { ($0[0], $0[1], $0[2]) }
        }
        var sunDots: [(Double, Double)] { numbers(##"<circle cx="([\d.]+)" cy="([\d.-]+)""##).map { ($0[0], $0[1]) } }
        var gridlines: [Double] { numbers(##"<line x1="0" x2="[\d.]+" y1="([\d.]+)" y2="[\d.]+" stroke="#FFFFFF" stroke-opacity="0.12""##).map { $0[0] } }
        var gridLabels: [(x: Double, y: Double)] { numbers(##"<text x="([\d.]+)" y="([\d.]+)" text-anchor="end" font-size="\d+" fill="#FFFFFF" fill-opacity="0.45""##).map { ($0[0], $0[1]) } }
        var nowRule: (x: Double, y1: Double, y2: Double)? { numbers(##"<line x1="([\d.]+)" x2="[\d.]+" y1="([\d.-]+)" y2="([\d.]+)" stroke="#FFFFFF" stroke-width="1.5"/>"##).last.map { ($0[0], $0[1], $0[2]) } } // the selection rule shares the shape and precedes it
        var edgeRule: (x: Double, y1: Double, y2: Double)? { numbers(##"<line x1="([\d.]+)" x2="[\d.]+" y1="([\d.-]+)" y2="([\d.]+)" stroke="#FFFFFF" stroke-opacity="0.7" stroke-width="1" stroke-dasharray="3 3"/>"##).first.map { ($0[0], $0[1], $0[2]) } }
        var stops: [(Double, Double)] { numbers(##"<stop offset="([\d.]+)" stop-color="#FFFFFF" stop-opacity="([\d.]+)"/>"##).map { ($0[0], $0[1]) } }
        var arrows: [(x: Double, y: Double, rot: Double)] { numbers(##"<g transform="translate\(([\d.]+),([\d.]+)\) rotate\((\d+)\)">"##).map { ($0[0], $0[1], $0[2]) } }
        var ticks: [Double] { numbers(##"<line x1="([\d.]+)" x2="[\d.]+" y1="[\d.]+" y2="[\d.]+" stroke="#FFFFFF" stroke-opacity="0.5" stroke-width="1"/>"##).map { $0[0] } }
        /// Day-band names: `<text x y font-size font-weight="700" fill="#FFFFFF" fill-opacity="0.75">`.
        var dayLabels: [(x: Double, name: String)] {
            let re = try! NSRegularExpression(pattern: ##"<text x="([\d.]+)" y="[\d.-]+" font-size="\d+" font-weight="700" fill="#FFFFFF" fill-opacity="0.75"[^>]*>(\w+)</text>"##)
            return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
                guard let xr = Range(m.range(at: 1), in: text), let nr = Range(m.range(at: 2), in: text), let x = Double(text[xr]) else { return nil }
                return (x, String(text[nr]))
            }
        }
        var dayDividers: [Double] { numbers(##"<line x1="([\d.]+)" x2="[\d.]+" y1="[\d.-]+" y2="[\d.]+" stroke="#FFFFFF" stroke-opacity="0.28""##).map { $0[0] } }
        var selectionOutline: (x: Double, y: Double, w: Double, h: Double)? { numbers(##"<rect x="([\d.-]+)" y="([\d.]+)" width="([\d.]+)" height="([\d.]+)" rx="2.5" fill="none""##).first.map { ($0[0], $0[1], $0[2], $0[3]) } }
    }

    /// `|a − b| ≤ 0.06 · scale` (the SVG prints to one decimal; watch files are 2× pixels).
    private func close(_ a: Double, _ b: Double, scale: Double = 1, tolerance: Double = 0.06) -> Bool {
        abs(a - b * scale) <= tolerance * scale + 1e-9
    }

    /// `checkY` is off when the reference pinned a different y domain than the §6.1 rule
    /// (the `watchstrip` call left `ymax=30`; the rule gives 20 for hours 0–11).
    private func compare(_ svg: SVG, _ g: ChartGeometry, scale: Double, checkY: Bool = true, sourceLocation: SourceLocation = #_sourceLocation) {
        let m = g.model
        let u = Double(g.unit)
        let bars = svg.bars
        #expect(bars.count == m.points.count, sourceLocation: sourceLocation)
        for (svgBar, p) in zip(bars, m.points) {
            let r = g.barRect(p)
            #expect(close(svgBar.x, r.minX, scale: scale), "bar x \(p.index)", sourceLocation: sourceLocation)
            #expect(close(svgBar.w, r.width, scale: scale), "bar w \(p.index)", sourceLocation: sourceLocation)
            if checkY {
                #expect(close(svgBar.y, r.minY, scale: scale), "bar y \(p.index)", sourceLocation: sourceLocation)
                #expect(close(svgBar.h, r.height, scale: scale), "bar h \(p.index)", sourceLocation: sourceLocation)
            }
        }
        let verts = svg.gustVertices
        #expect(verts.count == m.points.count, sourceLocation: sourceLocation)
        for (v, p) in zip(verts, m.points) {
            let pt = g.gustPoint(p)
            #expect(close(v.0, pt.x, scale: scale) && (!checkY || close(v.1, pt.y, scale: scale)), "gust \(p.index)", sourceLocation: sourceLocation)
        }
        let caps = svg.caps
        #expect(caps.count == m.points.count, sourceLocation: sourceLocation)
        for (c, p) in zip(caps, m.points) {
            let pt = g.gustPoint(p)
            #expect(close(c.x2 - c.x1, g.capWidth, scale: scale, tolerance: 0.11), "cap width \(p.index)", sourceLocation: sourceLocation)
            #expect(close((c.x1 + c.x2) / 2, pt.x, scale: scale) && (!checkY || close(c.y, pt.y, scale: scale)), "cap \(p.index)", sourceLocation: sourceLocation)
        }
        let suns = svg.sunDots
        #expect(suns.count == g.sunPoints.count, sourceLocation: sourceLocation)
        for (s, pt) in zip(suns, g.sunPoints) {
            // The fixture's Thursday sunrise is 07:41; the reference script used 07:40 (one minute = 0.017 slot).
            #expect(close(s.0, pt.x, scale: scale, tolerance: 0.3) && close(s.1, pt.y, scale: scale), "sun", sourceLocation: sourceLocation)
        }
        let grid = svg.gridlines
        if checkY { #expect(grid.count == g.gridValues.count, sourceLocation: sourceLocation) }
        for (yy, v) in zip(grid, g.gridValues) where checkY {
            #expect(close(yy, g.y(Double(v)), scale: scale), "grid \(v)", sourceLocation: sourceLocation)
        }
        for (label, v) in zip(svg.gridLabels, g.gridValues) where checkY {
            #expect(close(label.x, g.width - 2 * u, scale: scale) && close(label.y, g.y(Double(v)) - 3 * u, scale: scale), "grid label \(v)", sourceLocation: sourceLocation)
        }
        if let now = svg.nowRule {
            let x = try? #require(g.nowX)
            #expect(close(now.x, Double(x ?? -1), scale: scale), "now x", sourceLocation: sourceLocation)
            #expect(close(now.y1, g.plotTop - 6 * u, scale: scale) && close(now.y2, g.plotBottom, scale: scale), "now extent", sourceLocation: sourceLocation)
        } else {
            #expect(g.nowX == nil, sourceLocation: sourceLocation)
        }
        if let edge = svg.edgeRule {
            #expect(close(edge.x, Double(g.edgeX ?? -1), scale: scale), "edge x", sourceLocation: sourceLocation)
            #expect(close(edge.y1, g.plotTop - 6 * u, scale: scale) && close(edge.y2, g.plotBottom, scale: scale), "edge extent", sourceLocation: sourceLocation)
        }
        let stops = svg.stops
        let mine = m.twilightStops
        #expect(stops.count == mine.count, sourceLocation: sourceLocation)
        for (s, t) in zip(stops, mine) {
            #expect(abs(s.0 - t.fraction) < 0.0015, "stop fraction", sourceLocation: sourceLocation)
            #expect(abs(s.1 - 0.07 * t.value) < 0.002, "stop alpha", sourceLocation: sourceLocation)
        }
        let arrows = svg.arrows
        #expect(arrows.count == g.arrowPoints.count, sourceLocation: sourceLocation)
        for (a, p) in zip(arrows, g.arrowPoints) {
            #expect(close(a.x, g.centreX(index: p.index), scale: scale) && close(a.y, g.arrowY, scale: scale), "arrow \(p.index)", sourceLocation: sourceLocation)
            #expect(a.rot == Compass.arrowRotation(dirFrom: p.dirFrom), "arrow rotation \(p.index)", sourceLocation: sourceLocation)
        }
        let ticks = svg.ticks
        #expect(ticks.count == g.tickPoints.count, sourceLocation: sourceLocation)
        for (t, p) in zip(ticks, g.tickPoints) {
            #expect(close(t, g.centreX(index: p.index), scale: scale), "tick \(p.index)", sourceLocation: sourceLocation)
        }
        let dividers = svg.dayDividers
        let mineDividers = g.dayMarks.filter(\.divider)
        #expect(dividers.count == mineDividers.count, sourceLocation: sourceLocation)
        for (d, mark) in zip(dividers, mineDividers) {
            #expect(close(d, mark.x, scale: scale), "day divider", sourceLocation: sourceLocation)
        }
        let labels = svg.dayLabels
        #expect(labels.count == g.dayMarks.count, sourceLocation: sourceLocation)
        for (l, mark) in zip(labels, g.dayMarks) {
            #expect(l.name == mark.name && close(l.x, mark.labelX, scale: scale), "day label \(mark.name): \(l.x) vs \(mark.labelX)", sourceLocation: sourceLocation)
        }
    }

    @Test("phonebig: iPhone portrait, 402×262, now 0.4") func phoneBig() throws {
        let f = try Fixture.forecast()
        let m = ChartModel(forecast: f, now: f.start.addingTimeInterval(0.4 * 3600), window: .all, scheme: .dark)
        let g = ChartGeometry(model: m, style: .phonePortrait, width: 402)
        #expect(g.slot == 402.0 / 45 && g.barWidth == 6.43 && g.capWidth == 8.43 && g.unit == 1)
        #expect(g.plotTop == 38 && g.plotBottom == 244 && g.boxHeight == 262)
        compare(try SVG("phonebig"), g, scale: 1)
        #expect(g.edgeLabel == "ends Fri 5am")
    }

    @Test("phonesel: selection at hour 15") func phoneSelected() throws {
        let f = try Fixture.forecast()
        let m = ChartModel(forecast: f, now: f.start.addingTimeInterval(0.4 * 3600), window: .all, scheme: .dark)
        let g = ChartGeometry(model: m, style: .phonePortrait, width: 402)
        let svg = try SVG("phonesel")
        compare(svg, g, scale: 1)
        let outline = try #require(svg.selectionOutline)
        let mine = g.selectionOutline(m.points[15])
        #expect(close(outline.x, mine.minX) && close(outline.y, mine.minY) && close(outline.w, mine.width) && close(outline.h, mine.height))
    }

    @Test("land: iPhone landscape, 834×296") func landscape() throws {
        let f = try Fixture.forecast()
        let m = ChartModel(forecast: f, now: f.start.addingTimeInterval(0.4 * 3600), window: .all, scheme: .dark)
        let g = ChartGeometry(model: m, style: .phoneLandscape, width: 834)
        #expect(g.boxHeight == 296)
        compare(try SVG("land"), g, scale: 1)
    }

    @Test("watch12: 12-h strip at 2× (396×230)") func watch12() throws {
        let f = try Fixture.forecast()
        let m = ChartModel(forecast: f, now: f.start.addingTimeInterval(0.4 * 3600), window: .next12, scheme: .dark)
        let g = ChartGeometry(model: m, style: .watchStrip, width: 198)
        #expect(g.boxHeight == 115 && g.unit == 0.5 && g.capWidth == g.barWidth + 1)
        compare(try SVG("watch12"), g, scale: 2, checkY: false)
        #expect(m.yMax == 20) // §6.1 rule over hours 0–11 (max gust 15); the reference script pinned 30
    }

    @Test("watch-short: 6 hours left, edge at slot 6") func watchShort() throws {
        let f = try Fixture.forecast()
        let m = ChartModel(forecast: f, now: f.start.addingTimeInterval(39.1 * 3600), window: .next12, scheme: .dark)
        let g = ChartGeometry(model: m, style: .watchStrip, width: 198)
        #expect(m.points.count == 6 && m.horizonEdgeSlot == 6)
        compare(try SVG("watch-short"), g, scale: 2)
        #expect(g.edgeLabel == "ends 05:00")
    }

    @Test("comp-rect46 / comp-rect42: rectangular complication strip at 2× (336×58, 300×50)", arguments: [
        ("comp-rect46", CGFloat(168), CGFloat(29)), ("comp-rect42", CGFloat(150), CGFloat(25)),
    ]) func complicationStrip(name: String, width: CGFloat, height: CGFloat) throws {
        let f = try Fixture.forecast()
        let m = ChartModel(forecast: f, now: f.date(ofHour: 15), window: .complication, scheme: .dark)
        let g = ChartGeometry(model: m, style: .complication(height: height), width: width)
        #expect(m.yMax == 25 && m.points.count == 12 && g.boxHeight == height && g.capWidth == g.barWidth + 1)
        let svg = try SVG(name)
        #expect(svg.bars.count == 12 && svg.gustVertices.count == 12 && svg.caps.count == 12)
        for (bar, p) in zip(svg.bars, m.points) {
            let r = g.barRect(p)
            #expect(close(bar.x, r.minX, scale: 2) && close(bar.w, r.width, scale: 2), "bar x \(p.index)")
            #expect(close(bar.y, r.minY, scale: 2) && close(bar.h, r.height, scale: 2), "bar y \(p.index)")
        }
        for (v, p) in zip(svg.gustVertices, m.points) {
            let pt = g.gustPoint(p)
            #expect(close(v.0, pt.x, scale: 2) && close(v.1, pt.y, scale: 2), "gust \(p.index)")
        }
        for (c, p) in zip(svg.caps, m.points) {
            #expect(close(c.x2 - c.x1, g.capWidth, scale: 2, tolerance: 0.11) && close(c.y, g.gustPoint(p).y, scale: 2), "cap \(p.index)")
        }
        // 0.5 pt ticks every 3 h (00/03/06/09) under the baseline.
        let ticks = svg.ticks
        #expect(ticks.count == g.tickPoints.count)
        for (x, p) in zip(ticks, g.tickPoints) { #expect(close(x, g.centreX(index: p.index), scale: 2)) }
        // No shading, sun markers, rules, arrows or grid on the rectangular (§6.3).
        #expect(svg.stops.allSatisfy { $0.1 == 0 } && g.sunMarks.isEmpty && g.nowX == nil && g.edgeX == nil)
        #expect(g.arrowPoints.isEmpty && g.gridValues.isEmpty)
    }
}
