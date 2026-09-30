import SwiftUI

/// Launch: the session photos rotate full screen (the log-in's quick crossfade, faster here) under
/// the white wordmark, centred at the bottom. It stays long enough to see a
/// photo, then fades onto the first screen as soon as the app is ready.
struct SplashView: View {
    /// True once the first screen is ready (tabs mounted, session restored).
    let isReady: Bool
    let onFinished: () -> Void

    @State private var shownLongEnough = false
    @State private var fading = false

    var body: some View {
        ZStack {
            DS.Palette.night.ignoresSafeArea()
            HeroSlideshow(photos: WelcomeView.photos, interval: .seconds(2.5))
                .ignoresSafeArea()
            // Flat dim: keeps the white word legible on bright photos.
            DS.Palette.night.opacity(0.28).ignoresSafeArea()
            Wordmark(size: 34, color: .white)
                .padding(.bottom, 48)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .opacity(fading ? 0 : 1)
        .allowsHitTesting(!fading)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(1.3))
            shownLongEnough = true
        }
        // Checked on change, not from the task: the task's copy of `isReady` is the first render's.
        .onChange(of: isReady) { finishIfReady() }
        .onChange(of: shownLongEnough) { finishIfReady() }
    }

    private func finishIfReady() {
        guard isReady, shownLongEnough, !fading else { return }
        withAnimation(.easeIn(duration: 0.3)) { fading = true } completion: { onFinished() }
    }
}
