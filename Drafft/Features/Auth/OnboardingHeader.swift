import SwiftUI

/// Sign-up header, one row: Back, the stepper, Skip. Pinned once over the whole flow, so it never
/// slides with the steps. Skip keeps its slot when it isn't offered (only faded out), so the stepper
/// never moves; the stepper's bar sits level with the chevron, its chapter name under it.
struct OnboardingHeader: View {
    let chapters: [(title: String, steps: Int)]
    let step: Int
    let skippable: Bool
    @Binding var confirmLeave: Bool
    let back: () -> Void
    let skip: () -> Void
    let leave: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.md) {
            // Always a way back: previous step, or out of sign-up from the first one.
            Button {
                if step > 0 { back() } else { confirmLeave = true }
            } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold))
                    .frame(width: 44, height: 48, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.Palette.ink)
            .accessibilityLabel(step > 0 ? "Back" : "Leave sign-up")
            .drafftConfirm(isPresented: $confirmLeave, icon: "arrow.uturn.backward",
                           title: L("Leave sign-up?"),
                           message: L("Your answers won't be kept. You'll start over next time."),
                           cancelTitle: L("Keep going"),
                           actions: [ConfirmAction(title: L("Leave"), kind: .destructive, action: leave)])
            ChapterStepper(chapters: chapters, current: step)
                // Level the bar (not the whole stepper) with the chevron: the name hangs below.
                .alignmentGuide(VerticalAlignment.center) { _ in ChapterStepper.barHeight / 2 }
            Button(action: skip) {
                Text("Skip")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: 76, height: 48, alignment: .trailing)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .opacity(skippable ? 1 : 0)
            .animation(Motion.gentle, value: skippable)
            .disabled(!skippable)
            .accessibilityHidden(!skippable)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.bottom, DS.Space.md)
    }
}
