import NukeUI
import SwiftUI

/// The Likes grid: a banner (how many like you, and what to do) above a regular grid of portrait
/// tiles, two columns, every tile the same 3:4 shape so all rows line up. Only people go in the grid;
/// the words live in the banner. Used by the Likes tab and the drafft tempo likes sheet, blurred or
/// sharp.
///
/// Arriving on it after a while (`StickerVisits`, the same 30 s rule as the empty-tab sticker) files
/// the banner and the tiles in from the left, one after the other, like riders tucking into a draft.
/// A quick round of tabs or the walk under the splash doesn't replay it. Reduce Motion: already in
/// place.
struct LikesGrid<Item: Identifiable, Banner: View, Tile: View>: View {
    let items: [Item]
    /// Arrival bookkeeping, one per screen.
    let visitKey: String
    let banner: Banner
    let tile: (Item) -> Tile

    @Environment(\.tabsOnScreen) private var onScreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False: tiles still tucked away (the pose the arrival starts from).
    @State private var settled: Bool
    @State private var shown = false

    /// Tiles past this one arrive together with it: a long list doesn't make you wait.
    private static var staggerCap: Int { 9 }
    private static var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DS.Space.sm, alignment: .top), count: 2)
    }

    init(items: [Item], visitKey: String, @ViewBuilder banner: () -> Banner,
         @ViewBuilder tile: @escaping (Item) -> Tile) {
        self.items = items
        self.visitKey = visitKey
        self.banner = banner()
        self.tile = tile
        _settled = State(initialValue: !StickerVisits.isDue(visitKey))
    }

    var body: some View {
        VStack(spacing: DS.Space.md) {
            banner.modifier(DraftIn(order: 0, settled: settled))
            LazyVGrid(columns: Self.columns, spacing: DS.Space.sm) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    tile(item)
                        .modifier(DraftIn(order: min(index + 1, Self.staggerCap), settled: settled))
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

/// One element filing in: from a little to the left and slightly smaller, faded, to its place.
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

/// Reads the clock once a minute for what it wraps: the age labels on the tiles stay true while the
/// screen is open (the tiles themselves are static between refreshes).
struct EveryMinute<Content: View>: View {
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in content(context.date) }
    }
}

/// "5 min ago": a small translucent night capsule at the top of a tile. Night at 45 % so white text
/// reads over a blurred photo and a sharp one alike; one line, never cut.
private struct LikeAgeLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(DS.Palette.night.opacity(0.45), in: .capsule)
            .accessibilityHidden(true)
    }
}

/// The one tile shape: 3:4 portrait, whatever the screen width, so every row of the grid is the same
/// height. Content fills it; nothing in it sizes it.
private struct PortraitFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Color.clear
            .aspectRatio(3 / 4, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { content }
            .clipShape(.rect(cornerRadius: DS.Radius.xl))
            .contentShape(.rect(cornerRadius: DS.Radius.xl))
    }
}

/// A like without drafft tempo. The server's blurred copy of their first photo (`blurURL`, a signed
/// link) once it's loaded; until then, or if there is none or it fails, the ThumbHash. Both are blurs
/// made on the server: nothing sharper ever reaches the phone. A lock, and the red heart of a super
/// like.
struct LockedLikeTile: View {
    let like: BlurredLike
    /// The clock the age label reads (`EveryMinute`).
    let now: Date

    var body: some View {
        PortraitFrame {
            ZStack {
                Rectangle().fill(DS.Palette.night)
                if let preview = like.preview {
                    Image(uiImage: preview).resizable().interpolation(.high).scaledToFill()
                }
                if let url = like.blurURL {
                    ServerBlurredPhoto(url: url)
                }
                // One even veil so every tile reads alike and the lock stands out on a pale photo.
                DS.Palette.night.opacity(0.16)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Image("lock-keyhole-minimalistic")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.2), in: .circle)
                .padding(DS.Space.md)
        }
        .overlay(alignment: .top) {
            HStack(alignment: .top, spacing: DS.Space.xs) {
                if let age = LikeAge.text(of: like.likedAt, at: now) { LikeAgeLabel(text: age) }
                Spacer(minLength: 0)
                if like.superLike { SuperLikeDisc() }
            }
            .padding(DS.Space.sm)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.xl).strokeBorder(DS.Palette.blockEdge, lineWidth: 1)
        }
    }
}

