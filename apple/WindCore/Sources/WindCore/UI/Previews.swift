import Foundation
import SwiftUI

/// The reference payload (HANDOFF §10) for previews in this package and in the app targets.
public enum PreviewData {
    /// Decoded from the package's copy of `fixtures/payload-reference.json`.
    public static let payload: Payload = {
        guard let url = Bundle.module.url(forResource: "payload-reference", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? Payload.decode(data)
        else { fatalError("WindCore: payload-reference.json resource missing or invalid") }
        return payload
    }()

    public static let forecast = Forecast(payload: payload, isDefault: true)

    /// Wed 21 Oct 2026 09:30 PDT: thirty minutes into the forecast.
    public static let now = forecast.start.addingTimeInterval(30 * 60)

    /// Thu 22 Oct 2026 23:30 PDT: hour 38, Old tier, 7 slots left before the horizon.
    public static let lateNow = forecast.start.addingTimeInterval(38.5 * 3600)

    public static func chart(window: ChartWindow, now: Date = now, scheme: ColorScheme = .dark) -> ChartModel {
        ChartModel(forecast: forecast, now: now, window: window, scheme: scheme)
    }
}

#Preview("WindChart · phone · all · dark") {
    WindChart(model: PreviewData.chart(window: .all), style: .phonePortrait)
        .padding(.horizontal, 16)
        .frame(width: 402)
        .background(Tokens.card(.dark))
        .environment(\.colorScheme, .dark)
}

#Preview("WindChart · phone · all · light") {
    WindChart(model: PreviewData.chart(window: .all, scheme: .light), style: .phonePortrait)
        .padding(.horizontal, 16)
        .frame(width: 402)
        .background(Tokens.card(.light))
        .environment(\.colorScheme, .light)
}

#Preview("WindChart · watch · next12") {
    WindChart(model: PreviewData.chart(window: .next12), style: .watchStrip)
        .frame(width: 198)
        .background(Tokens.groundWatch(.dark))
        .environment(\.colorScheme, .dark)
}

#Preview("WindChart · watch · short horizon") {
    WindChart(model: PreviewData.chart(window: .next12, now: PreviewData.lateNow), style: .watchStrip)
        .frame(width: 198)
        .background(Tokens.groundWatch(.dark))
        .environment(\.colorScheme, .dark)
}

#Preview("WindChart · phone · scrubbing hour 15") {
    WindChart(model: PreviewData.chart(window: .all), style: .phonePortrait, selection: 15)
        .padding(.horizontal, 16)
        .frame(width: 402)
        .background(Tokens.card(.dark))
        .environment(\.colorScheme, .dark)
}

#Preview("WindChart · phone · landscape") {
    WindChart(model: PreviewData.chart(window: .all), style: .phoneLandscape)
        .frame(width: 756)
        .background(Tokens.card(.dark))
        .environment(\.colorScheme, .dark)
}

#Preview("MiniStrip") {
    VStack(spacing: 12) {
        MiniStrip(forecast: PreviewData.forecast, now: PreviewData.now)
            .frame(width: 75, height: 31)
        MiniStrip(forecast: PreviewData.forecast, now: PreviewData.forecast.start.addingTimeInterval(14 * 3600))
            .frame(width: 180, height: 31)
        MiniStrip(forecast: PreviewData.forecast, now: PreviewData.lateNow)
            .frame(width: 75, height: 31)
    }
    .padding()
    .background(Tokens.groundWatch(.dark))
    .environment(\.colorScheme, .dark)
}

#Preview("TrustLineView · states") {
    let f = PreviewData.forecast
    VStack(alignment: .leading, spacing: 8) {
        TrustLineView(state: .fresh, forecast: f, now: PreviewData.now)
        TrustLineView(state: .stale, forecast: f, now: f.fetched.addingTimeInterval(2 * 3600))
        TrustLineView(state: .old, forecast: f, now: f.fetched.addingTimeInterval(7 * 3600))
        TrustLineView(state: .offlineCached, forecast: f, now: PreviewData.now)
        TrustLineView(state: .updating, forecast: f, now: PreviewData.now)
        TrustLineView(state: .pastHorizon, forecast: f, now: f.horizon.addingTimeInterval(3600))
        TrustLineView(state: .firstRun, forecast: nil, now: PreviewData.now)
        Divider()
        TrustLineView(state: .fresh, forecast: f, now: PreviewData.now, compact: true)
        TrustLineView(state: .offlineCached, forecast: f, now: PreviewData.now, compact: true)
    }
    .padding()
    .background(Tokens.ground(.dark))
    .environment(\.colorScheme, .dark)
}

#Preview("Glyphs") {
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            ForEach([0, 45, 90, 135, 180, 225, 270, 315], id: \.self) { d in
                ArrowView(dirFrom: d, size: 18, color: .white)
            }
        }
        HStack(spacing: 8) {
            ForEach(0...10, id: \.self) { step in BeaufortChip(step: step) }
        }
        HStack(spacing: 8) {
            BeaufortPill(step: 1)
            BeaufortPill(step: 4)
            BeaufortPill(step: 10)
            BeaufortPill.watch(step: 6)
        }
        HStack(spacing: 8) {
            TickCap(width: 10, lineWidth: 1.5, color: .white)
            SunDot(radius: 3)
            WifiSlash().foregroundStyle(Tokens.trustAmber(.dark))
        }
    }
    .padding()
    .background(Tokens.ground(.dark))
    .environment(\.colorScheme, .dark)
}
