import SwiftUI
import UIKit

/// Top banner for a purchase the App Store confirmed that the server hasn't credited yet
/// (`PurchaseCredit`). Never in the way: it doesn't block the screen, swipes up to go away, and
/// never says the payment went through. After 10 minutes it offers to contact support; once the
/// wallet has the purchase it says so, then leaves.
struct PurchaseCreditBanner: View {
    let state: PurchaseCredit.Banner
    let pending: PurchaseCredit.Pending?
    let onContact: () -> Void
    let onDismiss: () -> Void
    @State private var dragY: CGFloat = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            content(slow: isSlow(at: context.date))
        }
        .offset(y: min(0, dragY))
        .gesture(
            DragGesture()
                .onChanged { dragY = $0.translation.height }
                .onEnded { v in
                    if v.translation.height < -30 { onDismiss() } else { withAnimation(Motion.snappy) { dragY = 0 } }
                }
        )
        .padding(.horizontal, DS.Space.md)
    }

    private func isSlow(at date: Date) -> Bool {
        guard state == .adding, let pending else { return false }
        return date.timeIntervalSince(pending.date) >= PurchaseCredit.slowAfter
    }

    private func content(slow: Bool) -> some View {
        HStack(spacing: DS.Space.md) {
            badge
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(title(slow: slow))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if slow {
                    Button {
                        Haptics.tap()
                        onContact()
                    } label: {
                        Text("Contact us")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Palette.accentOnNight)
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.97))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.md)
        .padding(.trailing, DS.Space.sm)
        .modifier(BannerSurface())
        .accessibilityElement(children: slow ? .contain : .combine)
        .accessibilityAction(named: Text("Dismiss")) { onDismiss() }
    }

    private func title(slow: Bool) -> String {
        if state == .credited { return L("Your purchase is on your account.") }
        if slow { return L("This is taking longer than usual.") }
        return L("We're adding your purchase to your account.")
    }

    @ViewBuilder
    private var badge: some View {
        Group {
            if state == .credited {
                Image("check")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(DS.Palette.onAccentOnNight)
            } else {
                ProgressView().tint(DS.Palette.onAccentOnNight)
            }
        }
        .frame(width: 48, height: 48)
        .background(DS.Palette.accentOnNight, in: .circle)
        .accessibilityHidden(true)
    }
}

/// Opens "Get help" above whatever is on screen, filled in for a purchase that hasn't reached the
/// account: the topic and the App Store reference.
@MainActor
enum PurchaseHelpPresenter {
    static func show(_ pending: PurchaseCredit.Pending?, app: AppModel) {
        guard let root = TopOverlayWindow.appWindow?.rootViewController else { return }
        var top = root
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        let message = pending?.transactionID.map { L("My purchase hasn't reached my account. Reference: \($0)") }
            ?? L("My purchase hasn't reached my account.")
        var details: [String: String] = [:]
        if let pending {
            details["product"] = pending.productID
            if let id = pending.transactionID { details["transaction"] = id }
        }
        let sheet = SupportSheet(topic: L("Purchase"), prefill: message, details: details)
            .environment(app)
            .environment(\.locale, .app)
            .sheetSurface()
        let host = UIHostingController(rootView: sheet)
        if let controller = host.sheetPresentationController {
            controller.detents = [.large()]
            controller.prefersGrabberVisible = true
            controller.preferredCornerRadius = DS.Radius.xl
        }
        top.present(host, animated: true)
    }
}
