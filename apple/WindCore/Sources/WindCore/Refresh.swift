import Foundation

/// When to hit the network (DESIGN §5.2): no cache, never checked, or the last check is older
/// than `minInterval` (20 min by default). Shared by the app and the widget.
public enum RefreshPolicy {
    public static let defaultMinInterval: TimeInterval = 20 * 60

    public static func shouldFetch(cached: Cached?, now: Date, minInterval: TimeInterval = defaultMinInterval) -> Bool {
        guard let cached, let lastChecked = cached.meta.lastChecked else { return true }
        return now.timeIntervalSince(lastChecked) >= minInterval
    }
}

/// One refresh cycle: fetch with the cached etag, save on `.updated`, record the check on
/// `.notModified` / `.failed`, and return whatever the store holds afterwards (possibly the old
/// cache, possibly nil on a first run that failed). Always fetches; callers gate with
/// `RefreshPolicy.shouldFetch` when they want to respect the interval.
public func refresh(
    client: WindClient, store: AppGroupStore, location: CustomLocation?, now: Date = .now
) async -> Cached? {
    let before = store.load()
    switch await client.fetch(ifNoneMatch: before?.meta.etag, location: location) {
    case .updated(let data, let etag):
        try? store.save(payloadData: data, etag: etag, at: now)
    case .notModified:
        try? store.recordCheck(ok: true, at: now)
    case .failed:
        try? store.recordCheck(ok: false, at: now)
    }
    return store.load()
}
