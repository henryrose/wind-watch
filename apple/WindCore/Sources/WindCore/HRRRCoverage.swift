import Foundation

/// The HRRR CONUS grid (NCEP): Lambert conformal on a 6 371 229 m sphere, tangent at 38.5°N,
/// centre meridian 97.5°W, 1799 × 1059 cells of 3 km with the first cell at 21.138123°N
/// 122.719528°W. A point is covered when it projects inside the grid; Open-Meteo answers
/// "No data is available for this location" everywhere else (checked 2026-10-22 against points
/// 2 cells inside and 3 cells outside each edge). The server stays the authority; this lets the
/// Location screen refuse a point before offering Save, offline too.
public enum HRRRCoverage {
    static let radius = 6_371_229.0
    static let tangentLat = 38.5
    static let centreLon = -97.5
    static let firstLat = 21.138123
    static let firstLon = -122.719528
    static let cellSize = 3000.0
    static let columns = 1799
    static let rows = 1059

    /// Shown when a point is outside the grid.
    public static let outsideText = "HRRR covers the continental US and nearby Canada and Mexico only. Pick a point inside it."

    public static func contains(lat: Double, lon: Double) -> Bool {
        guard let cell = gridPosition(lat: lat, lon: lon) else { return false }
        return (0...Double(columns - 1)).contains(cell.x) && (0...Double(rows - 1)).contains(cell.y)
    }

    /// Fractional (column, row) of a point, (0, 0) at the first cell; nil at the poles.
    static func gridPosition(lat: Double, lon: Double) -> (x: Double, y: Double)? {
        guard abs(lat) < 89.9, let p = project(lat: lat, lon: lon), let o = project(lat: firstLat, lon: firstLon) else { return nil }
        return ((p.x - o.x) / cellSize, (p.y - o.y) / cellSize)
    }

    /// The grid cell a point is forecast from, as the server asks for it: the point rounded to
    /// 2 dp (`WindClient.url`), then Open-Meteo's nearest cell. `corners` run SW, SE, NE, NW.
    public struct Cell: Sendable, Equatable {
        public var lat: Double
        public var lon: Double
        public var corners: [(lat: Double, lon: Double)]

        public static func == (a: Cell, b: Cell) -> Bool {
            a.lat == b.lat && a.lon == b.lon && a.corners.elementsEqual(b.corners) { $0 == $1 }
        }
    }

    /// Nil outside the grid.
    public static func cell(lat: Double, lon: Double) -> Cell? {
        let rLat = (lat * 100).rounded() / 100
        let rLon = (lon * 100).rounded() / 100
        guard contains(lat: rLat, lon: rLon), let pos = gridPosition(lat: rLat, lon: rLon) else { return nil }
        let col = pos.x.rounded(), row = pos.y.rounded()
        guard let centre = unproject(col: col, row: row) else { return nil }
        let corners = [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)].compactMap { unproject(col: col + $0.0, row: row + $0.1) }
        return Cell(lat: centre.lat, lon: centre.lon, corners: corners)
    }

    /// `HRRR cell 1.1 km NE` (distance and 8-point bearing from the pin to the cell centre), or
    /// `HRRR cell at pin` under 0.3 km (location-naming §3.6). Nil outside the grid.
    public static func forecastPointText(lat: Double, lon: Double) -> String? {
        guard let cell = cell(lat: lat, lon: lon) else { return nil }
        let km = distanceKm(lat, lon, cell.lat, cell.lon)
        guard km >= 0.3 else { return "HRRR cell at pin" }
        let bearing = Int(initialBearing(lat, lon, cell.lat, cell.lon).rounded())
        return String(format: "HRRR cell %.1f km ", km) + Compass.points[Compass.sectorIndex(degrees: bearing)]
    }

    static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let rad = Double.pi / 180
        let dLat = (lat2 - lat1) * rad, dLon = (lon2 - lon1) * rad
        let a = pow(sin(dLat / 2), 2) + cos(lat1 * rad) * cos(lat2 * rad) * pow(sin(dLon / 2), 2)
        return 2 * radius / 1000 * asin(min(1, sqrt(a)))
    }

    static func initialBearing(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let rad = Double.pi / 180
        let y = sin((lon2 - lon1) * rad) * cos(lat2 * rad)
        let x = cos(lat1 * rad) * sin(lat2 * rad) - sin(lat1 * rad) * cos(lat2 * rad) * cos((lon2 - lon1) * rad)
        let deg = atan2(y, x) / rad
        return deg < 0 ? deg + 360 : deg
    }

    /// Inverse of `project` for a fractional (column, row).
    static func unproject(col: Double, row: Double) -> (lat: Double, lon: Double)? {
        guard let o = project(lat: firstLat, lon: firstLon) else { return nil }
        let rad = Double.pi / 180
        let phi1 = tangentLat * rad
        let n = sin(phi1)
        let f = cos(phi1) * pow(tan(.pi / 4 + phi1 / 2), n) / n
        let rho0 = radius * f / pow(tan(.pi / 4 + phi1 / 2), n)
        let x = o.x + col * cellSize
        let y = o.y + row * cellSize
        let rho = (n < 0 ? -1.0 : 1.0) * sqrt(x * x + (rho0 - y) * (rho0 - y))
        let theta = atan2(x, rho0 - y)
        let lat = (2 * atan(pow(radius * f / rho, 1 / n)) - .pi / 2) / rad
        var lon = centreLon + theta / n / rad
        if lon > 180 { lon -= 360 }
        if lon < -180 { lon += 360 }
        return (lat, lon)
    }

    private static func project(lat: Double, lon: Double) -> (x: Double, y: Double)? {
        let rad = Double.pi / 180
        let phi1 = tangentLat * rad
        let n = sin(phi1)
        let f = cos(phi1) * pow(tan(.pi / 4 + phi1 / 2), n) / n
        let rho = radius * f / pow(tan(.pi / 4 + lat * rad / 2), n)
        let rho0 = radius * f / pow(tan(.pi / 4 + phi1 / 2), n)
        var dLon = lon - centreLon
        if dLon > 180 { dLon -= 360 }
        if dLon < -180 { dLon += 360 }
        let theta = n * dLon * rad
        guard rho.isFinite else { return nil }
        return (rho * sin(theta), rho0 - rho * cos(theta))
    }
}

extension SavedLocation {
    /// True when the point is inside the HRRR grid (`HRRRCoverage`).
    public var isInHRRRCoverage: Bool { HRRRCoverage.contains(lat: lat, lon: lon) }
}
