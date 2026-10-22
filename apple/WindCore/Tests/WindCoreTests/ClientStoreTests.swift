import Foundation
import Testing
@testable import WindCore

// MARK: - URLProtocol stub

/// Scripted HTTP responses keyed by request host, so parallel tests never share a handler.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        var status: Int
        var headers: [String: String] = [:]
        var body: Data = Data()
        /// nil status → never respond (lets the client time out).
        static let silent = Response(status: 0)
    }

    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var handlers: [String: @Sendable (URLRequest) -> Response] = [:]
        var requests: [String: [URLRequest]] = [:]
    }

    private static let registry = Registry()

    static func register(host: String, _ handler: @escaping @Sendable (URLRequest) -> Response) {
        registry.lock.withLock { registry.handlers[host] = handler }
    }

    static func requests(host: String) -> [URLRequest] {
        registry.lock.withLock { registry.requests[host] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host() else { return false }
        return registry.lock.withLock { registry.handlers[host] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host() else { return }
        let handler = Self.registry.lock.withLock { () -> (@Sendable (URLRequest) -> Response)? in
            Self.registry.requests[host, default: []].append(request)
            return Self.registry.handlers[host]
        }
        guard let handler else { return }
        let response = handler(request)
        guard response.status > 0 else { return } // silent: let the timeout fire
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: response.headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

enum Stub {
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }

    /// A fresh host + client pair wired to the stub.
    static func client(timeout: TimeInterval = 10, _ handler: @escaping @Sendable (URLRequest) -> StubURLProtocol.Response) -> (host: String, client: WindClient) {
        let host = "t-\(UUID().uuidString.lowercased()).example"
        StubURLProtocol.register(host: host, handler)
        return (host, WindClient(baseURL: URL(string: "https://\(host)")!, session: session(), timeout: timeout))
    }

    static func tempStore() -> AppGroupStore {
        AppGroupStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("WindCoreTests-\(UUID().uuidString)", isDirectory: true))
    }
}

// MARK: - WindClient

@Suite("WindClient")
struct WindClientTests {
    @Test func okReturnsUpdatedWithEtag() async throws {
        let body = try Fixture.data()
        let (host, client) = Stub.client { _ in .init(status: 200, headers: ["ETag": "\"sha256-abc\"", "Content-Type": "application/json"], body: body) }
        let result = await client.fetch(ifNoneMatch: nil)
        guard case .updated(let data, let etag) = result else { Issue.record("expected .updated, got \(result)"); return }
        #expect(data == body)
        #expect(etag == "\"sha256-abc\"")
        let sent = try #require(StubURLProtocol.requests(host: host).first)
        #expect(sent.url?.path == "/v1/wind")
        #expect(sent.url?.query == nil)
        #expect(sent.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(sent.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(sent.httpMethod == "GET")
    }

    @Test func notModifiedCarriesIfNoneMatch() async throws {
        let (host, client) = Stub.client { _ in .init(status: 304) }
        let result = await client.fetch(ifNoneMatch: "\"sha256-abc\"")
        guard case .notModified = result else { Issue.record("expected .notModified, got \(result)"); return }
        let sent = try #require(StubURLProtocol.requests(host: host).first)
        #expect(sent.value(forHTTPHeaderField: "If-None-Match") == "\"sha256-abc\"")
    }

    @Test func serverErrorFails() async {
        let (_, client) = Stub.client { _ in .init(status: 500, body: Data("{\"error\":\"no_data\"}".utf8)) }
        let result = await client.fetch(ifNoneMatch: nil)
        guard case .failed(let error) = result else { Issue.record("expected .failed, got \(result)"); return }
        #expect(error as? WindClientError == .http(500))
    }

    @Test func outsideCoverageIsItsOwnError() async {
        let (_, client) = Stub.client { _ in .init(status: 422, body: Data("{\"error\":\"outside_coverage\"}".utf8)) }
        let result = await client.fetch(ifNoneMatch: nil, location: CustomLocation(lat: 51.5, lon: -0.12))
        guard case .failed(let error) = result else { Issue.record("expected .failed, got \(result)"); return }
        #expect(error as? WindClientError == .outsideCoverage)
    }

    @Test func invalidJSONFails() async {
        let (_, client) = Stub.client { _ in .init(status: 200, body: Data("not json".utf8)) }
        let result = await client.fetch(ifNoneMatch: nil)
        guard case .failed(let error) = result else { Issue.record("expected .failed, got \(result)"); return }
        #expect(error is DecodingError)
    }

    @Test func invalidPayloadFails() async throws {
        var p = try Fixture.payload()
        p.gust.removeLast()
        let body = try p.encoded()
        let (_, client) = Stub.client { _ in .init(status: 200, body: body) }
        let result = await client.fetch(ifNoneMatch: nil)
        guard case .failed(let error) = result else { Issue.record("expected .failed, got \(result)"); return }
        #expect(error as? Payload.ValidationError == .lengthMismatch(hours: 45, kn: 45, gust: 44, dir: 45))
    }

    @Test func customLocationQuery() async throws {
        let body = try Fixture.data()
        let (host, client) = Stub.client { _ in .init(status: 200, body: body) }
        _ = await client.fetch(ifNoneMatch: nil, location: CustomLocation(lat: 48.1, lon: -122.75))
        let sent = try #require(StubURLProtocol.requests(host: host).first)
        #expect(sent.url?.path == "/v1/wind")
        #expect(sent.url?.query == "lat=48.10&lon=-122.75")
        #expect(client.url(location: CustomLocation(lat: 48.0907, lon: -122.7773)).query == "lat=48.09&lon=-122.78")
    }

    @Test func baseURLWithTrailingSlash() {
        let client = WindClient(baseURL: URL(string: "https://example.test/")!)
        #expect(client.url(location: nil).absoluteString == "https://example.test/v1/wind")
    }

    @Test func timeoutFails() async {
        let (_, client) = Stub.client(timeout: 0.2) { _ in .silent }
        let result = await client.fetch(ifNoneMatch: nil)
        guard case .failed(let error) = result else { Issue.record("expected .failed, got \(result)"); return }
        #expect((error as? URLError)?.code == .timedOut)
    }

    @Test func requestUsesTimeoutAndNoCache() {
        let client = WindClient(baseURL: URL(string: "https://example.test")!, timeout: 7)
        let r = client.request(ifNoneMatch: "", location: nil)
        #expect(r.timeoutInterval == 7)
        #expect(r.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(r.value(forHTTPHeaderField: "If-None-Match") == nil) // empty etag not sent
        #expect(r.value(forHTTPHeaderField: WindClient.clientHeader) == nil) // no tag, no header
    }

    @Test func requestSendsClientTag() {
        let client = WindClient(baseURL: URL(string: "https://example.test")!, clientTag: "watch/0.1.0+1")
        let r = client.request(ifNoneMatch: nil, location: nil)
        #expect(r.value(forHTTPHeaderField: "X-WW-Client") == "watch/0.1.0+1")
    }

    @Test func clientTagFromBundleInfo() {
        func tag(_ id: String) -> String {
            WindClient.clientTag(bundleInfo: ["CFBundleIdentifier": id, "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "2"])
        }
        #expect(tag("com.x.windwatch") == "ios/0.1.0+2")
        #expect(tag("com.x.windwatch.watchkitapp") == "watch/0.1.0+2")
        #expect(tag("com.x.windwatch.watchkitapp.complications") == "widget/0.1.0+2")
        #expect(tag("") == "other/0.1.0+2")
    }
}

// MARK: - AppGroupStore

@Suite("AppGroupStore")
struct AppGroupStoreTests {
    @Test func emptyDirectoryLoadsNil() {
        let store = Stub.tempStore()
        #expect(store.load() == nil)
        #expect(store.loadMeta() == nil)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = Stub.tempStore()
        let data = try Fixture.data()
        let at = Date(timeIntervalSince1970: 1_792_600_000)
        try store.save(payloadData: data, etag: "\"sha256-abc\"", at: at)
        let cached = try #require(store.load())
        #expect(cached.payload == (try Fixture.payload()))
        #expect(cached.meta == CacheMeta(etag: "\"sha256-abc\"", lastChecked: at, lastCheckOK: true, savedAt: at))
        #expect(store.loadPayloadData() == data)
        #expect(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("wind.json").path))
        #expect(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("wind.meta.json").path))
    }

    @Test func recordCheckTouchesMetaOnly() throws {
        let store = Stub.tempStore()
        let data = try Fixture.data()
        let saved = Date(timeIntervalSince1970: 1_792_600_000)
        let later = saved.addingTimeInterval(1800)
        try store.save(payloadData: data, etag: "\"e1\"", at: saved)
        try store.recordCheck(ok: false, at: later)
        let cached = try #require(store.load())
        #expect(cached.payload == (try Fixture.payload()))
        #expect(store.loadPayloadData() == data)
        #expect(cached.meta.lastCheckOK == false)
        #expect(cached.meta.lastChecked == later)
        #expect(cached.meta.savedAt == saved)
        #expect(cached.meta.etag == "\"e1\"")
        try store.recordCheck(ok: true, at: later.addingTimeInterval(60))
        #expect(store.load()?.meta.lastCheckOK == true)
    }

    @Test func recordCheckWithoutPayloadKeepsLoadNil() throws {
        let store = Stub.tempStore()
        try store.recordCheck(ok: false, at: .now)
        #expect(store.load() == nil)
        #expect(store.loadMeta()?.lastCheckOK == false)
    }

    @Test func undecodablePayloadLoadsNil() throws {
        let store = Stub.tempStore()
        try store.save(payloadData: Data("garbage".utf8), etag: nil, at: .now)
        #expect(store.load() == nil)
        #expect(store.loadMeta() != nil)
    }

    @Test func clearRemovesEverything() throws {
        let store = Stub.tempStore()
        try store.save(payloadData: try Fixture.data(), etag: nil, at: .now)
        #expect(store.load() != nil)
        try store.clear()
        #expect(store.load() == nil)
        #expect(store.loadMeta() == nil)
        try store.clear() // idempotent
    }

    @Test func groupIDHelper() {
        #expect(AppGroupStore.groupID(bundlePrefix: "com.example") == "group.com.example.windwatch")
        #expect(AppGroupStore.defaultGroupSuffix == "windwatch")
    }

    @Test func fallbackDirectoryWithoutGroup() {
        let store = AppGroupStore(groupID: nil)
        #expect(store.directory.lastPathComponent == "WindWatch")
        #expect(store.directory.path.contains("Application Support"))
    }
}

// MARK: - Refresh

@Suite("RefreshPolicy and refresh()")
struct RefreshTests {
    func cached(lastChecked: Date?) throws -> Cached {
        Cached(payload: try Fixture.payload(), meta: CacheMeta(etag: "\"e\"", lastChecked: lastChecked, lastCheckOK: true, savedAt: .now))
    }

    @Test func policy() throws {
        let now = Date(timeIntervalSince1970: 1_792_600_000)
        #expect(RefreshPolicy.shouldFetch(cached: nil, now: now) == true)
        #expect(RefreshPolicy.shouldFetch(cached: try cached(lastChecked: nil), now: now) == true)
        #expect(RefreshPolicy.shouldFetch(cached: try cached(lastChecked: now.addingTimeInterval(-5 * 60)), now: now) == false)
        #expect(RefreshPolicy.shouldFetch(cached: try cached(lastChecked: now.addingTimeInterval(-19 * 60 - 59)), now: now) == false)
        #expect(RefreshPolicy.shouldFetch(cached: try cached(lastChecked: now.addingTimeInterval(-20 * 60)), now: now) == true)
        #expect(RefreshPolicy.shouldFetch(cached: try cached(lastChecked: now.addingTimeInterval(-60)), now: now, minInterval: 30) == true)
    }

    @Test func updatedPathSaves() async throws {
        let body = try Fixture.data()
        let (_, client) = Stub.client { _ in .init(status: 200, headers: ["ETag": "\"new\""], body: body) }
        let store = Stub.tempStore()
        let now = Date(timeIntervalSince1970: 1_792_600_000)
        let result = await refresh(client: client, store: store, location: nil, now: now)
        let cached = try #require(result)
        #expect(cached.payload == (try Fixture.payload()))
        #expect(cached.meta == CacheMeta(etag: "\"new\"", lastChecked: now, lastCheckOK: true, savedAt: now))
        #expect(store.load() == cached)
    }

    @Test func notModifiedPathTouchesMetaOnly() async throws {
        let (host, client) = Stub.client { _ in .init(status: 304) }
        let store = Stub.tempStore()
        let saved = Date(timeIntervalSince1970: 1_792_600_000)
        try store.save(payloadData: try Fixture.data(), etag: "\"old\"", at: saved)
        let now = saved.addingTimeInterval(25 * 60)
        let result = await refresh(client: client, store: store, location: nil, now: now)
        let cached = try #require(result)
        #expect(cached.meta == CacheMeta(etag: "\"old\"", lastChecked: now, lastCheckOK: true, savedAt: saved))
        #expect(cached.payload == (try Fixture.payload()))
        let sent = try #require(StubURLProtocol.requests(host: host).first)
        #expect(sent.value(forHTTPHeaderField: "If-None-Match") == "\"old\"")
    }

    @Test func failurePathKeepsOldCache() async throws {
        let (_, client) = Stub.client { _ in .init(status: 503) }
        let store = Stub.tempStore()
        let saved = Date(timeIntervalSince1970: 1_792_600_000)
        let data = try Fixture.data()
        try store.save(payloadData: data, etag: "\"old\"", at: saved)
        let now = saved.addingTimeInterval(25 * 60)
        let result = await refresh(client: client, store: store, location: nil, now: now)
        let cached = try #require(result)
        #expect(cached.payload == (try Fixture.payload()))
        #expect(cached.meta == CacheMeta(etag: "\"old\"", lastChecked: now, lastCheckOK: false, savedAt: saved))
        #expect(store.loadPayloadData() == data)
        // Trust state derived from this cache is offline-with-cache.
        let forecast = Forecast(payload: cached.payload, isDefault: true)
        #expect(TrustState.compute(forecast: forecast, now: forecast.fetched, lastCheckOK: cached.meta.lastCheckOK) == .offlineCached)
    }

    @Test func failureOnFirstRunReturnsNil() async throws {
        let (_, client) = Stub.client { _ in .init(status: 500) }
        let store = Stub.tempStore()
        let result = await refresh(client: client, store: store, location: nil, now: .now)
        #expect(result == nil)
        #expect(store.loadMeta()?.lastCheckOK == false)
    }

    @Test func customLocationIsForwarded() async throws {
        let body = try Fixture.data()
        let (host, client) = Stub.client { _ in .init(status: 200, body: body) }
        _ = await refresh(client: client, store: Stub.tempStore(), location: CustomLocation(lat: 47.6, lon: -122.3), now: .now)
        #expect(StubURLProtocol.requests(host: host).first?.url?.query == "lat=47.60&lon=-122.30")
    }
}
