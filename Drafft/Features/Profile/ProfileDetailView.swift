import SwiftUI

struct ProfileDetailView: View {
    enum Mode { case discover, sheet, me }

    let profile: Profile
    var mode: Mode = .sheet
    /// Discover only: (liked, icebreaker opener to attach to the like).
    var onDecision: ((Bool, MessageContent?) -> Void)?
    /// Discover only: a confirmed super like, with its optional note. Confirmation happens here,
    /// over the profile, so cancelling brings you straight back to it.
    var onSuperLike: ((MessageContent?) -> Void)?
    /// Outside Discover (a matched profile opened from a chat): offered Report or block, and
    /// told once it's done so the chat can close behind it.
    var onBlocked: (() -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var showSafety = false
    @State private var pendingLike: LikeTarget?
    @State private var superLiking = false
    @State private var showExtras = false
    /// The profile `profile_viewed` was sent for: once per profile, not on each return to it.
    @State private var viewedID: String?

    /// Written prompts that have an answer: a skipped prompt never shows as an empty card.
    private var prompts: [ProfilePrompt] {
        profile.prompts.filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Discover: the card leaves like a pass, then the block lands (undo can't restore it).
    /// Elsewhere: the profile closes and the caller closes the chat; the block lands after.
    private func blockAndLeave() {
        Haptics.success()
        let person = profile
        if mode == .discover {
            onDecision?(false, nil)
        } else {
            dismiss()
            onBlocked?()
        }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            app.block(person)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                gallery
                header
                    .padding(.horizontal, DS.Space.lg)

                VStack(alignment: .leading, spacing: DS.Space.xxl) {
                    if profile.superLikedMe && mode == .discover { receivedSuperLike }

                    VitalsStrip(profile: profile, showDistance: false, showsPlace: false)
                        .padding(.bottom, -DS.Space.md)

                    if profile.voiceIntro != nil { VoiceBlock(profile: profile) }

                    if let p = prompts.first { promptCard(p) }

                    SportsWeekBlock(profile: profile, me: mode == .me ? nil : app.me)

                    if profile.photos.count > 0 { photo(profile.photos[0]) }

                    if prompts.count > 1 { promptCard(prompts[1]) }

                    if profile.icebreaker.isComplete {
                        IcebreakerCard(profile: profile, onSend: mode == .discover ? { opener in
                            Task {
                                try? await Task.sleep(for: .milliseconds(150))
                                onDecision?(true, opener)
                            }
                        } : nil, sendTitle: L("Like with this answer"), tracksAnswer: mode != .me)
                    }

                    if profile.photos.count > 1 { photo(profile.photos[1]) }

                    if prompts.count > 2 { promptCard(prompts[2]) }

                    if !profile.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { GoalBlock(goal: profile.goal) }

                    if profile.photos.count > 2 { photo(profile.photos[2]) }

                    if mode == .discover || onBlocked != nil {
                        // Deliberately quiet: available, never inviting.
                        Button { showSafety = true } label: {
                            Label("Report or block", image: "shield-warning")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(DS.Palette.body)
                                .padding(.horizontal, DS.Space.lg)
                                .frame(minHeight: 36)
                                .overlay(Capsule().strokeBorder(DS.Palette.hairline, lineWidth: 1))
                                .frame(minHeight: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Report or block \(profile.name)")
                        .sheet(isPresented: $showSafety) {
                            ReportSheet(profile: profile) { blockAndLeave() }
                                .sheetSurface()
                        }
                        if onBlocked != nil, app.matches.contains(where: { $0.profile.id == profile.id }) {
                            UnmatchButton(profile: profile) {
                                dismiss()
                                onBlocked?()
                            }
                        }
                    }

                }
                .padding(.horizontal, DS.Space.lg)
            }
            .padding(.bottom, DS.Space.xxl)
        }
        .background(DS.Palette.canvasSoft)
        .ignoresSafeArea(edges: .top)
        .scrollEdgeEffectHidden(true, for: .top)
        // No blur here (ours or the system's): the like/pass buttons float over the profile.
        .scrollEdgeEffectHidden(true, for: .bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if mode == .discover { decisionBar }
        }
        .toolbar {
            if mode != .me {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", image: .icon("close")) { dismiss() }
                }
            }
        }
        .toolbarVisibility(pendingLike == nil && !superLiking ? .automatic : .hidden, for: .navigationBar)
        .overlay {
            if superLiking {
                SuperLikeComposer(profile: profile, left: app.superLikes) { note in
                    superLiking = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(120))
                        onSuperLike?(note.isEmpty ? nil : .text(note))
                    }
                } onCancel: {
                    superLiking = false
                }
            }
        }
        .sheet(isPresented: $showExtras) { Group { ExtrasSheet(tab: .superLike) }.sheetSurface() }
        .overlay {
            if let target = pendingLike {
                LikeComposer(target: target, name: profile.name) { message in
                    let content: MessageContent = switch target {
                    case .photo(let name): .photoReply(asset: name, reply: message)
                    case .prompt(let p): .icebreakerReply(quote: p.answer, reply: message)
                    }
                    pendingLike = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(120))
                        onDecision?(true, content)
                    }
                } onCancel: {
                    pendingLike = nil
                }
            }
        }
        .onDisappear { AudioPlayback.shared.stop() }
        .onAppear { trackViewed() }
        .onChange(of: profile.id) { trackViewed() }
        .trackScreen(.profileDetail)
    }

    private func trackViewed() {
        guard viewedID != profile.id else { return }
        viewedID = profile.id
        let source = switch mode {
        case .discover: "discover"
        case .sheet: "sheet"
        case .me: "me"
        }
        Telemetry.track(.profileViewed(source: source, hasVoice: profile.voiceIntro != nil, photos: profile.allPhotos.count))
    }

    // MARK: Pieces

    private func promptCard(_ p: ProfilePrompt) -> some View {
        PromptCard(prompt: p, onLike: mode == .discover ? { withAnimation(Motion.snappy) { pendingLike = .prompt(p) } } : nil)
    }

    private func photo(_ name: String) -> some View {
        LikablePhoto(name: name, onLike: mode == .discover ? { likePhoto(name) } : nil)
    }

    private func likePhoto(_ name: String) { withAnimation(Motion.snappy) { pendingLike = .photo(name) } }

    private var gallery: some View {
        TabView(selection: $page) {
            ForEach(Array(profile.allPhotos.enumerated()), id: \.offset) { i, name in
                Photo(name: name, detail: true).tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 440)
        // Page steps centered on the photo, like a system page control; the heart keeps the corner.
        // Both share one bottom line so they read as one row, not two stray pieces.
        .overlay(alignment: .bottom) {
            if profile.allPhotos.count > 1 {
                PhotoSteps(count: profile.allPhotos.count, current: page)
                    .frame(height: 52)
                    .padding(.bottom, DS.Space.lg)
                    // Indicator only: swipes on it still page the photos.
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if mode == .discover {
                LikeHeartButton(label: L("Like this photo")) { likePhoto(profile.allPhotos[page]) }
                    .padding(DS.Space.lg)
            }
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: DS.Radius.xl, bottomTrailingRadius: DS.Radius.xl))
        // Stretchy header: on pull-down the photo grows upward so nothing ever shows above it.
        .visualEffect { content, proxy in
            let pull = max(0, proxy.frame(in: .scrollView).minY)
            return content.scaleEffect(1 + pull / 440, anchor: .bottom)
        }
        .accessibilityLabel("Photos of \(profile.name), \(profile.allPhotos.count) total")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            NameAgeLine(profile: profile, nameSize: 32,
                        nameColor: DS.Palette.ink, ageColor: DS.Palette.body,
                        // No heart by the name: the super like block right below says it.
                        showsBadge: false)
                .accessibilityAddTraits(.isHeader)
            // Where they are, right under the name (not buried in the facts below).
            // No pin icon (DESIGN.md: the place name stands on its own). Your own profile shows
            // the area only: a distance to yourself means nothing.
            if mode != .me {
                let distance = LocationPrivacy.rounded(km: profile.distanceKm)
                Text(profile.neighborhood.isEmpty ? L("\(distance) away") : L("\(profile.neighborhood), \(distance) away"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.ink)
            } else if !profile.neighborhood.isEmpty {
                Text(profile.neighborhood)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.ink)
            }
            if !profile.bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(profile.bio)
                    .font(.body)
                    .foregroundStyle(DS.Palette.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Straight on the page, not in a block (user-requested exception to "no loose text"):
        // the person's intro reads as the page's own title, lined up with the blocks' edges.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Their super like, in full (the deck card only shows the first lines of the note).
    private var receivedSuperLike: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                SuperLikeMark(size: 16, color: .white)
                Text("\(profile.name) super liked you")
                    .font(.subheadline.weight(.heavy))
            }
            .foregroundStyle(.white)
            if let note = profile.superLikeNote, !note.isEmpty {
                Text(note)
                    .font(.displayBold(24, relativeTo: .title2))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.negative, in: .rect(cornerRadius: DS.Radius.xl))
        .accessibilityElement(children: .combine)
    }

    private var decisionBar: some View {
        HStack(spacing: DS.Space.xl) {
            // Mirrors the super like button so cross and heart stay centered, as on the deck.
            if onSuperLike != nil { Color.clear.frame(width: 56, height: 56) }

            Button {
                onDecision?(false, nil)
            } label: {
                Image("close")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(DS.Palette.ink)
                    .frame(width: 68, height: 68)
                    .glassEffect(.regular, in: .circle)
                    // The whole disc passes, not just the glyph (glass isn't hit-testable).
                    .contentShape(.circle)
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            }
            .buttonStyle(PressScaleStyle(scale: 0.88))
            .accessibilityLabel("Pass on \(profile.name)")

            Button {
                onDecision?(true, nil)
            } label: {
                Image("heart")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(DS.Palette.onLike)
                    .frame(width: 68, height: 68)
                    .background(DS.Palette.like, in: .circle)
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            }
            .buttonStyle(PressScaleStyle(scale: 0.88))
            .accessibilityLabel("Like \(profile.name)")

            if onSuperLike != nil {
                Button {
                    if app.superLikes == 0 {
                        Haptics.warning()
                        showExtras = true
                    } else {
                        Haptics.tap()
                        withAnimation(Motion.snappy) { superLiking = true }
                    }
                } label: {
                    SuperLikeCountMark(count: app.superLikes, size: 56)
                        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                }
                .buttonStyle(PressScaleStyle(scale: 0.88))
                .accessibilityLabel("Super like \(profile.name), \(app.superLikes) left")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Space.md)
        .padding(.bottom, DS.Space.sm)
    }
}

/// Where you are in the photos: dots, the current one stretched into a bar. Sits on dark glass
/// so it reads on any photo, bright or dark, without a halo shadow.
private struct PhotoSteps: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(i == current ? 1 : 0.45))
                    .frame(width: i == current ? 18 : 6, height: 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(.black.opacity(0.3)), in: .capsule)
        .animation(Motion.snappy, value: current)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
