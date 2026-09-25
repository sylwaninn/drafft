import SwiftUI

/// Demo of the provider's own sheet (the real one is drawn by iOS / Google): what the person
/// chooses there, and so what the app gets back.
struct SocialSignInSheet: View {
    let provider: SocialIdentity.Provider
    let onDone: (SocialIdentity) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var shareEmail = true
    @State private var givenName = "Alex"
    @State private var familyName = "Martin"
    enum Account: String, CaseIterable { case new = "New account", returning = "Returning" }
    @State private var account: Account = .new

    var body: some View {
        NavigationStack {
            FocusScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    if provider == .apple { apple } else { google }
                    DemoPanel(title: L("This \(provider.rawValue) account is"), selection: $account)
                    // In a block, like every text on the page (no loose text on the canvas).
                    Text(provider == .apple
                         ? "Apple shares a verified email (or a private relay address) and, the first time only, the name you choose. Never a photo, birthday or phone number."
                         : "Google shares your name, email and profile picture. Never your birthday, gender or phone number.")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(DS.Space.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
                }
                .padding(DS.Space.lg)
            }
            .background(DS.Palette.canvasSoft)
            .blurredNavigationEdge()
            .bottomBar {
                VStack(spacing: DS.Space.sm) {
                    Button("Continue") {
                        Haptics.success()
                        let identity = provider == .apple
                            ? DemoSocialAuth.apple(shareEmail: shareEmail, name: (givenName, familyName), newUser: account == .new)
                            : DemoSocialAuth.google(newUser: account == .new)
                        dismiss()
                        onDone(identity)
                    }
                    .buttonStyle(.drafftPrimary)
                    .disabled(needsName)
                    // Why it's disabled; keeps its height when empty.
                    Text(needsName ? "Add a first name." : " ")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.body)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(!needsName)
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.md)
                .padding(.bottom, DS.Space.sm)
            }
            .navigationTitle(provider == .apple ? "Sign in with Apple" : "Sign in with Google")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private var needsName: Bool {
        provider == .apple && account == .new && givenName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // Apple: edit the name (first time only), share or hide the email.
    private var apple: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if account == .new {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("Name").font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.ink)
                    HStack(spacing: DS.Space.sm) {
                        // Each field fills its half of the box, so a tap anywhere on it lands in it.
                        TextField("First name", text: $givenName)
                            .textContentType(.givenName)
                            .frame(maxHeight: .infinity)
                            .contentShape(.rect)
                            .revealsOnFocus()
                        Divider()
                        TextField("Last name", text: $familyName)
                            .textContentType(.familyName)
                            .frame(maxHeight: .infinity)
                            .contentShape(.rect)
                            .revealsOnFocus()
                    }
                    .padding(.horizontal, DS.Space.lg)
                    .frame(height: 52)
                    .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.md))
                }
            }
            VStack(spacing: 0) {
                emailChoice(L("Share My Email"), detail: "alex.martin@icloud.com", on: shareEmail) { shareEmail = true }
                Divider().padding(.leading, DS.Space.lg)
                emailChoice(L("Hide My Email"), detail: L("Forwards to your email"), on: !shareEmail) { shareEmail = false }
            }
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
        }
    }

    private func emailChoice(_ title: String, detail: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(DS.Palette.ink)
                    Text(detail).font(.footnote).foregroundStyle(DS.Palette.body)
                }
                Spacer()
                CheckDisc(isOn: on)
            }
            .padding(DS.Space.lg)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // Google: pick the account; consent lists what's shared.
    private var google: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                Text(verbatim: "AM")
                    .font(.headline)
                    .foregroundStyle(DS.Palette.onLime)
                    .frame(width: 44, height: 44)
                    .background(DS.Palette.lime, in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Alex Martin").font(.body.weight(.semibold)).foregroundStyle(DS.Palette.ink)
                    Text(verbatim: "alex.martin@gmail.com").font(.footnote).foregroundStyle(DS.Palette.body)
                }
                Spacer()
                CheckDisc(isOn: true)
            }
            .padding(DS.Space.lg)
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
            Text(branded: L("Google will share your name, email address and profile picture with drafft."), font: .subheadline)
                .foregroundStyle(DS.Palette.ink)
                .padding(DS.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
        }
    }
}
