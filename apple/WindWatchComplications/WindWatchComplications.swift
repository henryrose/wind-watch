import SwiftUI
import WidgetKit
import WindCore

/// Wraps a non-Sendable completion so it can cross into a Task.
private struct Unchecked<T>: @unchecked Sendable {
    let value: T
}

/// DESIGN §5.2: one fetch (only when the cache is due) → one entry per hour boundary plus trust
/// flips, all from a single shared payload. Fixture data when the app set `FixtureFlag`.
struct WindProvider: TimelineProvider {
    private static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    private static var groupID: String {
        let prefix = (info["WWBundlePrefix"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "com.example"
        return AppGroupStore.groupID(bundlePrefix: prefix)
    }

    private static var client: WindClient? {
        guard let base = info["WWAPIBase"] as? String, let url = URL(string: base), url.host() != nil,
              url.host()?.contains("REPLACE") == false
        else { return nil }
        return WindClient(baseURL: url, clientTag: WindClient.clientTag(bundleInfo: info))
    }

    private static var isFixture: Bool {
        ProcessInfo.processInfo.environment["WW_FIXTURE"] == "1"
            || UserDefaults(suiteName: groupID).map(FixtureFlag.isSet(in:)) ?? false
    }

    func placeholder(in context: Context) -> WindEntry {
        WindEntry.fixture("fresh")
    }

    func getSnapshot(in context: Context, completion: @escaping (WindEntry) -> Void) {
        let store = AppGroupStore(groupID: Self.groupID)
        let prefs = UserDefaults(suiteName: Self.groupID).map(LocationSettings.load(from:)) ?? .default
        if let cached = store.load() {
            let forecast = Forecast(payload: cached.payload, isDefault: prefs.selectedIsServerDefault)
            let now = Date.now
            completion(WindEntry.make(forecast: forecast, at: now, lastCheckOK: cached.meta.lastCheckOK, isDefault: prefs.selectedIsServerDefault))
        } else {
            completion(placeholder(in: context))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WindEntry>) -> Void) {
        let boxed = Unchecked(value: completion)
        Task {
            let timeline = await Self.buildTimeline()
            boxed.value(timeline)
        }
    }

    static func buildTimeline() async -> Timeline<WindEntry> {
        let now = Date.now
        let store = AppGroupStore(groupID: groupID)
        let defaults = UserDefaults(suiteName: groupID)
        let prefs = defaults.map(LocationSettings.load(from:)) ?? .default
        var cached = store.load()

        if !isFixture, let client, RefreshPolicy.shouldFetch(cached: cached, now: now, minInterval: 20 * 60) {
            cached = await refresh(client: client, store: store, location: prefs.activeCustom, now: now)
        } else if isFixture, cached == nil {
            // The app has not seeded the group store yet: render the reference payload.
            if let data = try? PreviewData.payload.encoded() {
                try? store.save(payloadData: data, etag: "\"fixture\"", at: PreviewData.payload.fetchedDate)
                cached = store.load()
            }
        }

        let policy: TimelineReloadPolicy = .after(TimelineBuilder.nextReload(after: now))
        guard let cached else {
            return Timeline(entries: [WindEntry.firstRun(at: now)], policy: policy)
        }
        let isDefault = prefs.selectedIsServerDefault
        let forecast = Forecast(payload: cached.payload, isDefault: isDefault)
        let timeline = TimelineBuilder.entries(forecast: forecast, now: now, lastCheckOK: cached.meta.lastCheckOK)
        // The strip scale only grows within a run, across reloads too (HANDOFF §6.3).
        let domains = TimelineBuilder.stripDomains(forecast: forecast, entries: timeline, carried: defaults.flatMap(StripScale.load(from:)))
        if let defaults, let first = timeline.first, let yMax = domains.first ?? nil {
            StripScale(forecast: forecast, yMax: yMax, asOf: first.date).save(to: defaults)
        }
        let entries = zip(timeline, domains).map { WindEntry.make($0, forecast: forecast, isDefault: isDefault, stripYMax: $1) }
        return Timeline(entries: entries, policy: policy)
    }
}

struct WindComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WindEntry

    var body: some View {
        switch family {
        case .accessoryCircular: CircularComplicationView(entry: entry)
        case .accessoryInline: InlineComplicationView(entry: entry)
        case .accessoryCorner: CornerComplicationView(entry: entry)
        default: RectangularComplicationView(entry: entry)
        }
    }
}

struct WindComplication: Widget {
    let kind = "WindComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WindProvider()) { entry in
            WindComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Wind")
        .description("Sustained, gusts and direction for your selected location")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

@main
struct WindWatchComplicationsBundle: WidgetBundle {
    var body: some Widget {
        WindComplication()
    }
}

// MARK: - Previews

#Preview("Rectangular", as: .accessoryRectangular) {
    WindComplication()
} timeline: {
    WindEntry.fixture("fresh")
    WindEntry.fixture("stale")
    WindEntry.fixture("old")
    WindEntry.fixture("horizon")
}

#Preview("Circular", as: .accessoryCircular) {
    WindComplication()
} timeline: {
    WindEntry.fixture("fresh")
    WindEntry.fixture("stale")
    WindEntry.fixture("old")
    WindEntry.fixture("horizon")
}

#Preview("Circular · accented", as: .accessoryCircular) {
    WindComplication()
} timeline: {
    WindEntry.fixture("fresh")
    WindEntry.fixture("stale")
}

#Preview("Inline", as: .accessoryInline) {
    WindComplication()
} timeline: {
    WindEntry.fixture("fresh")
    WindEntry.fixture("stale")
    WindEntry.fixture("old")
    WindEntry.fixture("horizon")
}

#Preview("Corner", as: .accessoryCorner) {
    WindComplication()
} timeline: {
    WindEntry.fixture("fresh")
    WindEntry.fixture("stale")
    WindEntry.fixture("old")
    WindEntry.fixture("horizon")
}
