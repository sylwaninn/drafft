import SwiftUI

/// "Report or block": why (required to report), a few words if they help, then the report goes to the
/// safety team (`report_user`) and the person is blocked. Or just block, without a report. They're
/// never told. One sheet: nothing opens after it.
struct ReportSheet: View {
    let profile: Profile
    /// Called once reported or blocked: the caller closes what shows the person.
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason?
    @State private var details = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var detailsFocused: Bool

    var body: some View {
        AccountSheet(title: L("Report or block"),
                     actionTitle: L("Report and block"),
                     actionIcon: "flag",
                     destructive: true,
                     enabled: reason != nil && !sending,
                     loading: sending,
                     error: error,
                     hasChanges: reason != nil || !details.isEmpty,
                     screen: .report) {
            Task { await send() }
        } content: {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                SheetBlock {
                    Text("\(profile.name) won't be notified, and you won't see each other again.")
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SheetBlock(title: L("What's wrong?")) {
                    VStack(spacing: 0) {
                        ForEach(Array(ReportReason.allCases.enumerated()), id: \.element) { i, r in
                            if i > 0 { Divider().padding(.leading, DS.Space.lg) }
                            reasonRow(r)
                        }
                    }
                    .background(DS.Palette.field, in: .rect(cornerRadius: DS.Radius.md))
                }
                SheetBlock(title: L("Anything else? (optional)")) {
                    TextField("What happened, in a few words", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.body)
                        .focused($detailsFocused)
                        .padding(DS.Space.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Palette.field, in: .rect(cornerRadius: DS.Radius.md))
                        .overlay {
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .strokeBorder(detailsFocused ? DS.Palette.ink : DS.Palette.ink.opacity(0.35),
                                              lineWidth: detailsFocused ? 2 : 1)
                        }
                }
                Button("Just block, without a report") { justBlock() }
                    .buttonStyle(.textLink(fullWidth: true))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.negative)
                    .disabled(sending)
            }
        }
    }

    private func reasonRow(_ r: ReportReason) -> some View {
        Button {
            Haptics.select()
            reason = r
        } label: {
            HStack(spacing: DS.Space.md) {
                Text(r.title).font(.body.weight(.medium)).foregroundStyle(DS.Palette.ink)
                Spacer()
                CheckDisc(isOn: reason == r)
            }
            .padding(.horizontal, DS.Space.lg)
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(reason == r ? .isSelected : [])
    }

    private func send() async {
        guard let reason else { return }
        sending = true
        error = nil
        defer { sending = false }
        do {
            try await Safety.report(profile, reason: reason, details: details)
            Haptics.success()
            dismiss()
            onDone()
        } catch {
            Haptics.warning()
            // A refusal (daily limit, account on hold…) says why; the connection only when it's the cause.
            self.error = ServerMessage.text(for: error) ?? (error is URLError
                ? L("Your report couldn't be sent. Check your connection and try again.") : ServerMessage.generic)
        }
    }

    private func justBlock() {
        Haptics.success()
        dismiss()
        onDone()
    }
}

/// The reasons the server knows (`public.report_reason`).
enum ReportReason: String, CaseIterable {
    case fake, inappropriatePhotos = "inappropriate_photos", harassment, spam, underage, other

    var title: String {
        switch self {
        case .fake: L("Fake profile or scam")
        case .inappropriatePhotos: L("Inappropriate photos")
        case .harassment: L("Harassment or threats")
        case .spam: L("Spam or selling")
        case .underage: L("Under 18")
        case .other: L("Something else")
        }
    }
}
