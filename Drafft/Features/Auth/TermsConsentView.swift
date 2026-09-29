import SwiftUI

/// An account that signed up before the consent was recorded on the server, or before the current
/// terms, is asked once at its next open, over everything: the same two checks as sign-up, then
/// `accept_terms`. No close button: the only other way out is deleting the account, since drafft
/// can't work without the gender.
struct TermsConsentView: View {
    @Environment(AppModel.self) private var app
    @State private var terms = false
    @State private var sensitiveData = false
    @State private var saving = false
    @State private var failure: String?
    @State private var deleting = false

    var body: some View {
        FocusScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xxl) {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("Before you carry on.")
                        .font(.display(36))
                        .displayLeading(36)
                        .foregroundStyle(DS.Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(branded: L("drafft now keeps a record of your consent. Tick both to keep using the app."), font: .body)
                        .foregroundStyle(DS.Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ConsentChecks(terms: $terms, sensitiveData: $sensitiveData)
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.top, DS.Space.xxl)
            .padding(.bottom, DS.Space.xl)
        }
        .bottomBar { footer }
        .background { Rectangle().fill(DS.Palette.canvasSoft).ignoresSafeArea() }
        .interactiveDismissDisabled()
        .sheet(isPresented: $deleting) { DeleteAccountSheet().sheetSurface() }
    }

    private var footer: some View {
        VStack(spacing: DS.Space.xs) {
            Button(action: accept) {
                if saving { ProgressView().tint(DS.Palette.onLime) } else { Text("Accept and continue") }
            }
            .buttonStyle(.drafftPrimary)
            .disabled(!(terms && sensitiveData) || saving)
            if let failure {
                Text(failure)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DS.Palette.negative)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            // Quiet: the way out for someone who doesn't agree.
            Button("Delete my account") { deleting = true }
                .buttonStyle(.textLink)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.Palette.body)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.md)
    }

    private func accept() {
        failure = nil
        saving = true
        Task {
            defer { saving = false }
            do {
                try await TermsConsent.accept()
                Haptics.success()
                app.termsConsentNeeded = false
            } catch {
                Haptics.warning()
                withAnimation(Motion.snappy) {
                    failure = ServerMessage.text(for: error)
                        ?? L("Your consent couldn't be saved. Check your connection and try again.")
                }
            }
        }
    }
}
