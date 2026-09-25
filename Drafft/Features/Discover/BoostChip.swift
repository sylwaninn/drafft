import SwiftUI

/// Header chip for boosts. Idle: the bolt and how many you have. Running: one lime capsule with a
/// ring that drains around the bolt and a live mm:ss clock. A single surface either way, so it
/// never reads as a label sitting inside a button.
struct BoostChip: View {
    let boosts: Int
    let endsAt: Date?
    let action: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(0, (endsAt ?? .distantPast).timeIntervalSince(context.date))
            let running = left > 0
            Button(action: action) {
                HStack(spacing: 6) {
                    ZStack {
                        if running {
                            Circle()
                                .stroke(DS.Palette.onLime.opacity(0.2), lineWidth: 2)
                            Circle()
                                .trim(from: 0, to: left / AppModel.boostDuration)
                                .stroke(DS.Palette.onLime, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        Image(systemName: "bolt.fill")
                            .font(.system(size: running ? 9 : 13, weight: .heavy))
                    }
                    .frame(width: 20, height: 20)

                    Text(running ? Self.clock(left) : "\(boosts)")
                        .font(.subheadline.weight(.heavy).monospacedDigit())
                        .rollingDigits(wording: running, countsDown: running)
                        .lineLimit(1)
                }
                .foregroundStyle(running ? DS.Palette.onLime : DS.Palette.ink)
                .padding(.leading, DS.Space.sm)
                .padding(.trailing, DS.Space.md)
                .frame(minHeight: 36)
                .background(running ? AnyShapeStyle(DS.Palette.lime) : AnyShapeStyle(DS.Palette.canvas), in: .capsule)
                .fixedSize()
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(PressScaleStyle(scale: 0.94))
            .animation(Motion.snappy, value: running)
            .animation(.linear(duration: 1), value: Int(left))
            .accessibilityLabel(running
                                ? L("Boost running, \(Int(left) / 60) minutes \(Int(left) % 60) seconds left")
                                : boosts == 1 ? L("1 boost") : L("\(boosts) boosts"))
        }
    }

    /// 29:59, then 9:59: minutes without padding, seconds always two digits.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
