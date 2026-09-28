import SwiftUI
import PhotosUI

/// Edit your own profile. Works on a draft; nothing changes until "Save changes".
struct EditProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Profile
    @State private var vitals: Vitals
    @State private var prompts: [ProfilePrompt]
    @State private var voice: (url: URL, duration: TimeInterval, levels: [Float])?
    @State private var photoItem: PhotosPickerItem?
    @State private var confirmDiscard = false
    @State private var saved = false
    @State private var saving = false
    @State private var saveError: String?
    @State private var pickingPrompt: Int?
    @FocusState private var focus: Field?

    @State private var original: Profile
    @State private var path: [Page] = []
    enum Field: Hashable { case name, goal, prompt(Int) }

    init(profile: Profile) {
        _original = State(initialValue: profile)
        _draft = State(initialValue: profile)
        _vitals = State(initialValue: profile.vitals ?? .blank)
        _prompts = State(initialValue: profile.prompts)
    }

    private var edited: Profile {
        var p = draft
        p.vitalsOverride = vitals
        p.promptsOverride = prompts.filter { !$0.answer.trimmingCharacters(in: .whitespaces).isEmpty }
        if let voice {
            p.voiceIntro = voice.url.path
            p.voiceDuration = voice.duration
        }
        return p
    }

    private var hasChanges: Bool {
        draft != original || vitals != original.vitals || prompts != original.prompts || voice != nil
    }

    private var canSave: Bool {
        hasChanges && !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && !draft.sports.isEmpty && (draft.icebreaker.isComplete || draft.icebreaker.isBlank)
    }

    /// Pages follow the profile as others read it: who you are and what you're after, then how
    /// you move, then what you say in your own words.
    enum Page: String, CaseIterable, Hashable, Identifiable {
        case photos, identity, lifestyle, sports, goal, bio, prompts, voice
        var id: String { rawValue }
        var title: String {
            switch self {
            case .photos: L("Photos")
            case .bio: L("Bio")
            case .prompts: L("Prompts")
            case .voice: L("Voice intro")
            case .sports: L("Sports")
            case .goal: L("Training for")
            case .identity: L("Name & age")
            case .lifestyle: L("Lifestyle")
            }
        }
        var icon: String {
            switch self {
            case .photos: "photo.on.rectangle"
            case .bio: "text.quote"
            case .prompts: "quote.bubble.fill"
            case .voice: "waveform"
            case .sports: "figure.run"
            case .goal: "flag.checkered"
            case .identity: "person.text.rectangle"
            case .lifestyle: "leaf.fill"
            }
        }
    }

    private var groups: [(title: String, pages: [Page])] { [
        (L("The basics"), [.photos, .identity, .lifestyle]),
        (L("Your sport"), [.sports, .goal]),
        (L("In your words"), [.bio, .prompts, .voice])
    ] }

    /// One-line preview of what's in each page.
    private func summary(_ page: Page) -> String {
        switch page {
        case .photos: allPhotos.count == 1 ? L("1 photo") : L("\(allPhotos.count) photos")
        case .bio: draft.bio.isEmpty ? L("Add a few words about how you move") : draft.bio
        case .identity: "\(draft.name.isEmpty ? L("No name") : draft.name), \(draft.age)"
        case .lifestyle: lifestyleSummary
        case .sports: draft.sports.map(\.sport.name).joined(separator: ", ")
        case .voice: voice != nil || draft.voiceIntro != nil ? L("Recorded") : L("Not recorded yet")
        case .prompts: draft.icebreaker.isBlank && prompts.isEmpty ? L("Add a prompt")
            : draft.icebreaker.isBlank ? L("\(prompts.count) written") : L("\(draft.icebreaker.kind.title), \(prompts.count) written")
        case .goal: draft.goal.isEmpty ? L("Add a goal") : draft.goal
        }
    }

    /// Pages that need attention before saving.
    private func needsAttention(_ page: Page) -> Bool {
        switch page {
        case .identity: draft.name.trimmingCharacters(in: .whitespaces).isEmpty
        case .bio: draft.bio.count > 200
        case .sports: draft.sports.isEmpty
        case .prompts: !draft.icebreaker.isComplete && !draft.icebreaker.isBlank
        default: false
        }
    }

    private var lifestyleSummary: String {
        let drinks = switch vitals.drinks {
        case "": ""
        case "Never": L("No alcohol")
        case "Rarely": L("Drinks rarely")
        case "Socially": L("Drinks socially")
        case "Post-race only": L("Drinks post-race only")
        default: vitals.drinks
        }
        let parts = [Vitals.label(for: vitals.chronotype), Vitals.label(for: vitals.diet), drinks].filter { !$0.isEmpty }
        return parts.isEmpty ? L("Not filled in") : parts.joined(separator: ", ")
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: DS.Space.md) {
                    ForEach(groups, id: \.title) { group in
                        categoryGroup(group.title, group.pages)
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.sm)
            }
            .background(DS.Palette.canvasSoft)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Page.self) { page in
                subPage(page)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") {
                        if hasChanges { confirmDiscard = true } else { dismiss() }
                    }
                }
            }
            .drafftConfirm(isPresented: $confirmDiscard, icon: "trash",
                           title: L("Discard your changes?"),
                           message: L("What you changed since your last save will be lost."),
                           cancelTitle: L("Keep editing"),
                           actions: [ConfirmAction(title: L("Discard changes"), kind: .destructive) { dismiss() }])
            .blurredNavigationEdge()
            .bottomBar { footer }
            .sheet(item: Binding(get: { pickingPrompt.map(PromptSlot.init) }, set: { pickingPrompt = $0?.id })) { slot in
                Group {
                    PromptPickerSheet(current: prompts.indices.contains(slot.id) ? prompts[slot.id].question : nil,
                                      used: Set(prompts.map(\.question))) { q in
                        if prompts.indices.contains(slot.id) {
                            prompts[slot.id].question = q
                        } else if prompts.count < 3 {
                            // A new prompt joins only once its question is picked.
                            withAnimation(Motion.snappy) { prompts.append(.init(question: q, answer: "")) }
                        }
                    }
                }
                .sheetSurface()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await addPhoto(item) }
            }
        }
        .interactiveDismissDisabled(hasChanges || saving)
        .onChange(of: draft) { saveError = nil }
    }

    private func categoryGroup(_ title: String, _ pages: [Page]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote.weight(.bold))
                .foregroundStyle(DS.Palette.mute)
                .padding(.top, DS.Space.lg)
                .padding(.bottom, DS.Space.xs)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(pages.enumerated()), id: \.element) { i, page in
                NavigationLink(value: page) {
                    HStack(spacing: DS.Space.md) {
                        DraftGlyph(symbol: page.icon, size: 40, fill: AnyShapeStyle(DS.Palette.canvasSoft), glyph: DS.Palette.ink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(page.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(DS.Palette.ink)
                            if page == .sports && !draft.sports.isEmpty {
                                SportsLine(sports: draft.sports.map(\.sport), font: .footnote, color: DS.Palette.body)
                            } else {
                                Text(summary(page))
                                    .font(.footnote)
                                    .foregroundStyle(needsAttention(page) ? DS.Palette.negative : DS.Palette.body)
                                    // A name is never truncated: the identity line wraps instead.
                                    .lineLimit(page == .identity ? nil : 1)
                            }
                        }
                        Spacer(minLength: DS.Space.sm)
                        if needsAttention(page) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(DS.Palette.negative)
                                .accessibilityLabel("Needs attention")
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(DS.Palette.mute)
                    }
                    .padding(.vertical, DS.Space.md)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if i < pages.count - 1 {
                    Rectangle().fill(DS.Palette.hairline).frame(height: 1).padding(.leading, 52)
                }
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
    }

    @ViewBuilder
    private func subPage(_ page: Page) -> some View {
        FocusScrollView {
            VStack(spacing: DS.Space.md) {
                switch page {
                case .photos:
                    block(L("Photos"), icon: page.icon, note: L("Hold a photo, then drag to reorder")) { photosGrid }
                case .bio:
                    block(L("Your bio"), icon: page.icon, note: L("Optional")) { bioSection }
                case .identity:
                    block(L("Name & age"), icon: page.icon) { identitySection }
                case .lifestyle:
                    block(L("Lifestyle"), icon: page.icon, note: L("Shown on your profile")) { lifestyleSection }
                case .sports:
                    block(L("Your sports"), icon: page.icon, note: L("Up to 5")) { sportsSection }
                case .voice:
                    block(L("Voice intro"), icon: page.icon) { VoiceIntroRecorder(result: $voice, framed: false) }
                case .prompts:
                    block(L("Interactive prompt"), icon: "hand.tap.fill", note: L("What you write is what they see")) {
                        IcebreakerEditor(icebreaker: $draft.icebreaker)
                    }
                    block(L("Written prompts"), icon: page.icon, note: L("Up to 3")) { promptsSection }
                case .goal:
                    block(L("What's your next goal?"), icon: page.icon) { goalSection }
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.sm)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Palette.canvasSoft)
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        // Every page keeps its validate button in view, disabled until there's something valid to save.
        .blurredNavigationEdge()
        .bottomBar { footer }
    }

    // MARK: Photos

    private var allPhotos: [String] { [draft.portrait] + draft.photos }

    @ViewBuilder
    private var photosGrid: some View {
        ReorderablePhotoGrid(
            photos: Binding(get: { allPhotos }, set: { setPhotos($0) }),
            slots: 6,
            addButton: {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .strokeBorder(DS.Palette.ink.opacity(0.2), style: .init(lineWidth: 1.5, dash: [6, 5]))
                        .background(DS.Palette.canvasSoft, in: .rect(cornerRadius: DS.Radius.lg))
                        .overlay {
                            Image(systemName: "plus")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(DS.Palette.ink)
                        }
                }
                .accessibilityLabel("Add photo")
            },
            onRemove: { removePhoto(at: $0) }
        )
    }

    private func setPhotos(_ list: [String]) {
        guard let first = list.first else { return }
        draft.portrait = first
        draft.photos = Array(list.dropFirst())
    }

    private func removePhoto(at i: Int) {
        var list = allPhotos
        list.remove(at: i)
        withAnimation(Motion.snappy) { setPhotos(list) }
    }

    private func addPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("photo-\(UUID().uuidString).jpg")
        guard (try? data.write(to: url)) != nil else { return }
        withAnimation(Motion.snappy) { setPhotos(allPhotos + [url.path]) }
        Haptics.success()
        // Sent to the backend: compressed, uploaded, then judged by moderation (the tile shows it).
        PhotoModeration.shared.submit(url.path)
    }

    // MARK: About

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                field(L("First name"), text: $draft.name, focus: .name)
                Text("Only your first name is shown.")
                    .font(.footnote).foregroundStyle(DS.Palette.mute)
            }
            divider
            // The birthday is set once, at sign-up (the server keeps it from changing).
            LockedField(title: L("Birthday"),
                        value: draft.birthday.map {
                            $0.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: .gmt).locale(.app))
                        } ?? L("\(draft.age) years old"),
                        hint: L("Set at sign-up. It can't be changed."))
        }
    }

    private var bioSection: some View {
        DrafftTextArea(title: L("Bio"), text: $draft.bio, prompt: L("Weekday dawn runner, weekend long rides…"),
                       fill: DS.Palette.canvasSoft, showsTitle: false)
    }

    private var divider: some View {
        Rectangle().fill(DS.Palette.hairline).frame(height: 1)
    }

    // MARK: Sports

    private var sportsSection: some View {
        VStack(spacing: DS.Space.sm) {
            ForEach($draft.sports) { $entry in
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    HStack(spacing: DS.Space.md) {
                        DraftGlyph(symbol: entry.sport.symbol, size: 40)
                        Text(entry.sport.name)
                            .font(.displayBold(20, relativeTo: .headline))
                            .foregroundStyle(DS.Palette.ink)
                        Spacer()
                        if draft.sports.count > 1 {
                            Button {
                                Haptics.tap()
                                let s = entry.sport
                                withAnimation(Motion.snappy) { draft.sports.removeAll { $0.sport == s } }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DS.Palette.body)
                                    .frame(width: 44, height: 44)
                                    .contentShape(.rect)
                            }
                            .accessibilityLabel("Remove \(entry.sport.name)")
                        }
                    }
                    HStack {
                        Text("How often")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Palette.body)
                        Spacer()
                        FrequencyStepper(value: $entry.perWeek, sport: entry.sport.name)
                    }
                }
                .padding(DS.Space.md)
                .background(DS.Palette.canvasSoft, in: .rect(cornerRadius: DS.Radius.lg))
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
            SportPicker(selected: draft.sports.map(\.sport), limit: 5, chipBackground: DS.Palette.canvasSoft, collapsedCount: 16) { s in
                if draft.sports.contains(where: { $0.sport == s }) { draft.sports.removeAll { $0.sport == s } }
                else if draft.sports.count < 5 { draft.sports.append(.init(sport: s)) }
            }
            .padding(.top, DS.Space.xs)
        }
    }

    // MARK: Prompts

    private var promptsSection: some View {
        VStack(spacing: DS.Space.sm) {
            ForEach(Array(prompts.enumerated()), id: \.element.id) { i, prompt in
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    HStack {
                        Button {
                            pickingPrompt = i
                        } label: {
                            HStack(spacing: 4) {
                                Text(prompt.questionText)
                                    .font(.subheadline.weight(.semibold))
                                    .multilineTextAlignment(.leading)
                                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(DS.Palette.body)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                        }
                        Spacer()
                        Button {
                            Haptics.tap()
                            focus = nil
                            withAnimation(Motion.snappy) { prompts.removeAll { $0.id == prompt.id } }
                        } label: {
                            Image(systemName: "trash")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DS.Palette.body)
                                .frame(width: 44, height: 44)
                                .contentShape(.rect)
                        }
                        .accessibilityLabel("Remove prompt")
                    }
                    TextField("Your answer", text: Binding(
                        get: { prompts.first { $0.id == prompt.id }?.answer ?? "" },
                        set: { v in if let j = prompts.firstIndex(where: { $0.id == prompt.id }) { prompts[j].answer = v } }),
                              axis: .vertical)
                        .lineLimit(2...5)
                        .font(.body.weight(.semibold))
                        .focused($focus, equals: .prompt(i))
                        .frame(minHeight: 44, alignment: .topLeading)
                        .inputStyle(focused: focus == .prompt(i), fill: DS.Palette.canvas)
                        .contentShape(.rect(cornerRadius: DS.Radius.md))
                        .onTapGesture { focus = .prompt(i) }
                        .revealsOnFocus(focus == .prompt(i))
                }
                .padding(DS.Space.md)
                .background(DS.Palette.canvasSoft, in: .rect(cornerRadius: DS.Radius.lg))
            }
            if prompts.count < 3 {
                Button {
                    Haptics.select()
                    // Nothing pre-picked: the library opens with no selection, and the prompt
                    // is only added once a question is chosen (closing adds nothing).
                    pickingPrompt = prompts.count
                } label: {
                    Label("Add a prompt", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.accentInk)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(DS.Palette.canvasSoft, in: .rect(cornerRadius: DS.Radius.lg))
                }
            }
        }
    }

    // MARK: Goal

    private var goalIdeas: [String] { [L("First 10k"), L("Sub-4h marathon"), L("Climb a 7a"), L("Swim 2k non-stop"),
                             L("Ride 100k in a day"), L("Hold a 2 min plank"), L("First trail race"), L("Win the club tournament")] }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("It shows on your profile as “Training for…”. Big or small, it's a great conversation starter.")
                .font(.footnote)
                .foregroundStyle(DS.Palette.body)
                .fixedSize(horizontal: false, vertical: true)
            TextField("e.g. Sub-4h marathon in Berlin", text: $draft.goal, axis: .vertical)
                .lineLimit(1...3)
                .font(.body.weight(.semibold))
                .focused($focus, equals: .goal)
                .submitLabel(.done)
                .inputStyle(focused: focus == .goal)
                .contentShape(.rect(cornerRadius: DS.Radius.md))
                .onTapGesture { focus = .goal }
                .revealsOnFocus(focus == .goal)
            Text("Need inspiration?")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DS.Palette.mute)
            chips(goalIdeas, selected: draft.goal) { draft.goal = $0 }
        }
    }

    // MARK: Basics

    private var lifestyleSection: some View {
        LifestylePicker(vitals: $vitals)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: DS.Space.sm) {
            Button(action: save) {
                if saving {
                    ProgressView().tint(DS.Palette.onLime)
                } else {
                    Label(saved ? "Saved" : "Save changes", systemImage: saved ? "checkmark" : "arrow.down.circle.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(.drafftPrimary)
            .disabled((!canSave && !saved) || saving)
            .draftTrail(RoundedRectangle(cornerRadius: DS.Radius.xl), step: CGSize(width: -6, height: 0))
            .padding(.leading, 12)
            Text(footerHint)
                .font(.footnote)
                .foregroundStyle(saveError != nil || (hasChanges && !canSave) ? DS.Palette.negative : DS.Palette.body)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.md)
        .padding(.bottom, DS.Space.sm)
        .animation(Motion.snappy, value: canSave)
    }

    private var footerHint: String {
        if let saveError { return saveError }
        if saved { return L("Your profile is up to date.") }
        if !hasChanges { return L("Make a change to save it.") }
        if draft.sports.isEmpty { return L("Add at least one sport.") }
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { return L("Add your first name.") }
        if !draft.icebreaker.isComplete && !draft.icebreaker.isBlank { return L("Finish your interactive prompt.") }
        return L("Saves everything you've changed.")
    }

    /// Saves the whole draft. From a sub-page it returns to the list; from the list it closes the editor.
    private func save() {
        guard canSave, !saving else { return }
        focus = nil
        let result = edited
        let previous = original
        let recorded = voice
        saveError = nil
        saving = true
        Task {
            defer { saving = false }
            // Saved on the server first; nothing changes in the app if it fails (signed out included).
            do {
                try await ProfileSync.save(result, previous: previous, voice: recorded)
            } catch {
                Haptics.warning()
                saveError = (error as? LocalizedError)?.errorDescription
                    ?? L("Couldn't connect. Check your connection and try again.")
                return
            }
            Haptics.success()
            app.me = result
            withAnimation(Motion.bouncy) { saved = true }
            let fromSubPage = !path.isEmpty
            try? await Task.sleep(for: .milliseconds(150))
            if fromSubPage {
                original = result
                draft = result
                voice = nil
                withAnimation(Motion.snappy) { saved = false; path.removeAll() }
            } else {
                dismiss()
            }
        }
    }

    // MARK: Chrome

    private func block<C: View>(_ title: String, icon: String, note: String? = nil,
                                @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            // The note shares the title's line while both fit, under it otherwise.
            AdaptiveRow {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: icon)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(DS.Palette.ink)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(DS.Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                }
            } trailing: {
                if let note {
                    Text(note).font(.footnote).foregroundStyle(DS.Palette.mute)
                }
            }
            content()
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.body)
    }

    private func field(_ title: String, text: Binding<String>, focus f: Field) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            label(title)
            TextField(title, text: text)
                .font(.body)
                .focused($focus, equals: f)
                .inputStyle(focused: focus == f)
                .contentShape(.rect(cornerRadius: DS.Radius.md))
                .onTapGesture { focus = f }
                .revealsOnFocus(focus == f)
        }
    }

    private func chips(_ options: [String], selected: String, pick: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: DS.Space.sm) {
            ForEach(options, id: \.self) { o in
                let on = o == selected
                Button {
                    Haptics.select()
                    withAnimation(Motion.select) { pick(o) }
                } label: {
                    Text(o)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, DS.Space.md)
                        .frame(minHeight: 36)
                        .foregroundStyle(on ? DS.Palette.onLime : DS.Palette.ink)
                        .background(on ? AnyShapeStyle(DS.Palette.lime) : AnyShapeStyle(DS.Palette.canvasSoft), in: .capsule)
                        .frame(minHeight: 44)
                }
                .buttonStyle(PressScaleStyle(scale: 0.94))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

extension View {
    /// Sage input with an ink ring when focused.
    func inputStyle(focused: Bool, fill: Surface = DS.Palette.canvasSoft) -> some View {
        // Height comes from the field's own frame (not padding), so the whole box takes touches.
        frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.vertical, 2)
            .padding(.horizontal, DS.Space.md)
            .background(fill, in: .rect(cornerRadius: DS.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(focused ? DS.Palette.ink : .clear, lineWidth: 1.5)
            }
            .animation(Motion.snappy, value: focused)
    }
}

struct PromptSlot: Identifiable { let id: Int }

/// A value you can see but not change, laid out like the fields around it (same label, same box),
/// but plainly disabled: a greyed box sunk into the block instead of the white of a live field,
/// greyed text, a lock, and why it's locked underneath.
private struct LockedField: View {
    let title: String
    let value: String
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.body)
                HStack(spacing: DS.Space.sm) {
                    Text(value).font(.body).foregroundStyle(DS.Palette.mute)
                    Spacer()
                    Image(systemName: "lock.fill").font(.footnote.weight(.semibold)).foregroundStyle(DS.Palette.mute)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.vertical, 2)
                .padding(.horizontal, DS.Space.md)
                .background(DS.Palette.ink.opacity(0.06), in: .rect(cornerRadius: DS.Radius.md))
                .accessibilityAddTraits(.isStaticText)
                .accessibilityValue(L("Can't be changed"))
            }
            Text(hint)
                .font(.footnote)
                .foregroundStyle(DS.Palette.mute)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
