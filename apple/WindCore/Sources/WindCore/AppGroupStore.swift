import Foundation

/// Bookkeeping stored next to the cached payload.
public struct CacheMeta: Codable, Sendable, Equatable {
    /// `ETag` of the cached payload, sent back as `If-None-Match`.
    public var etag: String?
    /// When we last asked the server (200, 304 or failure).
    public var lastChecked: Date?
    /// Whether that last check reached the server (200 or 304).
    public var lastCheckOK: Bool
    /// When the cached payload bytes were written.
    public var savedAt: Date

    public init(etag: String?, lastChecked: Date?, lastCheckOK: Bool, savedAt: Date) {
        self.etag = etag
        self.lastChecked = lastChecked
        self.lastCheckOK = lastCheckOK
        self.savedAt = savedAt
    }
}

/// What `AppGroupStore.load()` hands back: the decoded payload and its meta.
public struct Cached: Sendable, Equatable {
    public var payload: Payload
    public var meta: CacheMeta

    public init(payload: Payload, meta: CacheMeta) {
        self.payload = payload
        self.meta = meta
    }
}

/// File cache shared by the watch app and its widget extension through an App Group.
///
/// Layout: `<directory>/wind.json` (raw payload bytes, exactly as served) and
/// `<directory>/wind.meta.json` (`CacheMeta`). Reads are synchronous and sub-millisecond so the
/// first paint never waits.
public final class AppGroupStore: Sendable {
    public static let payloadFileName = "wind.json"
    public static let metaFileName = "wind.meta.json"
    public static let defaultGroupSuffix = "windwatch"

    /// `group.<prefix>.windwatch` — the apps read `<prefix>` from their Info.plist (D1).
    public static func groupID(bundlePrefix: String) -> String {
        "group.\(bundlePrefix).\(defaultGroupSuffix)"
    }

    public let directory: URL
    public var payloadURL: URL { directory.appendingPathComponent(Self.payloadFileName) }
    public var metaURL: URL { directory.appendingPathComponent(Self.metaFileName) }

    /// Uses the App Group container when `groupID` is set and available; otherwise (no group, or
    /// not entitled) a `WindWatch` folder under the user's Application Support.
    public convenience init(groupID: String?) {
        let fm = FileManager.default
        if let groupID, let container = fm.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            self.init(directory: container.appendingPathComponent("WindWatch", isDirectory: true))
        } else {
            let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fm.temporaryDirectory
            self.init(directory: support.appendingPathComponent("WindWatch", isDirectory: true))
        }
    }

    /// Explicit directory (tests, previews).
    public init(directory: URL) {
        self.directory = directory
    }

    /// Payload + meta, or nil when either is missing or undecodable.
    public func load() -> Cached? {
        guard let data = try? Data(contentsOf: payloadURL),
              let payload = try? Payload.decode(data),
              let meta = loadMeta()
        else { return nil }
        return Cached(payload: payload, meta: meta)
    }

    /// Raw cached payload bytes (for re-sending or debugging), nil when absent.
    public func loadPayloadData() -> Data? {
        try? Data(contentsOf: payloadURL)
    }

    /// Meta alone; survives an undecodable payload.
    public func loadMeta() -> CacheMeta? {
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        return try? Self.decoder.decode(CacheMeta.self, from: data)
    }

    /// Writes new payload bytes atomically and marks a successful check at `at`.
    public func save(payloadData: Data, etag: String?, at: Date = .now) throws {
        try ensureDirectory()
        try payloadData.write(to: payloadURL, options: .atomic)
        try writeMeta(CacheMeta(etag: etag, lastChecked: at, lastCheckOK: true, savedAt: at))
    }

    /// Records the outcome of a check that brought no new payload (304 or failure).
    public func recordCheck(ok: Bool, at: Date = .now) throws {
        try ensureDirectory()
        var meta = loadMeta() ?? CacheMeta(etag: nil, lastChecked: nil, lastCheckOK: ok, savedAt: .distantPast)
        meta.lastChecked = at
        meta.lastCheckOK = ok
        try writeMeta(meta)
    }

    /// Removes both files.
    public func clear() throws {
        let fm = FileManager.default
        for url in [payloadURL, metaURL] where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    // MARK: - Private

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func writeMeta(_ meta: CacheMeta) throws {
        try Self.encoder.encode(meta).write(to: metaURL, options: .atomic)
    }
}
