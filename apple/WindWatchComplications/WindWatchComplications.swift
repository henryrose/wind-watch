import SwiftUI
import WidgetKit
import WindCore

/// D1 placeholder provider: one entry from the reference payload. Replaced in D4 by the
/// AppGroupStore + TimelineBuilder provider (DESIGN §5.2).
struct WindEntry: WidgetKit.TimelineEntry {
    let date: Date
    let hour: Forecast.Hour?
    let trust: TrustState
}

struct WindProvider: TimelineProvider {
    func placeholder(in context: Context) -> WindEntry {
        entry(at: PreviewData.now)
    }

    func getSnapshot(in context: Context, completion: @escaping (WindEntry) -> Void) {
        completion(entry(at: PreviewData.now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WindEntry>) -> Void) {
        let now = Date.now
        completion(Timeline(entries: [entry(at: now)], policy: .after(TimelineBuilder.nextReload(after: now))))
    }

    private func entry(at date: Date) -> WindEntry {
        let forecast = PreviewData.forecast
        let now = PreviewData.now
        return WindEntry(
            date: date,
            hour: forecast.hero(at: now),
            trust: TrustState.compute(forecast: forecast, now: now, lastCheckOK: true)
        )
    }
}

struct RectangularView: View {
    let entry: WindEntry

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(entry.hour?.kn ?? 0)")
                        .font(Tokens.complicationPrimaryFont(circular: false))
                    Text("G\(entry.hour?.gust ?? 0)")
                        .font(Tokens.complicationGustFont(circular: false))
                        .opacity(0.9)
                }
                HStack(spacing: 4) {
                    ArrowView(dirFrom: entry.hour?.dirFrom ?? 0, size: 11)
                    Text(Compass.fromText(dirFrom: entry.hour?.dirFrom ?? 0))
                        .font(.system(size: 12, weight: .semibold))
                    Text("kn")
                        .font(.system(size: 12, weight: .medium))
                        .opacity(0.7)
                }
            }
            Spacer()
            MiniStrip(forecast: PreviewData.forecast, now: PreviewData.now)
                .frame(width: 75, height: 31)
        }
        .containerBackground(for: .widget) { Tokens.complicationPlate(.dark) }
    }
}

struct WindComplication: Widget {
    let kind = "WindComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WindProvider()) { entry in
            RectangularView(entry: entry)
        }
        .configurationDisplayName("Wind")
        .description("Sustained wind, gust and direction now.")
        .supportedFamilies([.accessoryRectangular])
    }
}

@main
struct WindWatchComplicationsBundle: WidgetBundle {
    var body: some Widget {
        WindComplication()
    }
}
