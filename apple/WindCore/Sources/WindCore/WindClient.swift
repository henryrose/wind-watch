import Foundation

/// A user-chosen location sent to the Worker as `?lat=&lon=` (rounded to 2 dp; the server snaps).
public struct CustomLocation: Codable, Sendable, Hashable {
    public var lat: Double
    public var lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

public enum WindClientError: Error, Equatable, Sendable {
    /// Non-200/304 status.
    case http(Int)
    /// The response was not an HTTP response.
    case invalidResponse
}

/// Outcome of one `GET /v1/wind`.
public enum FetchResult: Sendable {
    /// 200 with a payload that decoded and validated. `etag` is the response's `ETag`, if any.
    case updated(data: Data, etag: String?)
    /// 304: the etag we sent still matches.
    case notModified
    /// Transport error, non-2xx status, or an undecodable body.
    case failed(Error)

    public var isUpdated: Bool { if case .updated = self { true } else { false } }
}

/// Minimal client for the Worker's `GET /v1/wind` (DESIGN §4). No retries, no caching of its own.
public final class WindClient: Sendable {
    public let baseURL: URL
    public let session: URLSession
    public let timeout: TimeInterval
    /// Sent as `X-WW-Client` so the Worker can count requests per surface (server/src/usage.ts).
    public let clientTag: String?

    /// - Parameters:
    ///   - baseURL: the API base from configuration (e.g. `https://<name>.workers.dev`), no path.
    ///   - session: injectable for tests (`URLProtocol` stubs).
    ///   - timeout: per-request, seconds (DESIGN §5.2 uses 10 s).
    ///   - clientTag: `<surface>/<version>`, usually from `WindClient.clientTag(bundleInfo:)`.
    public init(baseURL: URL, session: URLSession = .shared, timeout: TimeInterval = 10, clientTag: String? = nil) {
        self.baseURL = baseURL
        self.session = session
        self.timeout = timeout
        self.clientTag = clientTag
    }

    public static let clientHeader = "X-WW-Client"

    /// `ios|watch|widget/<short version>+<build>` from the target's Info.plist. The surface comes
    /// from the bundle id suffix (`.windwatch`, `.watchkitapp`, `.complications`).
    public static func clientTag(bundleInfo: [String: Any]) -> String {
        let id = bundleInfo["CFBundleIdentifier"] as? String ?? ""
        let surface: String
        if id.hasSuffix(".complications") { surface = "widget" }
        else if id.hasSuffix(".watchkitapp") { surface = "watch" }
        else if id.hasSuffix(".windwatch") { surface = "ios" }
        else { surface = "other" }
        let version = bundleInfo["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundleInfo["CFBundleVersion"] as? String ?? "?"
        return "\(surface)/\(version)+\(build)"
    }

    /// The request URL for the default or a custom location.
    public func url(location: CustomLocation?) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/wind"), resolvingAgainstBaseURL: false)!
        if let location {
            components.queryItems = [
                URLQueryItem(name: "lat", value: String(format: "%.2f", location.lat)),
                URLQueryItem(name: "lon", value: String(format: "%.2f", location.lon)),
            ]
        }
        return components.url!
    }

    /// The exact request sent by `fetch`.
    public func request(ifNoneMatch etag: String?, location: CustomLocation?) -> URLRequest {
        var request = URLRequest(url: url(location: location))
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        // ETags are handled here, not by URLSession's cache; never let it synthesise a 200 from a 304.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let clientTag {
            request.setValue(clientTag, forHTTPHeaderField: Self.clientHeader)
        }
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        return request
    }

    /// One attempt. 200 → `.updated` (after `Payload.decode` succeeds), 304 → `.notModified`,
    /// anything else → `.failed`.
    public func fetch(ifNoneMatch etag: String?, location: CustomLocation? = nil) async -> FetchResult {
        let request = request(ifNoneMatch: etag, location: location)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .failed(error)
        }
        guard let http = response as? HTTPURLResponse else {
            return .failed(WindClientError.invalidResponse)
        }
        switch http.statusCode {
        case 200:
            do {
                _ = try Payload.decode(data)
            } catch {
                return .failed(error)
            }
            return .updated(data: data, etag: http.value(forHTTPHeaderField: "ETag"))
        case 304:
            return .notModified
        default:
            return .failed(WindClientError.http(http.statusCode))
        }
    }
}
