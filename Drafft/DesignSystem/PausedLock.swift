import SwiftUI

extension View {
    /// While the profile is paused, the tab's content is greyed and untouchable, with one white
    /// block over it saying why and a way to resume. The tab bar stays live (You is where it's managed).
    func pausedLock() -> some View { modifier(PausedLock()) }
}

private struct PausedLock: ViewModifier {
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        let paused = app.profilePaused
        content
            .saturation(paused ? 0 : 1)
            .opacity(paused ? 0.4 : 1)
            .allowsHitTesting(!paused)
            .accessibilityHidden(paused)
            .overlay {
                if paused {
                    notice
                        .padding(.horizontal, DS.Space.lg)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
            .animation(Motion.snappy, value: paused)
    }

    private var notice: some View {
        VStack(spacing: DS.Space.md) {
            Image(systemName: "pause.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(DS.Palette.onLime)
                .frame(width: 48, height: 48)
                .background(DS.Palette.lime, in: .circle)
                .accessibilityHidden(true)
            Text("Your profile is paused")
                .font(.display(22, relativeTo: .title2))
                .foregroundStyle(DS.Palette.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Nobody sees you, and you can't like, message or plan sessions until you resume.")
                .font(.body)
                .foregroundStyle(DS.Palette.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Resume my profile") {
                Haptics.success()
                app.profilePaused = false
            }
            .buttonStyle(.drafftPrimaryFit)
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 10)
    }
}
