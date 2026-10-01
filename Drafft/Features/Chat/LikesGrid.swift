import SwiftUI

/// The Likes mosaic: two staggered columns of portrait tiles, tall and short in turn like a contact
/// sheet, with a lead block (the count, or what to do) as the first tile of the left column. Used by
/// the Likes tab and the drafft tempo likes sheet, blurred or sharp.
///
/// Arriving on it after a while (`StickerVisits`, the same 30 s rule as the empty-tab sticker) files
/// the tiles in from the left, one after the other, like riders tucking into a draft. A quick round
/// of tabs or the walk under the splash doesn't replay it. Reduce Motion: already in place.
struct LikesMosaic<Item: Identifiable, Lead: View, Tile: View>: View {
    let items: [Item]
    /// Arrival bookkeeping, one per screen.
    let visitKey: String
    let lead: Lead
    /// The tile for an item, at the given height.
    let tile: (Item, CGFloat) -> Tile

    @Environment(\.tabsOnScreen) private var onScreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False: tiles still tucked away (the pose the arrival starts from).
    @State private var settled: Bool
    @State private var shown = false

    /// What the lead block counts for when the columns are balanced (at least a tall tile).
    private static var leadWeight: CGFloat { LikesTileHeight.tall + 20 }
    /// Tiles past this one arrive together with it: a long list doesn't make you wait.
    private static var staggerCap: Int { 9 }

    init(items: [Item], visitKey: String, @ViewBuilder lead: () -> Lead,
         @ViewBuilder tile: @escaping (Item, CGFloat) -> Tile) {
        self.items = items
        self.visitKey = visitKey
        self.lead = lead()
        self.tile = tile
        _settled = State(initialValue: !StickerVisits.isDue(visitKey))
    }

    var body: some View {
        let layout = columns
        HStack(alignment: .top, spacing: DS.Space.sm) {
            LazyVStack(spacing: DS.Space.sm) {
                lead.modifier(DraftIn(order: 0, settled: settled))
                ForEach(layout.left, id: \.item.id) { slot in
                    tile(slot.item, slot.height).modifier(DraftIn(order: slot.order, settled: settled))
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            LazyVStack(spacing: DS.Space.sm) {
                ForEach(layout.right, id: \.item.id) { slot in
                    tile(slot.item, slot.height).modifier(DraftIn(order: slot.order, settled: settled))
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            shown = true
            if onScreen { arrive() }
        }
        .onChange(of: onScreen) { _, now in
            if now && shown { arrive() }
        }
        .onDisappear {
            shown = false
            if onScreen { StickerVisits.leave(visitKey) }
        }
    }

    private struct Slot {
        let item: Item
        let height: CGFloat
        /// Arrival order across both columns (the lead block is 0).
        let order: Int
    }

    /// Each tile goes to the shorter column; heights run tall, short, short, tall so the two
    /// columns never line up.
    private var columns: (left: [Slot], right: [Slot]) {
        var left: [Slot] = [], right: [Slot] = []
        var leftHeight = Self.leadWeight, rightHeight: CGFloat = 0
        for (i, item) in items.enumerated() {
            let height = [0, 3].contains(i % 4) ? LikesTileHeight.tall : LikesTileHeight.short
            let order = min(i + 1, Self.staggerCap)
            if rightHeight <= leftHeight {
                right.append(Slot(item: item, height: height, order: order))
                rightHeight += height + DS.Space.sm
            } else {
                left.append(Slot(item: item, height: height, order: order))
                leftHeight += height + DS.Space.sm
            }
        }
        return (left, right)
    }

    private func arrive() {
        guard StickerVisits.isDue(visitKey) || !settled else { return }
        // Recorded now, so switching away and back at once doesn't play it twice.
        StickerVisits.leave(visitKey)
        if reduceMotion {
            settled = true
            return
        }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { settled = false }
        // Next frame: each tile springs in on its own delay (`DraftIn`).
        DispatchQueue.main.async { settled = true }
    }
}

/// One tile filing in: from a little to the left and slightly smaller, faded, to its place.
private struct DraftIn: ViewModifier {
    let order: Int
    let settled: Bool

    func body(content: Content) -> some View {
        content
            .opacity(settled ? 1 : 0)
            .scaleEffect(settled ? 1 : 0.94, anchor: .leading)
            .offset(x: settled ? 0 : -28)
            .animation(settled ? .spring(response: 0.42, dampingFraction: 0.8).delay(Double(order) * 0.045) : nil,
                       value: settled)
    }
}

// MARK: - Tiles

/// A like without drafft tempo: the server's ThumbHash of their first photo (`BlurredLike`, already a
/// blur, nothing sharper ever reaches the phone), a lock, and the red heart of a super like.
struct LockedLikeTile: View {
    let like: BlurredLike
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(DS.Palette.night)
            .overlay {
                if let preview = like.preview {
                    Image(uiImage: preview).resizable().interpolation(.high).scaledToFill()
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottomLeading) {
                Image("lock-keyhole-minimalistic")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.2), in: .circle)
                    .padding(DS.Space.md)
            }
            .overlay(alignment: .topTrailing) {
                if like.superLike { SuperLikeDisc().padding(DS.Space.sm) }
            }
            .clipShape(.rect(cornerRadius: DS.Radius.xl))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.xl).strokeBorder(DS.Palette.blockEdge, lineWidth: 1)
            }
            .contentShape(.rect(cornerRadius: DS.Radius.xl))
    }
}

