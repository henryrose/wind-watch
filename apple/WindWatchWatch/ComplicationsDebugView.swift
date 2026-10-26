#if DEBUG
import SwiftUI
import WindCore

/// DEBUG-only page (`WW_PAGE=complications`, `WW_FAMILY=rectangular|circular|corner|inline`,
/// optional `WW_ROWS=fresh,stale,old,horizon`, or `WW_STATE=<one state>`, and `WW_HOUR=<index>` to
/// put fresh/stale/old at that fixture hour, e.g. 15 for `Comp-Rectangular`) rendering each
/// complication family at its exact size for screenshots. Real watch-face rendering cannot be
/// scripted in the simulator.
struct ComplicationsDebugView: View {
    private static let env = ProcessInfo.processInfo.environment
    private let family = env["WW_FAMILY"] ?? "rectangular"
    private let rows: [String] = (env["WW_ROWS"] ?? env["WW_STATE"] ?? "fresh,stale,old,horizon")
        .split(separator: ",").map(String.init)

    var body: some View {
        Group {
            switch family {
            case "circular": circular
            case "corner": corner
            case "inline": inline
            default: rectangular
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .ignoresSafeArea()
    }

    /// 184×72 on 46 mm (208 pt wide), ≈166×65 on 41/42 mm (HANDOFF §7.1).
    private var rectangular: some View {
        GeometryReader { geo in
            let small = geo.size.width < 200
            VStack(spacing: 4) {
                ForEach(rows, id: \.self) { state in
                    RectangularComplicationView(entry: Self.entry(state), tinted: false, showsPlate: true)
                        .frame(width: small ? 166 : 184, height: small ? 65 : 72)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
        }
    }

    /// `WindEntry.fixture`, or with `WW_HOUR` the state at that hour: `fetched` moved to 30 min /
    /// 2 h / 7 h before it so the trust tier matches.
    private static func entry(_ state: String) -> WindEntry {
        guard let hour = env["WW_HOUR"].flatMap(Int.init), ["fresh", "stale", "old"].contains(state) else { return .fixture(state) }
        var f = PreviewData.forecast
        let now = f.date(ofHour: hour).addingTimeInterval(30 * 60)
        f.fetched = now.addingTimeInterval(-[ "fresh": 1800, "stale": 7200, "old": 25200 ][state, default: 1800])
        return .make(forecast: f, at: now)
    }

    private var circular: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(rows, id: \.self) { state in
                    CircularComplicationView(entry: .fixture(state), tinted: false)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Tokens.complicationPlate(.dark)))
                }
            }
            // Frame rule check: 8 and 15 (fixture hours 1 and 15) must not move the arrow or gust.
            HStack(spacing: 0) {
                ForEach([1, 15, 44, 11], id: \.self) { index in
                    CircularComplicationView(entry: .make(forecast: PreviewData.forecast, at: PreviewData.forecast.date(ofHour: index)), tinted: false)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Tokens.complicationPlate(.dark)))
                }
            }
            // Tinted rendering: ramp dropped, dashing kept.
            HStack(spacing: 0) {
                ForEach(["fresh", "stale", "old", "horizon"], id: \.self) { state in
                    CircularComplicationView(entry: .fixture(state), tinted: true)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Tokens.complicationPlate(.dark)))
                        .foregroundStyle(Tokens.trustAmber(.dark))
                }
            }
        }
        .padding(.top, 30)
    }

    private var corner: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(rows, id: \.self) { state in
                    CornerComplicationView(entry: .fixture(state), tinted: false)
                        .innerLabel
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Tokens.complicationPlate(.dark)))
                }
            }
            ForEach(rows, id: \.self) { state in
                CornerComplicationView(entry: .fixture(state), tinted: false)
                    .gauge
                    .frame(width: 160)
            }
        }
        .padding(.top, 30)
    }

    private var inline: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows, id: \.self) { state in
                InlineComplicationView(entry: .fixture(state))
                    .foregroundStyle(Color.white)
            }
        }
        .padding(.top, 34)
        .padding(.horizontal, 10)
    }
}
#endif
