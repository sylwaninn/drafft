import SwiftUI

/// Opened when a link from an auth email couldn't be used: what happened, a way to get a new link
/// (reset), and help. Links work once, for a limited time, on the device that asked for them.
struct AuthLinkProblemView: View {
    let problem: AppModel.AuthLinkProblem
    @Environment(AppModel.self) private var app
    @State private var askingNewLink = false

    var body: some View {
        AuthScaffold(
            title: title,
            subtitle: subtitle,
            actionTitle: problem == .resetExpired ? L("Send a new link") : L("Got it"),
            actionEnabled: true,
            loading: false,
            action: next,
            backdropSeed: BackdropSeed.login
        ) {
            GetHelpButton(topic: problem == .confirmExpired ? L("Create your account") : L("Password reset"))
        }
        .navigationDestination(isPresented: $askingNewLink) { ResetPasswordView(email: app.email) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", systemImage: "xmark") { app.authLinkProblem = nil }
            }
        }
    }

    private func next() {
        if problem == .resetExpired { askingNewLink = true } else { app.authLinkProblem = nil }
    }

    private var title: String {
        problem == .offline ? L("Couldn't open the link") : L("This link has expired")
    }

    private var subtitle: String {
        switch problem {
        case .resetExpired:
            L("A reset link works once, only on the iPhone that asked for it, and only the newest one. Ask for a new link.")
        case .confirmExpired:
            L("It was already used or is too old. Log in with your email and password, or get help if you're stuck.")
        case .offline:
            L("Check your connection, then tap the link in the email again.")
        }
    }
}
