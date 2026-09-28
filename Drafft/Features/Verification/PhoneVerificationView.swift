import SwiftUI

/// Phone number, then the 6-digit code. The primary action lives in the host's pinned footer
/// (model.primaryTitle / primaryEnabled); this view shows the fields, the states and the errors.
struct PhoneVerificationView: View {
    @Bindable var model: PhoneVerificationModel
    @FocusState private var focus: Field?
    @State private var pickingCountry = false
    enum Field { case number }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            switch model.stage {
            case .enterNumber: numberField
            case .enterCode: codeEntry
            case .verified: verified
            case .locked: locked
            }
        }
        .animation(Motion.snappy, value: model.stage)
        .animation(Motion.snappy, value: model.error)
        // No focus on arrival (the page opens whole); the code step takes focus itself once the
        // person has asked for a code.
    }

    // MARK: Number

    private var numberField: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
            Text("Mobile number").font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.ink)
            HStack(spacing: 0) {
                // A plain button opening a sheet: the system menu morphed out of the field and
                // flashed white across its border.
                Button {
                    Haptics.tap()
                    pickingCountry = true
                } label: {
                    HStack(spacing: 4) {
                        Text("\(model.country.flag) \(model.country.dial)")
                            .font(.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(DS.Palette.ink)
                        Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(DS.Palette.body)
                    }
                    .padding(.horizontal, DS.Space.md)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Country code, \(model.country.name) \(model.country.dial)")
                Rectangle().fill(DS.Palette.hairline).frame(width: 1).padding(.vertical, DS.Space.sm)
                TextField(model.country.example, text: $model.number)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .font(.body.monospacedDigit())
                    .focused($focus, equals: .number)
                    .revealsOnFocus(focus == .number)
                    .padding(.horizontal, DS.Space.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .onTapGesture { focus = .number }
            }
            .frame(height: 52)
            .background(DS.Palette.field, in: .rect(cornerRadius: DS.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(model.error != nil ? DS.Palette.negative : (focus == .number ? DS.Palette.ink : DS.Palette.ink.opacity(0.35)),
                                  lineWidth: focus == .number || model.error != nil ? 2 : 1)
            }
            errorOrHint(default: L("We'll text you a code. Your number never shows on your profile."))
        }
        .sheet(isPresented: $pickingCountry) {
            Group {
                CountryPickerSheet(selection: $model.country)
                    .presentationDetents([.medium, .large])
            }
            .sheetSurface()
        }
    }

    // MARK: Code

    private var codeEntry: some View {
        OneTimeCodeEntry(destination: model.displayNumber, code: model.code, onCode: model.enterCode,
                         busy: model.busy, error: model.error, needsHelp: model.needsHelp,
                         helpTopic: L("Phone verification"),
                         hint: L("Check your messages. The code works for 10 minutes."),
                         resendIn: model.resendIn,
                         onEdit: model.changeNumber,
                         onResend: { Task { await model.resend() } })
    }

    // MARK: Results

    private var verified: some View {
        CodeVerifiedCard(title: L("Number verified"), detail: model.displayNumber)
    }

    private var locked: some View { CodeLockedCard(message: model.error) }

    /// The error or the hint, then Get help: always there on this step, even before anything
    /// fails (a number the list can't take, a text that never comes).
    private func errorOrHint(default text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DS.Palette.negative)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                // Body grey: mute is under 4.5:1 on the sage page.
                Text(text).font(.footnote).foregroundStyle(DS.Palette.body)
            }
            GetHelpButton(topic: L("Phone verification"))
        }
    }
}

/// Every country code as a searchable list in a sheet, by name in the app's language.
struct CountryPickerSheet: View {
    @Binding var selection: PhoneCountry
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// Sorted once per sheet: the names follow the app's language.
    @State private var countries = PhoneCountry.all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    private var results: [PhoneCountry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return countries.filter { q.isEmpty || $0.name.localizedStandardContains(q) || $0.dial.contains(q) }
    }

    var body: some View {
        NavigationStack {
            List(results) { c in
                Button {
                    Haptics.select()
                    selection = c
                    dismiss()
                } label: {
                    HStack {
                        Text(c.flag).accessibilityHidden(true)
                        Text(c.name).foregroundStyle(DS.Palette.ink)
                        Spacer()
                        Text(c.dial).monospacedDigit().foregroundStyle(DS.Palette.body)
                        // The one selection mark (CheckDisc), not an SF tick.
                        CheckDisc(isOn: c == selection)
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .accessibilityAddTraits(c == selection ? .isSelected : [])
            }
            .overlay {
                if results.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Country or code")
            .navigationTitle("Country code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }
}
