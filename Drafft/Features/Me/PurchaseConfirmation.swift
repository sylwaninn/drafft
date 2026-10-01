import SwiftUI

/// What was just bought, as the App Store confirmed it.
struct PurchaseReceipt: Identifiable {
    enum Item {
        case tempo(TempoSubscription)
        case boosts(count: Int, price: String, balance: Int)
        case superLikes(count: Int, price: String, balance: Int)
    }
    let id = UUID()
    let item: Item
}

/// The moment after a purchase: presented over the screen the purchase was made on, sized to
/// its content. It says what was added, what it does, a receipt-like recap and one
/// clear next step. The presenter decides what the buttons do (and closes it).
/// Raised surface (white, lifted grey in dark mode): it's often shown over the night paywall, and
/// a dark sheet on a dark page would lose its edges.
struct PurchaseConfirmation: View {
    let receipt: PurchaseReceipt
    let primaryTitle: String
    let primary: () -> Void
    var secondaryTitle: String?
    var secondary: () -> Void = {}

    @State private var height: CGFloat = 520
    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                mark
                    .scaleEffect(arrived ? 1 : 0.6)
                    .opacity(arrived ? 1 : 0)
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    title
                        .displayLeading(34)
                        .foregroundStyle(DS.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(branded: message, font: .body)
                        .foregroundStyle(DS.Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            recap

            VStack(spacing: DS.Space.sm) {
                Button {
                    Haptics.tap()
                    primary()
                } label: {
                    Text(primaryTitle)
                }
                .buttonStyle(.drafftPrimary)
                .draftTrail(RoundedRectangle(cornerRadius: DS.Radius.xl), step: CGSize(width: -6, height: 0))
                .padding(.leading, 12)

                if let secondaryTitle {
                    Button {
                        Haptics.tap()
                        secondary()
                    } label: {
                        Text(secondaryTitle)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(DS.Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(.rect)
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.97))
                }

                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(DS.Palette.body)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.xxl)
        .padding(.bottom, DS.Space.lg)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        // System corner radius: the floating sheet's corners follow the screen's.
        .presentationBackground(DS.Palette.sheetRaised)
        .onAppear {
            Haptics.success()
            withAnimation(reduceMotion ? nil : Motion.bouncy.delay(0.08)) { arrived = true }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var mark: some View {
        switch receipt.item {
        case .tempo:
            SparkPlus()
                .fill(DS.Palette.onLime)
                .frame(width: 32, height: 23)
                .frame(width: 72, height: 72)
                .background(DS.Palette.lime, in: .circle)
                .draftTrail(Circle(), step: CGSize(width: -9, height: 0))
                .padding(.leading, 18)
                .accessibilityHidden(true)
        case .boosts:
            Image("bolt")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(DS.Palette.onLime)
                .frame(width: 72, height: 72)
                .background(DS.Palette.lime, in: .circle)
                .draftTrail(Circle(), step: CGSize(width: -9, height: 0))
                .padding(.leading, 18)
                .accessibilityHidden(true)
        case .superLikes:
            SuperLikeMark(size: 26, color: .white)
                .offset(x: -5)
                .frame(width: 72, height: 72)
                .background(DS.Palette.negative, in: .circle)
                .draftTrail(Circle(), color: DS.Palette.negative, step: CGSize(width: -9, height: 0))
                .padding(.leading, 18)
                .accessibilityHidden(true)
        }
    }

    private var title: Text {
        switch receipt.item {
        case .tempo:
            Text(branded: L("You're on drafft tempo."), font: .display(34), tierColor: DS.Palette.accentInk)
        case .boosts(let n, _, _):
            Text(n == 1 ? "Boost added." : "\(n) boosts added.").font(.display(34))
        case .superLikes(let n, _, _):
            Text(n == 1 ? "Super like added." : "\(n) super likes added.").font(.display(34))
        }
    }

    private var message: String {
        switch receipt.item {
        case .tempo:
            L("Undo, see who liked you, unlimited likes and a free boost every week. Everything is on, starting now.")
        case .boosts:
            L("Each boost puts you first in decks near you for 30 minutes. Use them when you like: they never expire.")
        case .superLikes:
            L("They see you first, with a red heart on your profile. Use them when you like: they never expire.")
        }
    }

    private var footnote: String {
        switch receipt.item {
        case .tempo: L("Apple emails your receipt. Manage your subscription anytime in You.")
        case .boosts, .superLikes: L("Apple emails your receipt.")
        }
    }

    /// Receipt-like recap: what, how much, and what happens next.
    private var recap: some View {
        let rows: [(String, String)] = switch receipt.item {
        case .tempo(let sub):
            [(L("Length"), sub.plan.title),
             (L("Price"), sub.billing),
             (L("Renews"), sub.periodEnds.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(.app)))]
        case .boosts(let n, let price, let balance):
            [(L("Added"), n == 1 ? L("1 boost") : L("\(n) boosts")),
             (L("You now have"), balance == 1 ? L("1 boost") : L("\(balance) boosts")),
             (L("Paid"), price)]
        case .superLikes(let n, let price, let balance):
            [(L("Added"), n == 1 ? L("1 super like") : L("\(n) super likes")),
             (L("You now have"), balance == 1 ? L("1 super like") : L("\(balance) super likes")),
             (L("Paid"), price)]
        }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                if i > 0 { Rectangle().fill(DS.Palette.hairline).frame(height: 1) }
                AdaptiveRow(spacing: DS.Space.md) {
                    Text(row.0)
                        .font(.subheadline)
                        .foregroundStyle(DS.Palette.body)
                } trailing: {
                    Text(row.1)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(DS.Palette.ink)
                }
                .padding(.vertical, DS.Space.md)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .background(DS.Palette.canvasSoft, in: .rect(cornerRadius: DS.Radius.lg))
    }
}
