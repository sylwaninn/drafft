import SwiftUI

/// Section title in the display face.
struct ProfileSectionTitle: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.display(26, relativeTo: .title2))
                .foregroundStyle(DS.Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(DS.Palette.onLime)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DS.Palette.lime, in: .capsule)
            }
        }
    }
}

/// White block holding a section title and its content. Text never sits outside a block.
struct ProfileSectionCard<Content: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            ProfileSectionTitle(title: title, trailing: trailing)
            content
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
    }
}

// MARK: - Voice

/// Night block: big lime play button with drafting trail, full-width waveform, playback speed.
struct VoiceBlock: View {
    let profile: Profile
    @State private var audio = AudioPlayback.shared

    private var url: URL? {
        profile.voiceIntro.flatMap(AudioPlayback.url(for:))
    }
    private var isCurrent: Bool { audio.isCurrent(url) }
    private var playing: Bool { isCurrent && audio.isPlaying }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.lg) {
                Button {
                    guard let url else { return }
                    Haptics.tap()
                    audio.toggle(url)
                } label: {
                    Image(playing ? "pause" : "play")
                        .font(.system(size: 24, weight: .black))
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(DS.Palette.onAccentOnNight)
                        .frame(width: 64, height: 64)
                        .background(DS.Palette.accentOnNight, in: .circle)
                        .draftTrail(Circle(), step: CGSize(width: -10, height: 0))
                        .padding(.leading, 20)
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(playing ? "Pause voice intro" : "Play \(profile.name)'s voice intro")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Hear \(profile.name)")
                        .font(.display(24, relativeTo: .title2))
                        .foregroundStyle(.white)
                    Text("\((isCurrent && audio.elapsed > 0 ? audio.elapsed : profile.voiceDuration).clock) voice intro")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }

            TimelineView(.animation(paused: !playing)) { _ in
                WaveformBars(levels: Waveform.seeded(profile.id, count: 48), progress: isCurrent ? audio.liveProgress : 0,
                             played: DS.Palette.accentOnNight, unplayed: .white.opacity(0.22), barWidth: 3.5) { f in
                    if isCurrent { audio.seek(to: f) }
                }
            }
            .frame(height: 44)

            if isCurrent {
                HStack {
                    Spacer()
                    Button {
                        audio.rate = audio.rate == 1 ? 1.5 : (audio.rate == 1.5 ? 2 : 1)
                        Haptics.select()
                    } label: {
                        Text(audio.rate == 1 ? "1×" : (audio.rate == 1.5 ? "1.5×" : "2×"))
                            .font(.footnote.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 32)
                            .background(.white.opacity(0.14), in: .capsule)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("Playback speed")
                    .accessibilityValue(audio.rate == 1 ? "Normal" : (audio.rate == 1.5 ? "1.5 times" : "2 times"))
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(DS.Space.xl)
        .nightBlock()
        .animation(Motion.snappy, value: isCurrent)
    }
}

// MARK: - Sports

/// All of someone's sports in one block, with how often they do each. Each sport has its own tone, in the bar and on its disc; shared ones say so.
struct SportsWeekBlock: View {
    let profile: Profile
    /// The viewer, to highlight shared sports. Nil on your own profile.
    let me: Profile?

    private func shared(_ s: Sport) -> Bool { me?.sports.contains { $0.sport == s } ?? false }
    /// The sport's own tone, shared by its bar segment and its disc.
    private func tone(_ i: Int) -> Color { DS.Palette.sportTones[i % DS.Palette.sportTones.count] }
    private var sessionsPerWeek: Int { profile.sports.reduce(0) { $0 + $1.perWeek } }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(me == nil ? "How you move" : "How \(profile.name) moves")
                    .font(.display(26, relativeTo: .title2))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text(sessionsPerWeek == 1 ? "About 1 session a week" : "About \(sessionsPerWeek) sessions a week")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }

            // The week split by sport: one segment per sport, sized by how often.
            GeometryReader { geo in
                let gap: CGFloat = 4
                let total = CGFloat(max(sessionsPerWeek, 1))
                let usable = geo.size.width - gap * CGFloat(max(profile.sports.count - 1, 0))
                HStack(spacing: gap) {
                    ForEach(Array(profile.sports.enumerated()), id: \.element.id) { i, entry in
                        Capsule()
                            .fill(tone(i))
                            .frame(width: usable * CGFloat(entry.perWeek) / total)
                    }
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)

            VStack(spacing: 0) {
                ForEach(Array(profile.sports.enumerated()), id: \.element.id) { i, entry in
                    let both = shared(entry.sport)
                    HStack(spacing: DS.Space.md) {
                        Image(entry.sport.symbol)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DS.Palette.night)
                            .frame(width: 38, height: 38)
                            // Same tone as its segment in the bar above: the bar reads as a legend.
                            .background(tone(i), in: .circle)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.sport.name)
                                .font(.headline)
                                .foregroundStyle(.white)
                            if both {
                                Text("You do it too")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        Spacer(minLength: DS.Space.sm)
                        HStack(alignment: .center, spacing: 4) {
                            Text("\(entry.perWeek)×")
                                .font(.display(28, relativeTo: .title2))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                // Fixed-width, right-aligned column so every row's number lines up.
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, DS.Space.md)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(both ? L("\(entry.sport.name), \(entry.perWeekText), you do it too") : "\(entry.sport.name), \(entry.perWeekText)")
                    if i < profile.sports.count - 1 {
                        Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.leading, 50)
                    }
                }
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightBlock()
    }
}

// MARK: - Goal

/// Lime block: the goal set in display type.
struct GoalBlock: View {
    let goal: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            DraftGlyph(symbol: "flag-2", size: 40, fill: AnyShapeStyle(DS.Palette.onLimeWash), glyph: DS.Palette.onLime)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Training for")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DS.Palette.onLime)
                Text(goal)
                    .font(.display(32, relativeTo: .title))
                    .displayLeading(32)
                    .foregroundStyle(DS.Palette.onLime)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .draftBlock(DS.Palette.lime)
    }
}

