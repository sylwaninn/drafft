import SwiftUI

/// A session change the server turned down or couldn't receive: the card is already back as it was
/// (`SessionStore`), and this banner says why, in the app's words for the server's code. Shown above
/// everything (`TopOverlayWindow`), never blocking: it swipes up and leaves on its own.
@MainActor
@Observable
final class SessionFailureNotice {
    static let shared = SessionFailureNotice()
    /// The sentence on screen, or nil when hidden.
    private(set) var message: String?
    private var hide: Task<Void, Never>?

    static let duration: Duration = .seconds(6)

    func show(_ error: Error?) {
        message = Self.text(for: error)
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(for: Self.duration)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }

    func dismiss() {
        hide?.cancel()
        message = nil
    }

    /// The server's code in words (`ServerMessage`), the connection when it's that, else a generic line.
    static func text(for error: Error?) -> String {
        // `not_found` from a session call: the session, or the match behind it, is gone.
        if let error, ServerMessage.code(of: error) == "not_found" { return L("This session is no longer available.") }
        if let error, let known = ServerMessage.text(for: error) { return known }
        if error is URLError { return L("Check your connection and try again.") }
        return ServerMessage.generic
    }
}

struct SessionFailureBanner: View {
    let message: String
    let onDismiss: () -> Void
    @State private var dragY: CGFloat = 0

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.title3.weight(.bold))
                .foregroundStyle(DS.Palette.onLime)
                .frame(width: 48, height: 48)
                .background(DS.Palette.lime, in: .circle)
                .accessibilityHidden(true)
            Text(message)
                .font(.headline)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DS.Space.md)
        .padding(.trailing, DS.Space.sm)
        .modifier(BannerSurface())
        .accessibilityElement(children: .combine)
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
