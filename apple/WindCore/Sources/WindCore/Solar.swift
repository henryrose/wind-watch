import Foundation

/// Sunrise, sunset and civil twilight on the device: a port of `server/src/sun.ts` (the NOAA
/// solar position algorithm). The payload's `sun` covers the HRRR hours only; the 7-day chart
/// (spec §12a: "sun markers every day") fills the days after it from here.
public enum Solar {
    private static let rad = Double.pi / 180
    private static let zenithRiseSet = 90.833
    private static let zenithCivil = 96.0

    /// Declination (degrees) and equation of time (minutes) at a unix instant.
    static func params(_ unix: Double) -> (decl: Double, eqTime: Double) {
        let jd = unix / 86400 + 2440587.5
        let t = (jd - 2451545) / 36525
        let l0 = norm360(280.46646 + t * (36000.76983 + t * 0.0003032))
        let m = norm360(357.52911 + t * (35999.05029 - 0.0001537 * t))
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sin(m * rad) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * m * rad) * (0.019993 - 0.000101 * t)
            + sin(3 * m * rad) * 0.000289
        let omega = 125.04 - 1934.136 * t
        let lambda = l0 + c - 0.00569 - 0.00478 * sin(omega * rad)
        let eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let eps = eps0 + 0.00256 * cos(omega * rad)
        let decl = asin(sin(eps * rad) * sin(lambda * rad)) / rad
        let y = pow(tan(eps / 2 * rad), 2)
        let eq = 4 / rad * (y * sin(2 * l0 * rad) - 2 * e * sin(m * rad)
            + 4 * e * y * sin(m * rad) * cos(2 * l0 * rad)
            - 0.5 * y * y * sin(4 * l0 * rad) - 1.25 * e * e * sin(2 * m * rad))
        return (decl, eq)
    }

    private static func norm360(_ d: Double) -> Double { (d.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }
    private static func norm180(_ d: Double) -> Double { let n = norm360(d); return n > 180 ? n - 360 : n }

    private static func hourAngle(_ unix: Double, lon: Double) -> Double {
        let minutes = (unix.truncatingRemainder(dividingBy: 86400) + 86400).truncatingRemainder(dividingBy: 86400) / 60
        return norm180((minutes + params(unix).eqTime + 4 * lon) / 4 - 180)
    }

    private static func solve(_ guess: Double, lon: Double, target: Double) -> Double {
        var t = guess
        for _ in 0..<3 { t += norm180(target - hourAngle(t, lon: lon)) * 240 }
        return t
    }

    private static func halfArc(_ unix: Double, lat: Double, zenith: Double) -> Double {
        let decl = params(unix).decl
        let cosHA = cos(zenith * rad) / (cos(lat * rad) * cos(decl * rad)) - tan(lat * rad) * tan(decl * rad)
        if cosHA >= 1 { return 0 }
        if cosHA <= -1 { return 180 }
        return acos(cosHA) / rad
    }

    private static func event(noon: Double, lon: Double, arc: Double, sign: Double) -> Double {
        if arc <= 0 { return noon }
        if arc >= 180 { return noon + sign * 12 * 3600 }
        return solve(noon + sign * arc * 240, lon: lon, target: sign * arc)
    }

    /// Sun events for the local civil day that begins at `midnight` (same ordering guarantees as
    /// the server: dawn ≤ rise ≤ set ≤ dusk).
    public static func day(lat: Double, lon: Double, midnight: Date) -> Forecast.SunDay {
        let noon = solve(midnight.timeIntervalSince1970 + 12 * 3600, lon: lon, target: 0)
        let arc = halfArc(noon, lat: lat, zenith: zenithRiseSet)
        let rise = event(noon: noon, lon: lon, arc: arc, sign: -1).rounded()
        let set = max(event(noon: noon, lon: lon, arc: arc, sign: 1).rounded(), rise)
        let civil = max(halfArc(noon, lat: lat, zenith: zenithCivil), arc)
        let dawn = min(event(noon: noon, lon: lon, arc: civil, sign: -1).rounded(), rise)
        let dusk = max(event(noon: noon, lon: lon, arc: civil, sign: 1).rounded(), set)
        func d(_ x: Double) -> Date { Date(timeIntervalSince1970: x) }
        return Forecast.SunDay(civilDawn: d(dawn), sunrise: d(rise), sunset: d(set), civilDusk: d(dusk))
    }
}

extension Forecast {
    /// The payload's sun days, followed by computed days for every local day up to `end` that the
    /// payload does not cover (the payload stops at the HRRR horizon).
    public func sunDays(through end: Date) -> [SunDay] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var days = sun
        let lastCovered = sun.last.map { cal.startOfDay(for: $0.sunrise) } ?? cal.startOfDay(for: start).addingTimeInterval(-86400)
        guard var day = cal.date(byAdding: .day, value: 1, to: lastCovered) else { return days }
        while day <= end {
            days.append(Solar.day(lat: location.lat, lon: location.lon, midnight: day))
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }
}
