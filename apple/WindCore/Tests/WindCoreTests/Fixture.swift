import Foundation
import Testing
@testable import WindCore

/// Shared access to `payload-reference.json` (a copy of `fixtures/payload-reference.json`).
enum Fixture {
    static let la = TimeZone(identifier: "America/Los_Angeles")!
    static let utc = TimeZone(identifier: "UTC")!

    static func data() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "payload-reference", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    static func payload() throws -> Payload {
        try Payload.decode(try data())
    }

    static func forecast(isDefault: Bool = true) throws -> Forecast {
        Forecast(payload: try payload(), isDefault: isDefault)
    }

    /// A local date in America/Los_Angeles.
    static func la(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0, _ s: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = la
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }
}
