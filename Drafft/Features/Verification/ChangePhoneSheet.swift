import SwiftUI

/// Change the phone number: verify the new one first. The number can't be removed, only replaced.
struct ChangePhoneSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model = PhoneVerificationModel()
    @State private var showHelp = false

    var body: some View {
        AccountSheet(title: L("Phone number"),
                     actionTitle: model.stage == .verified ? L("Done") : model.primaryTitle,
                     enabled: model.primaryEnabled,
                     loading: model.busy,
                     error: model.stage == .enterNumber && model.isSameAsCurrent ? L("That's already your number.") : nil,
                     finished: model.stage == .verified,
                     screen: .phoneVerification) {
            switch model.stage {
            case .enterNumber: Task { await model.sendCode() }
            case .enterCode: Task { await model.verify() }
            case .verified: dismiss()
            case .locked: showHelp = true
            }
        } content: {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Current number").font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.body)
                HStack {
                    Text(app.phoneNumber ?? L("None")).font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(DS.Palette.ink)
                    Spacer()
                    // Only a number that exists can be verified.
                    if app.phoneNumber != nil {
                        Label("Verified", image: "verified-check")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DS.Palette.positiveDeep)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                Text("You can replace your number, not remove it: it keeps your account secure.")
                    .font(.footnote)
                    .foregroundStyle(DS.Palette.mute)
                    .padding(.top, DS.Space.xs)
            }
            .padding(DS.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))

            SheetBlock { PhoneVerificationView(model: model) }
        }
        .onAppear { model.currentNumber = app.phoneNumber?.filter { $0.isNumber || $0 == "+" } }
        .onChange(of: model.stage) { _, s in
            if s == .verified { app.phoneNumber = model.displayNumber }
        }
        .sheet(isPresented: $showHelp) { Group { SupportSheet(topic: L("Phone verification")) }.sheetSurface() }
    }
}
