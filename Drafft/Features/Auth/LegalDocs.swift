import SwiftUI

/// Legal documents shown before sign-up. Demo copy: placeholders until legal provides the texts.
enum LegalDoc: String, CaseIterable, Identifiable {
    case terms, privacy, community
    var id: Self { self }

    var title: String {
        switch self {
        case .terms: L("Terms of Use")
        case .privacy: L("Privacy Policy")
        case .community: L("Community Guidelines")
        }
    }
    var sections: [(String, String)] {
        switch self {
        case .terms: [
            (L("Who can use drafft"), L("You must be 18 or older and use your real identity. One account per person.")),
            (L("Your account"), L("You verify a phone number. Keep your login details private.")),
            (L("Paid features"), L("drafft tempo renews until you cancel. Boosts and super likes are one-time purchases.")),
            (L("Ending your account"), L("You can delete your account at any time from You › Delete account."))]
        case .privacy: [
            (L("What we collect"), L("Your profile, photos, voice intro, messages, your phone number and an approximate area.")),
            (L("What we never show"), L("Your exact location and your phone number.")),
            (L("Your rights"), L("Export or delete your data at any time from You › Privacy & data. Contact our data protection officer through support.")),
            (L("How long we keep it"), L("Until you delete your account, then 30 days in backups."))]
        case .community: [
            (L("Be real"), L("Recent photos of you, your own voice, your real age.")),
            (L("Be respectful"), L("No harassment, hate or sexual content without consent.")),
            (L("Meet safely"), L("First sessions in public places. Tell a friend where you're going.")),
            (L("Report"), L("Report anything that feels wrong. Reports are confidential."))]
        }
    }
}

struct LegalDocSheet: View {
    let doc: LegalDoc
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    ForEach(doc.sections, id: \.0) { title, body in
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            Text(branded: title, font: .headline, brandWeight: .heavy).foregroundStyle(DS.Palette.ink)
                            Text(branded: body, font: .body).foregroundStyle(DS.Palette.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(DS.Space.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
                    }
                    Text("Demo text. The final legal documents will replace it.")
                        .font(.footnote)
                        .foregroundStyle(DS.Palette.body)
                        .padding(.horizontal, DS.Space.xs)
                }
                .padding(DS.Space.lg)
            }
            .background(DS.Palette.canvasSoft)
            .blurredNavigationEdge()
            .navigationTitle(doc.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }
}