/// The server's blurred rendition, through the app's image pipeline (`Images`: decoded at tile size in
/// the background, memory and disk caches keyed by the object, never by the signature). Softened a
/// little more at decode so it matches the ThumbHash it replaces. Transparent until it's there, so the
/// ThumbHash under it stays as the placeholder and the fallback.
private struct ServerBlurredPhoto: View {
    let url: String
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { geo in
            LazyImage(request: Images.request(url, points: geo.size, scale: scale, blur: 0.03, variant: "blurred"),
                      transaction: Transaction(animation: .easeOut(duration: 0.25))) { state in
                if let image = state.image {
                    image.resizable().scaledToFill().transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A like with drafft tempo: their photo, name and age. The tile opens the profile; the green heart
/// likes them back at once (it's mutual from there).
struct LikeTile: View {
    let profile: Profile
    /// The clock the age label reads (`EveryMinute`).
    let now: Date
    let onOpen: () -> Void
    let onLike: () -> Void

    var body: some View {
        Button(action: onOpen) {
            PortraitFrame {
                Photo(name: profile.portrait, side: 240)
                    .overlay {
                        // design-lint: allow gradient - photo scrim under the name
                        LinearGradient(stops: [.init(color: .clear, location: 0.45),
                                               .init(color: DS.Palette.night.opacity(0.85), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .overlay(alignment: .topLeading) {
                        if let age = LikeAge.text(of: profile.likedAt, at: now) {
                            LikeAgeLabel(text: age).padding(DS.Space.sm)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        ProfileIdentity(profile: profile, nameSize: 20, showsLocation: false, showsSuperLike: true)
                            .padding(.leading, DS.Space.md)
                            .padding(.trailing, 56)
                            .padding(.bottom, DS.Space.md)
                    }
            }
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .accessibilityLabel("\(profile.name), \(profile.age). Open profile")
        .accessibilityValue(LikeAge.text(of: profile.likedAt, at: now) ?? "")
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

/// The red disc of a super like, with its heart.
private struct SuperLikeDisc: View {
    var body: some View {
        SuperLikeMark(size: 11, color: .white)
            .frame(width: 30, height: 30)
            .background(DS.Palette.negative, in: .circle)
            .accessibilityHidden(true)
    }
}

// MARK: - Banner

/// The top of Likes: a night banner with the likes sticker (the empty tab's, still), how many people
/// like you (counted from the list the server sent, never a made-up figure) and one sentence on what
/// to do. It holds no button: the screen's one action is pinned at the bottom (or on each tile with
/// drafft tempo).
struct LikesBanner: View {
    let count: Int
    let message: Text

    var body: some View {
        let line = count == 1 ? L("1 person likes you.") : L("\(count) people like you.")
        HStack(alignment: .center, spacing: DS.Space.md) {
            StillSticker(art: .likes, size: 56)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(line)
                    .rollingDigits(wording: line.wording)
                    .font(.display(22, relativeTo: .title2))
                    .displayLeading(22)
                    .foregroundStyle(DS.Palette.accentOnNight)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                message
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Space.lg)
        .nightBlock()
        .accessibilityElement(children: .combine)
        .animation(Motion.snappy, value: count)
    }
}

extension LikesBanner {
    /// Without drafft tempo: what drafft tempo does about it. The pinned button opens it.
    static func locked(count: Int) -> LikesBanner {
        LikesBanner(count: count,
                    message: Text(branded: L("See who, and match in one tap with drafft tempo."), font: .subheadline,
                                  tierColor: DS.Palette.tierOnNight))
    }

    /// With drafft tempo: who they are is right there, like back to match.
    static func tempo(count: Int) -> LikesBanner {
        LikesBanner(count: count, message: Text("Like back and it's a match straight away.").font(.subheadline))
    }
}
