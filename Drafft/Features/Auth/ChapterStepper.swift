import SwiftUI

/// Sign-up stepper, between Back and Skip in the header. Only the current chapter is open: its bar
/// takes the free width, fills step by step, and names the chapter under it. The others fold to short
/// ticks (solid when done, faint when ahead). Moving to the next chapter is one move: the finished bar
/// fills and folds while the next one opens, and the name blurs across.
struct ChapterStepper: View {
    let chapters: [(title: String, steps: Int)]
    /// Index of the current step across the whole flow.
    let current: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A folded chapter: long enough to count, short enough to leave the room to the open one.
    private let tick: CGFloat = 18
    nonisolated static let barHeight: CGFloat = 5

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.xs) {
            ForEach(Array(chapters.enumerated()), id: \.offset) { i, chapter in
                let start = chapters.prefix(i).reduce(0) { $0 + $1.steps }
                let done = current >= start + chapter.steps
                let active = !done && current >= start
                let fill = done ? 1 : active ? CGFloat(current - start + 1) / CGFloat(max(1, chapter.steps)) : 0
                VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
                    Capsule()
                        .fill(DS.Palette.ink.opacity(0.12))
                        .overlay(alignment: .leading) {
                            GeometryReader { g in
                                Capsule().fill(DS.Palette.ink).frame(width: g.size.width * fill)
                            }
                        }
                        .frame(height: Self.barHeight)
                    if active {
                        Text(chapter.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(DS.Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
                    }
                }
                // Open chapter takes the room left by the folded ones.
                .frame(width: active ? nil : tick)
                .frame(maxWidth: active ? .infinity : tick, alignment: .leading)
            }
        }
        // Reserve the name's line so the row never changes height as chapters open and fold.
        .frame(minHeight: Self.barHeight + DS.Space.xs + 2 + 16, alignment: .top)
        .animation(reduceMotion ? Motion.gentle : Motion.progress, value: current)
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