// MARK: - Vitals

/// Hinge-style quick facts as a loose cluster of pills; sport stays the headline.
struct VitalsStrip: View {
    let profile: Profile
    var showDistance = true
    /// Off on the detail, where the place already sits under the name.
    var showsPlace = true

    private struct Item: Hashable { let symbol: String?; let text: String; var lead = false }

    private var items: [Item] {
        var out: [Item] = []
        if showsPlace && !profile.neighborhood.isEmpty {
            out.append(.init(symbol: nil, text: profile.neighborhood + (showDistance ? ", \(LocationPrivacy.rounded(km: profile.distanceKm))" : "")))
        }
        if let v = profile.vitals {
            if !v.chronotype.isEmpty { out.append(.init(symbol: "sunrise", text: Vitals.label(for: v.chronotype))) }
        }
        if let p = profile.pronouns, !p.isEmpty { out.append(.init(symbol: "user-rounded", text: p)) }
        if let v = profile.vitals {
            if !v.diet.isEmpty { out.append(.init(symbol: "chef-hat", text: Vitals.label(for: v.diet, gender: profile.gender))) }
            if !v.drinks.isEmpty { out.append(.init(symbol: "wineglass", text: Vitals.label(for: v.drinks))) }
            if !v.smokes.isEmpty {
                out.append(.init(symbol: "forbidden-circle", text: v.smokes == "Never" ? L("Doesn't smoke") : Vitals.label(for: v.smokes)))
            }
        }
        return out
    }

    var body: some View {
        FlowLayout(spacing: DS.Space.sm) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 6) {
                    if let symbol = item.symbol {
                        Image(symbol)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(item.lead ? DS.Palette.onLime : DS.Palette.ink)
                    }
                    Text(item.text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(item.lead ? DS.Palette.onLime : DS.Palette.ink)
                        .lineLimit(1) // tags never wrap
                        .fixedSize()
                }
                .padding(.horizontal, DS.Space.md)
                .frame(minHeight: 36)
                .background(item.lead ? AnyShapeStyle(DS.Palette.lime) : AnyShapeStyle(DS.Palette.canvas), in: .capsule)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Prompt

/// A written prompt. In Discover it can be liked on its own; the like carries the quoted answer into the match.
struct PromptCard: View {
    let prompt: ProfilePrompt
    var onLike: (() -> Void)?

    var body: some View {
        // Heart sits in the layout (not an overlay) so the text always keeps a gap from it and its trail.
        HStack(alignment: .bottom, spacing: DS.Space.lg) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text(prompt.questionText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.body)
                Text(prompt.answer)
                    .font(.displayBold(26, relativeTo: .title2))
                    .foregroundStyle(DS.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onLike {
                LikeHeartButton(label: L("Like this answer"), action: onLike)
                    .padding(.leading, 14) // room for the trail
            }
        }
        .padding(DS.Space.xl)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
    }
}

// MARK: - Likes

/// Green like heart with the drafting trail (liking stays green whatever the brand accent).
struct LikeHeartButton: View {
    var label = L("Like")
    var size: CGFloat = 52
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.thump()
            action()
        } label: {
            Image("heart")
                .font(.system(size: size * 0.38, weight: .heavy))
                .foregroundStyle(DS.Palette.onLike)
                .frame(width: size, height: size)
                .background(DS.Palette.like, in: .circle)
                .draftTrail(Circle(), color: DS.Palette.like, step: CGSize(width: -size * 0.14, height: 0))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }
}

/// A profile photo that can be liked: heart button, or double-tap with a heart pop.
struct LikablePhoto: View {
    let name: String
    var height: CGFloat = 400
    var onLike: (() -> Void)?
    @State private var pop = false

    var body: some View {
        Photo(name: name)
            .frame(height: height)
            .overlay {
                Image("heart")
                    .font(.system(size: 96, weight: .heavy))
                    .foregroundStyle(DS.Palette.like)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .scaleEffect(pop ? 1 : 0.4)
                    .opacity(pop ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottomTrailing) {
                if let onLike {
                    LikeHeartButton(label: L("Like this photo")) { like(onLike) }
                        .padding(DS.Space.lg)
                }
            }
            .clipShape(.rect(cornerRadius: DS.Radius.xl))
            .contentShape(.rect)
            .onTapGesture(count: 2) { if let onLike { like(onLike) } }
    }

    private func like(_ onLike: () -> Void) {
        Haptics.thump()
        withAnimation(Motion.bouncy) { pop = true }
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            withAnimation(.easeOut(duration: 0.18)) { pop = false }
        }
        onLike()
    }
}
