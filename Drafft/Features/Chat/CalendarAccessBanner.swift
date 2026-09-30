import SwiftUI
import UIKit

/// Calendar access refused or restricted when the person tries to add a session: the "New Event" sheet
/// doesn't open (the event couldn't follow the session), and this banner says why and opens Settings.
/// Shown above everything (`TopOverlayWindow`), never blocking: it swipes up and leaves on its own.
@MainActor
@Observable
final class CalendarAccessNotice {
    static let shared = CalendarAccessNotice()
    private(set) var isShown = false
    private var hide: Task<Void, Never>?

    /// How long it stays unless swiped away or tapped.
    static let duration: Duration = .seconds(8)

    func show() {
        isShown = true
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(for: Self.duration)
            guard !Task.isCancelled else { return }
            self?.isShown = false
        }
    }

    func dismiss() {
        hide?.cancel()
        isShown = false
    }
}

struct CalendarAccessBanner: View {
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void
    @State private var dragY: CGFloat = 0

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image("calendar-warning")
                .font(.title3.weight(.bold))
                .foregroundStyle(DS.Palette.onAccentOnNight)
                .frame(width: 48, height: 48)
                .background(DS.Palette.accentOnNight, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Calendar access is off for drafft.")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Haptics.tap()
                    onOpenSettings()
                } label: {
                    Text("Open Settings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.accentOnNight)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(PressScaleStyle(scale: 0.97))
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.md)
        .padding(.trailing, DS.Space.sm)
        .modifier(BannerSurface())
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Dismiss")) { onDismiss() }
        .offset(y: min(0, dragY))
        .gesture(
            DragGesture()
                .onChanged { dragY = $0.translation.height }
                .onEnded { v in
                    if v.translation.height < -30 { onDismiss() } else { withAnimation(Motion.snappy) { dragY = 0 } }
                }
        )
        .padding(.horizontal, DS.Space.md)
    }
}
