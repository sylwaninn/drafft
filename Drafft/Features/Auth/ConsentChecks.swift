import SwiftUI

/// The two required consents, unchecked until the person ticks them, each in its own white block:
/// the terms (the documents named in the sentence are links), then the use of sensitive data (gender,
/// the genders someone wants to see, lifestyle answers), which the privacy policy bases on explicit
/// consent. Links open getdrafft.com in the in-app browser. Sign-up and `TermsConsentView` share it.
struct ConsentChecks: View {
    @Binding var terms: Bool
    @Binding var sensitiveData: Bool

    var body: some View {
        VStack(spacing: DS.Space.md) {
            block {
                check(isOn: $terms, sentence: termsText)
            }
            block {
                check(isOn: $sensitiveData, sentence: sensitiveText,
                      detail: L("This can reveal your sexual orientation or your health, so drafft asks first."))
            }
        }
        .environment(\.openURL, OpenURLAction { url in .systemAction(url, prefersInApp: true) })
    }

    private func block(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(.vertical, DS.Space.sm)
            .padding(.horizontal, DS.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
    }

    /// The checkbox toggles; the sentence next to it carries the links.
    private func check(isOn: Binding<Bool>, sentence: AttributedString, detail: String? = nil) -> some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Button {
                Haptics.select()
                isOn.wrappedValue.toggle()
            } label: {
                DrafftCheckbox(isOn: isOn.wrappedValue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(sentence.characters))
            .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(sentence)
                    .font(.subheadline)
                    .foregroundStyle(DS.Palette.ink)
                    .tint(DS.Palette.accentInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(branded: detail, font: .footnote)
                        .foregroundStyle(DS.Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 11) // Level with the box on top, the same room under the last line.
        }
        .padding(.leading, -DS.Space.sm)
    }

    private var termsText: AttributedString {
        // One sentence for translators; the document names in it become the links.
        let terms = LegalDoc.terms.title, privacy = LegalDoc.privacy.title, community = LegalDoc.community.title
        var s = AttributedString(L("I'm 18 or older and I accept the \(terms), the \(privacy) and the \(community)."))
        for doc in LegalDoc.allCases {
            link(doc.title, to: doc.url, in: &s)
        }
        return s
    }

    private var sensitiveText: AttributedString {
        let name = L("sensitive data")
        let sentence = L("I agree that drafft uses my \(name): my gender, the genders I want to see and my lifestyle, if I fill it in.")
        var s = AttributedString(sentence)
        link(name, to: LegalDoc.sensitiveData, in: &s)
        // The brand, one weight up, as everywhere in running text.
        if let r = s.range(of: Brand.name) { s[r].font = .subheadline.weight(.semibold) }
        return s
    }

    private func link(_ words: String, to url: URL, in s: inout AttributedString) {
        guard let r = s.range(of: words) else { return }
        s[r].link = url
        s[r].underlineStyle = .single
        s[r].font = .subheadline.weight(.semibold)
    }
}
