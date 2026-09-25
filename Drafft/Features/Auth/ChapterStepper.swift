import SwiftUI

/// Sign-up stepper: one bar per chapter, filling step by step, with the chapter names under
/// it (the current one bold, finished ones ticked, the next ones quieter).
struct ChapterStepper: View {
    let chapters: [(title: String, steps: Int)]
    /// Index of the current step across the whole flow.
    let current: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            ForEach(Array(chapters.enumerated()), id: \.offset) { i, chapter in
                let start = chapters.prefix(i).reduce(0) { $0 + $1.steps }
                let done = current >= start + chapter.steps
                let active = !done && current >= start
                let fill = done ? 1 : active ? CGFloat(current - start + 1) / CGFloat(max(1, chapter.steps)) : 0
                VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
                    // The current chapter's bar is a touch thicker: the eye finds where it is.
                    Capsule()
                        .fill(DS.Palette.ink.opacity(0.12))
                        .overlay(alignment: .leading) {
                            GeometryReader { g in
                                Capsule().fill(DS.Palette.ink).frame(width: g.size.width * fill)
                            }
                        }
                        .frame(height: active ? 6 : 4)
                        .frame(height: 6, alignment: .center)
                    HStack(spacing: 3) {
                        if done {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.heavy))
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text(chapter.title)
                            .font(.caption.weight(active ? .bold : .semibold))
                            .instantWeight()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(active || done ? DS.Palette.ink : DS.Palette.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Bars fill, the finished chapter ticks, the next one lights up: all in one visible move.
        .animation(reduceMotion ? nil : Motion.progress, value: current)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var start = 0
        for (i, c) in chapters.enumerated() {
            if current < start + c.steps {
                return L("\(c.title), step \(current - start + 1) of \(c.steps). Part \(i + 1) of \(chapters.count).")
            }
            start += c.steps
        }
        return L("Sign-up complete")
    }
}