/// A like with drafft tempo: their photo, name and age. The tile opens the profile; the green heart
/// likes them back at once (it's mutual from there).
struct LikeTile: View {
    let profile: Profile
    let height: CGFloat
    let onOpen: () -> Void
    let onLike: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Photo(name: profile.portrait, side: 180)
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .overlay {
                    // design-lint: allow gradient - photo scrim under the name
                    LinearGradient(stops: [.init(color: .clear, location: 0.45),
                                           .init(color: DS.Palette.night.opacity(0.85), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    ProfileIdentity(profile: profile, nameSize: 20, showsLocation: false, showsSuperLike: true)
                        .padding(.leading, DS.Space.md)
                        .padding(.trailing, 56)
                        .padding(.bottom, DS.Space.md)
                }
                .clipShape(.rect(cornerRadius: DS.Radius.xl))
                .contentShape(.rect(cornerRadius: DS.Radius.xl))
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .accessibilityLabel("\(profile.name), \(profile.age). Open profile")
        .overlay(alignment: .bottomTrailing) {
            Button {
                Haptics.thump()
                onLike()
            } label: {
                // Likes stay green whatever the brand accent.
                Image("heart")
                    .font(.body.weight(.heavy))
                    .foregroundStyle(DS.Palette.onLike)
                    .frame(width: 40, height: 40)
                    .background(DS.Palette.like, in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(PressScaleStyle(scale: 0.86))
            .padding(DS.Space.xs)
            .accessibilityLabel("Like back")
        }
    }
}

/// The red disc of a super like, with its drafting heart.
private struct SuperLikeDisc: View {
    var body: some View {
        SuperLikeMark(size: 11, color: .white)
            .offset(x: -3)
            .frame(width: 30, height: 30)
            .background(DS.Palette.negative, in: .circle)
            .accessibilityHidden(true)
    }
}

// MARK: - Lead blocks

/// Tile heights shared by the mosaic and its lead block.
enum LikesTileHeight {
    static let tall: CGFloat = 252
    static let short: CGFloat = 200
}

/// The mosaic's first tile: a night block with the likes sign, a display line and one sentence.
struct LikesLeadBlock<Headline: View>: View {
    let headline: Headline
    let message: Text

    init(@ViewBuilder headline: () -> Headline, message: Text) {
        self.headline = headline()
        self.message = message
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Image("user-heart")
                .font(.title3.weight(.bold))
                .foregroundStyle(DS.Palette.onAccentOnNight)
                .frame(width: 44, height: 44)
                .background(DS.Palette.accentOnNight, in: .circle)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            headline
                .font(.display(26, relativeTo: .title))
                .displayLeading(26)
                .foregroundStyle(DS.Palette.accentOnNight)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            message
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, minHeight: LikesTileHeight.tall, alignment: .leading)
        .nightBlock()
    }
}

/// With drafft tempo: who they are is right there, like back to match.
struct TempoLikesLead: View {
    var body: some View {
        LikesLeadBlock(headline: { Text("They like you.") },
                       message: Text("Like back and it's a match straight away.").font(.subheadline))
    }
}
