#if DEBUG
import SwiftUI
import WindCore

/// DEBUG-only page (`WW_PAGE=complications`, `WW_FAMILY=rectangular|circular|corner|inline`,
/// optional `WW_ROWS=fresh,stale,old,horizon`) rendering each complication family at its exact
/// size for screenshots. Real watch-face rendering cannot be scripted in the simulator.
struct ComplicationsDebugView: View {
    private let family = ProcessInfo.processInfo.environment["WW_FAMILY"] ?? "rectangular"
    private let rows: [String] = (ProcessInfo.processInfo.environment["WW_ROWS"] ?? "fresh,stale,old,horizon")
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

    private var rectangular: some View {
        VStack(spacing: 4) {
            ForEach(rows, id: \.self) { state in
                RectangularComplicationView(entry: .fixture(state), tinted: false, showsPlate: true)
                    .frame(width: 184, height: 72)
            }
        }
        .padding(.top, 22)
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
