import SwiftUI

/// Interactive icebreaker. Playing it produces a ready-made opener the viewer can send.
struct IcebreakerCard: View {
    let profile: Profile
    /// Called with the opener to send (quote + reply).
    var onSend: ((MessageContent) -> Void)?
    var sendTitle = L("Send as opener")

    @State private var guess: Int?
    @State private var revealed = false
    @State private var take: Bool?
    @State private var choice: Int?
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text(title)
                .font(.headline)
                .foregroundStyle(DS.Palette.accentOnNight)
                // Clear of the backdrop glyph's densest part.
                .padding(.trailing, DS.Space.xxl)

            switch profile.icebreaker {
            case let .twoTruths(statements, lie): twoTruths(statements, lie)
            case let .joke(setup, punchline): joke(setup, punchline)
            case let .hotTake(text): hotTake(text)
            case let .thisOrThat(q, options, pick): thisOrThat(q, options, pick)
            case let .guess(q, options, answer): guess(q, options, answer)
            }

            if let opener, onSend != nil {
                Button {
                    Haptics.success()
                    withAnimation(Motion.bouncy) { sent = true }
                    onSend?(opener)
                } label: {
                    Label(sent ? L("Done") : sendTitle, systemImage: sent ? "checkmark" : "heart.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(DrafftButtonStyle(kind: .like))
                .disabled(sent)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) { backdrop }
        .nightBlock()
        .animation(Motion.bouncy, value: guess)
        .animation(Motion.bouncy, value: revealed)
        .animation(Motion.bouncy, value: take)
        .animation(Motion.bouncy, value: choice)
    }

    private var title: String {
        switch profile.icebreaker {
        case .twoTruths: L("Two truths, one lie. Spot the lie.")
        case .joke: L("\(profile.name)'s best bad joke")
        case .hotTake: L("Hot take. Agree?")
        case .thisOrThat: L("This or that? Pick a side.")
        case .guess: L("Guess about \(profile.name)")
        }
    }

    private var icon: String {
        profile.icebreaker.kind.symbol
    }

    /// The kind's sign, oversized behind the top corner and cut by the block's edge: a faint
    /// accent tint on night, texture rather than a second title.
    private var backdrop: some View {
        Image(systemName: icon)
            .font(.system(size: 168, weight: .bold))
            .foregroundStyle(DS.Palette.accentOnNight.opacity(0.13))
            .rotationEffect(.degrees(-14))
            .offset(x: 44, y: -40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .clipShape(.rect(cornerRadius: DS.Radius.xl))
            .accessibilityHidden(true)
    }

    private var opener: MessageContent? {
        switch profile.icebreaker {
        case let .twoTruths(statements, lie):
            guard let guess else { return nil }
            let right = guess == lie
            return .icebreakerReply(quote: statements[guess], reply: right
                ? L("Called it: that one's the lie 😏 What's the real story?")
                : L("I was SO sure that was the lie. Tell me it's not true"))
        case let .joke(_, punchline):
            guard revealed else { return nil }
            return .icebreakerReply(quote: punchline, reply: L("Okay that got a groan AND a laugh. Respect 😂"))
        case let .hotTake(text):
            guard let take else { return nil }
            return .icebreakerReply(quote: text, reply: take ? L("Fully agree. Finally someone said it.") : L("Strongly disagree, and I'm ready to argue it over a session"))
        case let .thisOrThat(q, options, pick):
            guard let choice else { return nil }
            return .icebreakerReply(quote: options.count == 2 ? L("\(q) \(options[0]) or \(options[1])") : "\(q) \(options.joined(separator: " / "))",
                                    reply: choice == pick ? L("\(options[choice]), obviously. Great minds 🤝") : L("Team \(options[choice]). We need to talk 😄"))
        case let .guess(q, options, answer):
            guard let choice else { return nil }
            return .icebreakerReply(quote: q, reply: choice == answer ? L("Guessed it: \(options[answer])! Do I win a session?") : L("I said \(options[choice])… so it's \(options[answer])? Tell me more"))
        }
    }

    // MARK: Variants

    private func twoTruths(_ statements: [String], _ lie: Int) -> some View {
        VStack(spacing: DS.Space.sm) {
            ForEach(Array(statements.enumerated()), id: \.offset) { i, s in
                let isLie = i == lie
                let picked = guess == i
                Button {
                    guard guess == nil else { return }
                    guess = i
                    isLie ? Haptics.success() : Haptics.warning()
                } label: {
                    HStack(alignment: .top, spacing: DS.Space.md) {
                        Text(s)
                            .font(.body.weight(.medium))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if guess != nil {
                            Text(isLie ? "Lie" : "True")
                                .font(.caption.weight(.heavy))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(isLie ? DS.Palette.accentOnNight : .white.opacity(0.14), in: .capsule)
                                .foregroundStyle(isLie ? DS.Palette.onAccentOnNight : .white)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(DS.Space.lg)
                    .foregroundStyle(.white)
                    .background(background(picked: picked, isLie: isLie), in: .rect(cornerRadius: DS.Radius.lg))
                }
                .buttonStyle(PressScaleStyle(scale: 0.98))
                .disabled(guess != nil && !picked)
                .accessibilityAddTraits(picked ? .isSelected : [])
                .accessibilityHint(guess == nil ? "Guess this is the lie" : (isLie ? "This was the lie" : "This one is true"))
            }
            if let guess {
                Text(guess == lie ? "Nailed it. You read people well." : "Nope, that one's true. The lie was a different one.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(guess == lie ? DS.Palette.accentOnNight : .white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
    }

    private func background(picked: Bool, isLie: Bool) -> Color {
        guard guess != nil else { return .white.opacity(0.08) }
        // Your pick carries the fill: an accent wash when it was the lie, a light wash when not.
        if picked { return isLie ? DS.Palette.selectedOnNight : .white.opacity(0.18) }
        return .white.opacity(0.04)
    }

    private func joke(_ setup: String, _ punchline: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text(setup)
                .font(.displayBold(24, relativeTo: .title2))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                guard !revealed else { return }
                Haptics.thump()
                revealed = true
            } label: {
                ZStack(alignment: .leading) {
                    Text(punchline)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DS.Palette.accentOnNight)
                        .blur(radius: revealed ? 0 : 9)
                        .opacity(revealed ? 1 : 0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !revealed {
                        Label("Tap for the punchline", systemImage: "hand.tap.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, DS.Space.md)
                            .frame(minHeight: 36)
                            .background(.white.opacity(0.14), in: .capsule)
                            .transition(.opacity)
                    }
                }
                .padding(.vertical, DS.Space.xs)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(revealed ? punchline : L("Reveal punchline"))
        }
    }

    private func thisOrThat(_ q: String, _ options: [String], _ pick: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text(q)
                .font(.displayBold(24, relativeTo: .title2))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.sm) {
                ForEach(options.indices, id: \.self) { i in
                    let on = choice == i
                    let theirs = choice != nil && i == pick
                    Button {
                        guard choice == nil else { return }
                        Haptics.select()
                        choice = i
                    } label: {
                        VStack(spacing: 4) {
                            Text(options[i]).font(.headline).multilineTextAlignment(.center)
                            if theirs {
                                Text("\(profile.name)'s pick").font(.caption2.weight(.bold)).opacity(0.8)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .padding(.horizontal, DS.Space.sm)
                        .foregroundStyle(on ? DS.Palette.onAccentOnNight : .white)
                        // Yours: solid accent. Theirs (when different): an accent wash. No frames.
                        .background(on ? DS.Palette.accentOnNight : theirs ? DS.Palette.selectedOnNight : .white.opacity(0.1),
                                    in: .rect(cornerRadius: DS.Radius.lg))
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.96))
                    .disabled(choice != nil && !on)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if let choice {
                Text(choice == pick ? "Same pick as \(profile.name)!" : "\(profile.name) went the other way.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(choice == pick ? DS.Palette.accentOnNight : .white.opacity(0.7))
                    .transition(.opacity)
            }
        }
    }

    private func guess(_ q: String, _ options: [String], _ answer: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text(q)
                .font(.displayBold(24, relativeTo: .title2))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(options.indices, id: \.self) { i in
                let picked = choice == i
                let right = i == answer
                Button {
                    guard choice == nil else { return }
                    right ? Haptics.success() : Haptics.warning()
                    choice = i
                } label: {
                    HStack {
                        Text(options[i]).font(.body.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
                        if choice != nil && (right || picked) {
                            Image(systemName: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(right ? DS.Palette.accentOnNight : .white.opacity(0.7))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(DS.Space.lg)
                    .foregroundStyle(.white)
                    .background(.white.opacity(picked ? 0.14 : (choice == nil ? 0.08 : 0.04)), in: .rect(cornerRadius: DS.Radius.lg))
                }
                .buttonStyle(PressScaleStyle(scale: 0.98))
                .disabled(choice != nil && !picked)
                .accessibilityAddTraits(picked ? .isSelected : [])
            }
            if let choice {
                Text(choice == answer ? "Right! You know \(profile.name) already." : "Not quite. Now you know.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(choice == answer ? DS.Palette.accentOnNight : .white.opacity(0.7))
                    .transition(.opacity)
            }
        }
    }

    private func hotTake(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text("“\(text)”")
                .font(.displayBold(24, relativeTo: .title2))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.sm) {
                voteButton("Agree", icon: "hand.thumbsup.fill", value: true)
                voteButton("Disagree", icon: "hand.thumbsdown.fill", value: false)
            }
        }
    }

    private func voteButton(_ label: LocalizedStringKey, icon: String, value: Bool) -> some View {
        let on = take == value
        return Button {
            Haptics.select()
            take = value
        } label: {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(on ? DS.Palette.onAccentOnNight : .white)
                .background(on ? DS.Palette.accentOnNight : .white.opacity(0.1), in: .rect(cornerRadius: DS.Radius.lg))
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
