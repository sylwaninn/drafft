import SwiftUI

/// "Unmatch" on a matched profile opened from its chat: quiet like Report or block, confirmed first.
/// The chat closes behind it (`onDone`), then the match ends (`AppModel.unmatch`).
struct UnmatchButton: View {
    let profile: Profile
    let onDone: () -> Void
    @Environment(AppModel.self) private var app
    @State private var confirming = false

    var body: some View {
        Button { confirming = true } label: {
            Label("Unmatch", systemImage: "heart.slash")
                .font(.footnote.weight(.medium))
                .foregroundStyle(DS.Palette.body)
                .padding(.horizontal, DS.Space.lg)
                .frame(minHeight: 36)
                .overlay(Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Unmatch \(profile.name)")
        .drafftConfirm(isPresented: $confirming, icon: "heart.slash",
                       title: L("Unmatch \(profile.name)?"),
                       message: L("Your chat ends for both of you, and you won't see each other in Discover again."),
                       actions: [ConfirmAction(title: L("Unmatch"), kind: .destructive) { unmatch() }])
    }

    private func unmatch() {
        Haptics.success()
        let person = profile
        onDone()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            app.unmatch(person)
        }
    }
}
