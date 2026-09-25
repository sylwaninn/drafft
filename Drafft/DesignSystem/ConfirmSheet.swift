import SwiftUI

/// Drafft's own confirmation, instead of the system action sheet: a short sheet sized to its
/// content, with the brand's type, an icon, a clear consequence and full-width buttons.
struct ConfirmAction: Identifiable {
    enum Kind { case primary, destructive }
    let title: String
    var kind: Kind = .primary
    let action: () -> Void
    var id: String { title }
}

private struct ConfirmSheet: View {
    let icon: String?
    let title: String
    let message: String?
    let actions: [ConfirmAction]
    var cancelTitle: String
    let close: () -> Void

    @State private var height: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                if let icon {
                    Image(systemName: icon)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(actions.contains { $0.kind == .destructive } ? .white : DS.Palette.onLime)
                        .frame(width: 52, height: 52)
                        .background(actions.contains { $0.kind == .destructive } ? DS.Palette.negative : DS.Palette.lime, in: .circle)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.display(30))
                    .displayLeading(30)
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(DS.Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: DS.Space.sm) {
                ForEach(actions) { a in
                    Button {
                        close()
                        a.kind == .destructive ? Haptics.warning() : Haptics.tap()
                        a.action()
                    } label: {
                        Text(a.title)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.9)
                            .foregroundStyle(a.kind == .destructive ? .white : DS.Palette.onLime)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(a.kind == .destructive ? DS.Palette.negative : DS.Palette.lime,
                                        in: .rect(cornerRadius: DS.Radius.xl))
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.97))
                }
                Button {
                    Haptics.tap()
                    close()
                } label: {
                    // The whole full-width row takes the tap, not just the word.
                    Text(cancelTitle)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DS.Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(.rect)
                }
                .buttonStyle(PressScaleStyle(scale: 0.97))
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.xxl)
        .padding(.bottom, DS.Space.sm)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        // System corner radius: the floating sheet's corners follow the screen's. Lifted above the
        // page and above any sheet it opens from (it was sage, the page's own colour).
        .presentationBackground(DS.Palette.sheetRaised)
        .environment(\.isSheetSurface, true)
    }
}

extension View {
    /// Branded confirmation sheet (use instead of confirmationDialog / alert).
    func drafftConfirm(isPresented: Binding<Bool>, icon: String? = nil, title: String, message: String? = nil,
                       cancelTitle: String = L("Cancel"), actions: [ConfirmAction]) -> some View {
        sheet(isPresented: isPresented) {
            ConfirmSheet(icon: icon, title: title, message: message, actions: actions,
                         cancelTitle: cancelTitle) { isPresented.wrappedValue = false }
        }
    }
}
