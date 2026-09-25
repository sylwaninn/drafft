import SwiftUI
import PhotosUI

/// Sign-up flow. One step at a time, moved only by the buttons (no swipe between steps).
/// Nothing is pre-selected: every answer is the person's own. Optional steps keep Continue
/// disabled until something is filled in, and offer Skip instead.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @State private var step = 0
    @State private var forward = true
    @State private var birthday: Date?
    @State private var editingBirthday = false
    @State private var acceptedTerms = false
    @State private var language: AppLanguage = .deviceDefault
    @State private var legalDoc: LegalDoc?
    @State private var identity: String?
    @State private var interestedIn: Set<String> = []
    @State private var intent: Intent?
    @State private var locator = AreaLocator()
    @State private var notifications = NotificationService.shared
    @State private var phone = PhoneVerificationModel()
    @State private var showHelp: HelpTopic?
    @State private var area: Area?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var name = ""
    @State private var sports: [SportEntry] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var photos: [String] = []
    /// Face check on the first photo: nil while checking or with no photo.
    @State private var mainFace: FaceCheck.Result?
    enum DemoFace: String, CaseIterable { case real = "Real check", pass = "Face", fail = "No face" }
    @State private var demoFace: DemoFace = .real
    @State private var voice: (url: URL, duration: TimeInterval, levels: [Float])?
    @State private var icebreaker: Icebreaker = Icebreaker.Kind.twoTruths.blank
    /// Written prompts (up to 3): a question from the library and their answer.
    @State private var prompts: [ProfilePrompt] = []
    /// Lifestyle answers (intent lives in its own step).
    @State private var lifestyle = Vitals.blank
    @State private var bio = ""
    @State private var pickingPrompt: Int?
    @FocusState private var promptFocus: Int?
    /// The last step sends the profile to the server: spinner, then the server's reason if it refuses.
    @State private var finishing = false
    @State private var finishError: String?

    /// One question per step, grouped in four chapters shown in the stepper: secure the
    /// account, say who you are, how you move, then what people see.
    enum Step: Int, CaseIterable {
        case language, rules, phone
        case name, birthday, gender, showMe, intent, lifestyle, area
        case sports, rhythm
        case photos, bio, voice, prompts, icebreaker, notifications

        enum Chapter: String, CaseIterable {
            case account = "Account", you = "About you", sports = "Sports", profile = "Profile"
            var title: String {
                switch self {
                case .account: L("Account")
                case .you: L("About you")
                case .sports: L("Sports")
                case .profile: L("Profile")
                }
            }
        }
        var chapter: Chapter {
            switch self {
            case .language, .rules, .phone: .account
            case .name, .birthday, .gender, .showMe, .intent, .lifestyle, .area: .you
            case .sports, .rhythm: .sports
            case .photos, .bio, .voice, .prompts, .icebreaker, .notifications: .profile
            }
        }
    }
    private let steps = Step.allCases
    private var current: Step { steps[step] }
    @State private var restored = false
    @State private var confirmLeave = false

    var body: some View {
        ZStack {
            currentStep
                .id(step)
                // Reduce Motion: a plain fade, no sideways slide.
                .transition(reduceMotion ? AnyTransition.opacity : .asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
        }
        // A different terrain per step, cross-fading as the steps change.
        .background { PageContourBackdrop(seed: "signup-\(current)") }
        .onAppear(perform: restore)
        .onChange(of: phone.stage) { _, s in if s == .verified { save() } }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await addPhoto(item) }
        }
    }

    @ViewBuilder
    private var currentStep: some View {
        switch current {
        case .language: languageStep
        case .rules: rulesStep
        case .phone: phoneStep
        case .name: nameStep
        case .birthday: birthdayStep
        case .gender: genderStep
        case .showMe: showMeStep
        case .area: areaStep
        case .intent: intentStep
        case .lifestyle: lifestyleStep
        case .bio: bioStep
        case .sports: sportsStep
        case .rhythm: rhythmStep
        case .photos: photosStep
        case .voice: voiceStep
        case .prompts: promptsStep
        case .icebreaker: icebreakerStep
        case .notifications: notificationsStep
        }
    }

    // MARK: Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack {
                // Always a way back: previous step, or out of sign-up from the first one.
                Button {
                    if step > 0 { go(to: step - 1) } else { confirmLeave = true }
                } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                        .frame(minWidth: 80, minHeight: 48, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Palette.ink)
                .accessibilityLabel(step > 0 ? "Back" : "Leave sign-up")
                .drafftConfirm(isPresented: $confirmLeave, icon: "arrow.uturn.backward",
                               title: L("Leave sign-up?"),
                               message: L("Your answers won't be kept. You'll start over next time."),
                               cancelTitle: L("Keep going"),
                               actions: [ConfirmAction(title: L("Leave"), kind: .destructive) {
                                   // Leaving on purpose starts over: nothing is kept.
                                   OnboardingStore.clear()
                                   app.socialIdentity = nil
                                   app.signOut()
                               }])
                Spacer()
                Button { advance() } label: {
                    Text("Skip")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Palette.body)
                        // Generous invisible hit area around the word.
                        .frame(minWidth: 80, minHeight: 48, alignment: .trailing)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                    .opacity(skippable ? 1 : 0)
                    .disabled(!skippable)
                    .accessibilityHidden(!skippable)
            }
            ChapterStepper(chapters: Step.Chapter.allCases.map { c in
                (c.title, steps.filter { $0.chapter == c }.count)
            }, current: step)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.bottom, DS.Space.sm)
    }

    /// The phone check is mandatory: never skippable.
    private var skippable: Bool { Self.optional.contains(current) }
    private static let optional: Set<Step> = [.intent, .lifestyle, .bio, .voice, .prompts, .icebreaker, .notifications]

    private var footer: some View {
        VStack(spacing: DS.Space.sm) {
            // Typing a prompt answer: no Continue above the keyboard (it would jump to the next
            // step before the other prompts). The field has its own check button instead.
            if !(current == .prompts && promptFocus != nil) {
                primaryButton
                    .buttonStyle(.drafftPrimary)
                    .padding(.horizontal, DS.Space.xl)
                footerReason
            }
        }
        .padding(.bottom, DS.Space.sm)
        .sheet(item: $showHelp) { item in Group { SupportSheet(topic: item.id) }.sheetSurface() }
    }

    @ViewBuilder
    private var primaryButton: some View {
        Group {
            if current == .phone {
                Button(action: phonePrimary) {
                    if phone.busy { ProgressView().tint(DS.Palette.onLime) } else { Text(phone.primaryTitle) }
                }
                .disabled(!phone.primaryEnabled)
            } else if current == .area && area == nil {
                Button(action: areaPrimary) {
                    if locator.state == .locating { ProgressView().tint(DS.Palette.onLime) }
                    else { Label(locator.state == .denied ? "Open Settings" : "Allow location", systemImage: "location.fill") }
                }
                .disabled(locator.state == .locating)
            } else if current == .notifications && !notifications.isAllowed {
                Button {
                    Task { await notifications.requestPermission() }
                } label: { Label("Turn on notifications", systemImage: "bell.fill") }
                .disabled(notifications.isDenied)
            } else {
                Button(action: advance) {
                    if finishing { ProgressView().tint(DS.Palette.onLime) }
                    else { Text(step == steps.count - 1 ? "Start swiping" : "Continue") }
                }
                .disabled(!canContinue || finishing)
            }
        }
    }

    /// One line under the button: why it can't run yet. The line keeps its height when empty,
    /// so the button never jumps.
    private var footerReason: some View {
        let r = blockedReason
        return Text(branded: r?.text ?? " ", font: .footnote.weight(r?.error == true ? .medium : .regular))
            .foregroundStyle(r?.error == true ? DS.Palette.negative : DS.Palette.body)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.Space.xl)
            .contentTransition(.opacity)
            .animation(Motion.snappy, value: r?.text)
            .accessibilityHidden(r == nil)
    }

    private var blockedReason: (text: String, error: Bool)? {
        if let finishError, step == steps.count - 1 { return (finishError, true) }
        switch current {
        case .language: return nil
        case .rules: return acceptedTerms ? nil : (L("Accept the rules and terms to continue."), false)
        case .phone:
            // Sending or checking: the spinner says it, no reason needed.
            if phone.busy || phone.primaryEnabled { return nil }
            switch phone.stage {
            case .enterNumber:
                return (phone.number.isEmpty ? L("Enter your mobile number.") : L("That number looks incomplete."), false)
            case .enterCode: return (L("Enter the 6-digit code we sent you."), false)
            default: return nil
            }
        case .name: return complete(.name) ? nil : (L("Add your first name."), false)
        case .birthday:
            if birthday == nil { return (L("Pick your birthday."), false) }
            return isAdult ? nil : (L("drafft is for people 18 and over."), true)
        case .gender: return identity == nil ? (L("Pick the one that fits you best."), false) : nil
        case .showMe: return interestedIn.isEmpty ? (L("Pick at least one."), false) : nil
        case .intent: return intent == nil ? (L("Pick one, or skip it for now."), false) : nil
        case .lifestyle: return lifestyle.hasLifestyle ? nil : (L("Answer one, or skip it for now."), false)
        case .bio:
            if bio.count > 200 { return (L("Keep it under 200 characters."), true) }
            return bioText.isEmpty ? (L("Write a few words, or skip it for now."), false) : nil
        case .area: return area == nil && locator.state == .locating ? (L("Finding your area…"), false) : nil
        case .sports: return sports.isEmpty ? (L("Pick at least one sport."), false) : nil
        case .rhythm: return nil
        case .photos:
            if photos.isEmpty { return (L("Add at least one photo."), false) }
            switch mainFace {
            case nil: return (L("Checking your first photo…"), false)
            case .face?: return nil
            case .noFace?, .tooSmall?: return (L("Put a clear photo of your face first."), true)
            }
        case .voice: return voice == nil ? (L("Record your intro, or skip it for now."), false) : nil
        case .prompts: return answeredPrompts.isEmpty ? (L("Answer a prompt, or skip it for now."), false) : nil
        case .icebreaker: return icebreaker.isComplete ? nil : (L("Finish your prompt, or skip it for now."), false)
        case .notifications:
            return notifications.isDenied ? (L("Notifications are off in iPhone Settings. Skip for now."), false) : nil
        }
    }

    private func phonePrimary() {
        switch phone.stage {
        case .enterNumber: Task { await phone.sendCode() }
        case .enterCode: Task { await phone.verify() }
        case .verified: advance()
        case .locked: showHelp = HelpTopic(id: L("Phone verification"))
        }
    }

    private var age: Int? {
        birthday.flatMap { Calendar.current.dateComponents([.year], from: $0, to: .now).year }
    }
    private var isAdult: Bool { (age ?? 0) >= 18 }

    private var canContinue: Bool {
        complete(current)
    }

    /// `resuming`: photos kept from last time count as checked until the photos step checks them again.
    private func complete(_ s: Step, resuming: Bool = false) -> Bool {
        switch s {
        case .language: true
        case .rules: acceptedTerms
        case .phone: phone.stage == .verified
        case .name: !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .birthday: birthday != nil && isAdult
        case .gender: identity != nil
        case .showMe: !interestedIn.isEmpty
        case .area: area != nil
        case .intent: intent != nil
        case .sports, .rhythm: !sports.isEmpty
        case .photos: !photos.isEmpty && (mainFace == .face || resuming && mainFace == nil)
        case .voice: voice != nil
        case .prompts: !answeredPrompts.isEmpty
        case .lifestyle: lifestyle.hasLifestyle
        case .bio: !bioText.isEmpty && bio.count <= 200
        case .icebreaker: icebreaker.isComplete
        case .notifications: notifications.isAllowed
        }
    }

    private func go(to target: Int) {
        forward = target > step
        withAnimation(Motion.snappy) { step = target }
        furthest = max(furthest, target)
        save()
    }

    // MARK: Resume

    @State private var furthest = 0

    /// Saves everything answered so far, so an unfinished sign-up resumes here.
    private func save() {
        var p = OnboardingProgress()
        p.name = name
        p.language = language.rawValue
        p.birthday = birthday
        p.acceptedTerms = acceptedTerms
        p.verifiedPhone = phone.stage == .verified ? phone.displayNumber : nil
        p.identity = identity
        p.interestedIn = Array(interestedIn)
        p.area = area?.name
        p.intent = intent.map { "\($0)" }
        p.sports = sports.map { .init(sport: $0.sport.rawValue, perWeek: $0.perWeek) }
        p.photos = photos
        p.voicePath = voice?.url.path
        p.voiceDuration = voice?.duration ?? 0
        p.prompts = prompts.map { .init(question: $0.question, answer: $0.answer) }
        p.bio = bio
        p.lifestyle = [lifestyle.chronotype, lifestyle.diet, lifestyle.drinks, lifestyle.smokes]
        p.furthest = furthest
        OnboardingStore.save(p)
    }

    /// Back where they stopped: the first mandatory step not done yet (usually the SMS), otherwise the furthest step reached.
    private func restore() {
        // Apple / Google: prefill only what they really shared (first name, for now).
        if name.isEmpty, let given = app.socialIdentity?.givenName { name = given }
        guard !restored, let p = OnboardingStore.load() else { restored = true; return }
        name = p.name
        if let l = p.language.flatMap(AppLanguage.init(rawValue:)) { language = l; app.language = l }
        birthday = p.birthday
        acceptedTerms = p.acceptedTerms
        if let number = p.verifiedPhone { phone.restoreVerified(number) }
        identity = p.identity
        interestedIn = Set(p.interestedIn)
        if let a = p.area { area = Area(name: a, city: a) }
        intent = Intent.allCases.first { "\($0)" == p.intent }
        sports = p.sports.compactMap { s in Sport(rawValue: s.sport).map { SportEntry(sport: $0, perWeek: s.perWeek) } }
        photos = p.photos.filter { FileManager.default.fileExists(atPath: $0) }
        prompts = p.prompts.map { ProfilePrompt(question: $0.question, answer: $0.answer) }
        bio = p.bio
        if p.lifestyle.count == 4 {
            lifestyle.chronotype = p.lifestyle[0]; lifestyle.diet = p.lifestyle[1]
            lifestyle.drinks = p.lifestyle[2]; lifestyle.smokes = p.lifestyle[3]
        }
        if let path = p.voicePath, FileManager.default.fileExists(atPath: path) {
            voice = (URL(fileURLWithPath: path), p.voiceDuration, [])
        }
        furthest = p.furthest
        restored = true
        let firstMissing = steps.first { !Self.optional.contains($0) && !complete($0, resuming: true) }
        let target = min(firstMissing?.rawValue ?? p.furthest, p.furthest)
        forward = true
        // Clamped: a saved step from an older, longer flow must not index past the steps.
        step = min(max(0, target), steps.count - 1)
    }

    private func advance() {
        guard step < steps.count - 1 else { finish(); return }
        if steps[step + 1].chapter != current.chapter { Haptics.success() } else { Haptics.tap() }
        go(to: step + 1)
    }

    /// The new profile holds only what the person answered: nothing from the demo profile.
    private func finish() {
        var vitals = lifestyle
        vitals.intent = intent
        let p = Profile(
            id: "me",
            name: name.trimmingCharacters(in: .whitespaces),
            age: age ?? 18,
            pronouns: nil,
            neighborhood: area?.name ?? "",
            distanceKm: 0,
            portrait: photos.first ?? "",
            photos: Array(photos.dropFirst()),
            sports: sports,
            voiceIntro: voice?.url.path,
            voiceDuration: voice?.duration ?? 0,
            icebreaker: icebreaker.isComplete ? icebreaker : Icebreaker.Kind.twoTruths.blank,
            favoriteSpot: "",
            bio: bio.count <= 200 ? bioText : "",
            goal: "",
            vitalsOverride: vitals,
            promptsOverride: answeredPrompts
        )
        app.language = language
        app.phoneNumber = phone.displayNumber
        guard let birthday else { return }
        let signUp = ProfileSync.SignUp(
            name: p.name, birthday: birthday, gender: identity, interestedIn: interestedIn,
            neighborhood: area?.name ?? "", location: locator.blurred, intent: intent, bio: p.bio,
            lifestyle: lifestyle, icebreaker: icebreaker.isComplete ? icebreaker : nil, sports: sports,
            prompts: answeredPrompts, photos: photos, voice: voice, language: language)
        finishError = nil
        finishing = true
        Task {
            defer { finishing = false }
            // Signed in: the profile goes to the server first (demo builds without an account skip it).
            if await Backend.shared.hasSession {
                do {
                    try await ProfileSync.finish(signUp)
                } catch {
                    Haptics.warning()
                    finishError = (error as? LocalizedError)?.errorDescription
                        ?? L("Couldn't connect. Check your connection and try again.")
                    return
                }
            }
            Haptics.success()
            app.finishOnboarding(p)
        }
    }

    // MARK: Layout

    private func stepTitle(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(title)
                .font(.display(36))
                .displayLeading(36)
                .foregroundStyle(DS.Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(branded: sub, font: .body).foregroundStyle(DS.Palette.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Every step: its own scroll view with the header and the Continue bar attached as native
    /// safe-area bars, so content scrolls under both with the system's progressive blur.
    private func page<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        FocusScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xxl) { content() }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.lg)
                .padding(.bottom, DS.Space.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .topBar { header }
        .bottomBar { footer.padding(.top, DS.Space.md) }
    }

    /// Field label, same everywhere in the flow (matches DrafftField's title).
    private func label(_ text: String) -> some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.ink)
    }

    /// Hint or error under a field, same everywhere in the flow.
    private func hint(_ text: String, error: Bool = false) -> some View {
        Group {
            if error {
                Label { Text(branded: text, font: .footnote.weight(.medium)) } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(DS.Palette.negative)
            } else {
                // Body grey: mute is under 4.5:1 on the sage page.
                Text(branded: text, font: .footnote).foregroundStyle(DS.Palette.body)
            }
        }
    }

    // MARK: Steps

    private var nameStep: some View {
        page {
            stepTitle(L("What should we call you?"), L("First name only. It's what your matches see."))
            VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
                DrafftField(title: L("First name"), text: $name, prompt: L("Alex"), contentType: .givenName, submitLabel: .done)
                if let id = app.socialIdentity, id.givenName != nil, name == id.givenName {
                    hint(L("From your \(id.provider.rawValue) account. You can change it."))
                }
            }
        }
    }

    private var birthdayStep: some View {
        page {
            stepTitle(L("When's your birthday?"), L("Your profile shows your age, never the date."))
            birthdayField
        }
    }

    /// Community rules, then the required consent (unchecked by default), before anything
    /// personal is asked.
    private var rulesStep: some View {
        page {
            stepTitle(L("A few ground rules"), L("drafft works because everyone plays fair."))
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                fact("person.fill", L("Be yourself"), L("Your own photos, your real first name and your real age."))
                fact("hand.raised.fill", L("Respect first"), L("Kind in chat, clear about what you want. No means no."))
                fact("figure.run", L("Meet where others train"), L("First sessions happen in public places: a park, a club, a court."))
                fact("flag.fill", L("Report anything off"), L("Two taps from any profile or chat. Every report is reviewed."))
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
            consent
                .padding(.vertical, DS.Space.sm)
                .padding(.horizontal, DS.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
        }
    }

    /// Looks and behaves like DrafftField: label, bordered white field, hint below. Tapping it
    /// opens a wheel right under it. No date until the person picks one.
    private var birthdayField: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
            label(L("Birthday"))
            Button {
                Haptics.tap()
                withAnimation(Motion.snappy) { editingBirthday.toggle() }
            } label: {
                HStack {
                    Text(birthday.map { $0.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(.app)) } ?? L("Select your birthday"))
                        .font(.body)
                        .foregroundStyle(birthday == nil ? DS.Palette.mute : DS.Palette.ink)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(DS.Palette.body)
                        .rotationEffect(.degrees(editingBirthday ? 180 : 0))
                }
                .padding(.horizontal, DS.Space.lg)
                .frame(minHeight: 52)
                .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .strokeBorder(editingBirthday ? DS.Palette.ink : DS.Palette.ink.opacity(0.35),
                                      lineWidth: editingBirthday ? 2 : 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(birthday.map { L("Birthday, \($0.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(.app)))") } ?? L("Select your birthday"))

            if editingBirthday {
                VStack(spacing: 0) {
                    DatePicker("Birthday",
                               // Shows a starting point without choosing it: nothing is set until the wheel moves.
                               selection: Binding(get: { birthday ?? Calendar.current.date(byAdding: .year, value: -25, to: .now)! },
                                                  set: { birthday = $0 }),
                               in: Self.oldestBirthday...Self.youngestBirthday, displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    Divider()
                    Button {
                        Haptics.tap()
                        withAnimation(Motion.snappy) { editingBirthday = false }
                    } label: {
                        Text("Done")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(DS.Palette.accentInk)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.md))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let age, birthday != nil {
                if isAdult { hint(L("Your profile will show \(age).")) }
                else { hint(L("You need to be 18 or older to use drafft."), error: true) }
            } else {
                hint(L("drafft is for people 18 and over."))
            }
        }
    }

    /// First question: the app's language, preselected from the phone (English otherwise).
    private var languageStep: some View {
        page {
            stepTitle(L("Pick your language"), L("We've set it to your phone's language. You can change it anytime in You."))
            VStack(spacing: 0) {
                ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element) { i, l in
                    if i > 0 { Divider().padding(.leading, DS.Space.lg) }
                    Button {
                        Haptics.select()
                        language = l
                        // The rest of sign-up switches to it straight away, one frame after
                        // the row so the selection shows at once.
                        DispatchQueue.main.async { app.language = l }
                    } label: {
                        HStack {
                            Text(l.name).font(.body.weight(language == l ? .semibold : .regular)).foregroundStyle(DS.Palette.ink)
                                .instantWeight()
                            Spacer()
                            CheckDisc(isOn: language == l)
                        }
                        .padding(.horizontal, DS.Space.lg)
                        .frame(minHeight: 52)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(language == l ? .isSelected : [])
                }
            }
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
        }
    }

    private var phoneStep: some View {
        page {
            stepTitle(L("What's your number?"), L("Everyone on drafft verifies a phone number. It keeps fake accounts out."))
            PhoneVerificationView(model: phone)
        }
    }

    private var notificationsStep: some View {
        page {
            stepTitle(L("Don't miss a match"), L("Get told when someone likes you back, writes to you, or a session is coming up."))
            VStack(alignment: .leading, spacing: DS.Space.md) {
                ForEach([("heart.fill", L("New matches and likes")), ("bubble.left.fill", L("Messages, without the text unless you want it")),
                         ("alarm.fill", L("Session reminders, the evening before and an hour before"))], id: \.1) { icon, text in
                    HStack(spacing: DS.Space.md) {
                        Image(systemName: icon)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(DS.Palette.ink)
                            .frame(width: 32, height: 32)
                            .background(DS.Palette.canvasSoft, in: .circle)
                        Text(text).font(.subheadline).foregroundStyle(DS.Palette.ink)
                    }
                }
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
            if notifications.isAllowed {
                hint(L("Notifications are on. Fine-tune them anytime in You › Notifications."))
            } else if notifications.isDenied {
                hint(L("Notifications are off. You can turn them on later in iPhone Settings."), error: true)
            } else {
                hint(L("You choose what you hear about in You › Notifications."))
            }
        }
        .task { await notifications.refresh() }
    }

    /// Drafft is 18+: the wheel can't go past the date you turned 18.
    static var youngestBirthday: Date { Calendar.current.date(byAdding: .year, value: -18, to: .now)! }
    static var oldestBirthday: Date { Calendar.current.date(byAdding: .year, value: -100, to: .now)! }

    /// Required consent, unchecked by default. The checkbox toggles; the document names in the
    /// sentence are links that open each document.
    private var consent: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Button {
                Haptics.select()
                acceptedTerms.toggle()
            } label: {
                DrafftCheckbox(isOn: acceptedTerms)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("I'm 18 or older and I accept the Terms of Use, the Privacy Policy and the Community Guidelines")
            .accessibilityAddTraits(acceptedTerms ? .isSelected : [])

            Text(consentText)
                .font(.subheadline)
                .foregroundStyle(DS.Palette.ink)
                .tint(DS.Palette.accentInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 11) // Level with the box on top, the same room under the last line.
                .environment(\.openURL, OpenURLAction { url in
                    legalDoc = LegalDoc(rawValue: url.lastPathComponent)
                    return .handled
                })
        }
        .padding(.leading, -DS.Space.sm)
        .sheet(item: $legalDoc) { item in Group { LegalDocSheet(doc: item) }.sheetSurface() }
    }

    private var consentText: AttributedString {
        // One sentence for translators; the document names in it become the links.
        let terms = LegalDoc.terms.title, privacy = LegalDoc.privacy.title, community = LegalDoc.community.title
        var s = AttributedString(L("I'm 18 or older and I accept the \(terms), the \(privacy) and the \(community)."))
        for doc in LegalDoc.allCases {
            guard let r = s.range(of: doc.title) else { continue }
            s[r].link = URL(string: "drafft://legal/\(doc.rawValue)")
            s[r].underlineStyle = .single
            s[r].font = .subheadline.weight(.semibold)
        }
        return s
    }

    private var genderStep: some View {
        page {
            stepTitle(L("Which describes you best?"), L("You can change it anytime in You."))
            choiceRows(["Woman", "Man", "Non-binary"], isOn: { identity == $0 }) { o in
                identity = identity == o ? nil : o
            }
        }
    }

    private var showMeStep: some View {
        page {
            stepTitle(L("Who do you want to meet?"), L("Pick as many as you like."))
            choiceRows(["Women", "Men", "Non-binary people", "Everyone"], isOn: { interestedIn.contains($0) }) { o in
                if o == "Everyone" { interestedIn = interestedIn.contains(o) ? [] : ["Everyone"]; return }
                interestedIn.remove("Everyone")
                if interestedIn.contains(o) { interestedIn.remove(o) } else { interestedIn.insert(o) }
            }
        }
    }

    /// The options are stored in English; this is what the rows show.
    private func choiceTitle(_ option: String) -> String {
        switch option {
        case "Woman": L("Woman")
        case "Man": L("Man")
        case "Non-binary": L("Non-binary")
        case "Women": L("Women")
        case "Men": L("Men")
        case "Non-binary people": L("Non-binary people")
        case "Everyone": L("Everyone")
        default: option
        }
    }

    /// A white block of rows, each with the one selection mark (`CheckDisc`). Same as the language list.
    private func choiceRows(_ options: [String], isOn: @escaping (String) -> Bool, toggle: @escaping (String) -> Void) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { i, o in
                if i > 0 { Divider().padding(.leading, DS.Space.lg) }
                Button {
                    Haptics.select()
                    withAnimation(Motion.select) { toggle(o) }
                } label: {
                    HStack {
                        Text(choiceTitle(o)).font(.body.weight(isOn(o) ? .semibold : .regular)).foregroundStyle(DS.Palette.ink)
                        Spacer()
                        CheckDisc(isOn: isOn(o))
                    }
                    .padding(.horizontal, DS.Space.lg)
                    .frame(minHeight: 52)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn(o) ? .isSelected : [])
            }
        }
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
    }

    /// Where they train: location is required (at least while using the app). No typing: the
    /// area comes from a blurred position, resolved by the server. Denied: Continue stays off
    /// and the footer sends them to Settings.
    private var areaStep: some View {
        page {
            stepTitle(L("Where do you train?"), L("drafft needs your location to show people near you. We show your area, never your address."))
            VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
                label(L("Your area"))
                HStack(spacing: DS.Space.md) {
                    Group {
                        if let area {
                            CheckDisc(isOn: true)
                            Text(area.name).font(.body.weight(.semibold)).foregroundStyle(DS.Palette.ink)
                        } else if locator.state == .locating {
                            ProgressView().tint(DS.Palette.ink)
                            Text("Finding your area…").foregroundStyle(DS.Palette.body)
                        } else {
                            Image(systemName: "location.slash.fill").foregroundStyle(DS.Palette.mute)
                            Text("Location not shared yet").foregroundStyle(DS.Palette.mute)
                        }
                    }
                    .font(.body)
                    Spacer()
                }
                .padding(.horizontal, DS.Space.lg)
                .frame(minHeight: 52)
                .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.md))
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .strokeBorder(locator.state == .denied ? DS.Palette.negative : DS.Palette.ink.opacity(0.35),
                                      lineWidth: locator.state == .denied ? 2 : 1)
                }
                switch locator.state {
                case .denied:
                    hint(L("Location is off for drafft. Turn it on in Settings (While Using the App is enough) to continue."), error: true)
                case .failed:
                    hint(L("We couldn't find your area. Try again."), error: true)
                default:
                    EmptyView()
                }
            }
            locationFacts
        }
        .onChange(of: locator.state) { _, state in
            if case .found(let a) = state {
                Haptics.success()
                withAnimation(Motion.snappy) { area = a }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from Settings: try again.
            if phase == .active, area == nil, locator.state == .denied || locator.state == .failed { locator.locate() }
        }
    }

    /// How location works, plainly: when it updates, how it's blurred, what others see.
    private var locationFacts: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            fact("arrow.triangle.2.circlepath", L("Updates as you move"),
                 L("Each time you open drafft, your area follows you: home, work, a weekend away."))
            fact("circle.dotted.circle", L("Blurred before it leaves your phone"),
                 L("Your position is rounded to about 1 km. Your exact spot is never sent or stored."))
            fact("eye", L("What others see"),
                 L("Your area, like a district, and a distance rounded to the kilometre. Never your address."))
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
    }

    private func fact(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(systemName: icon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(DS.Palette.ink)
                .frame(width: 32, height: 32)
                .background(DS.Palette.canvasSoft, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(DS.Palette.ink)
                Text(branded: text, font: .footnote).foregroundStyle(DS.Palette.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func areaPrimary() {
        if area != nil { advance(); return }
        if locator.state == .denied {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        } else {
            locator.locate()
        }
    }

    private var intentStep: some View {
        page {
            stepTitle(L("What are you training for?"), L("Shown on your profile so nobody's guessing. Skip it to keep it private."))
            IntentPicker(selection: $intent)
        }
    }

    /// Step 1 of 2 for sports: pick them.
    private var sportsStep: some View {
        page {
            stepTitle(L("How do you move?"), L("Pick up to 5 sports. Next, how often you do each."))
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                SportPicker(selected: sports.map(\.sport), limit: 5) { s in
                    if sports.contains(where: { $0.sport == s }) { sports.removeAll { $0.sport == s } }
                    else if sports.count < 5 { sports.append(.init(sport: s)) }
                }
                hint(sports.count >= 5 ? L("That's 5. Remove one to pick another.") : L("\(sports.count) of 5 picked"))
            }
        }
    }

    /// Step 2 of 2 for sports: how often.
    private var rhythmStep: some View {
        page {
            stepTitle(L("How often?"), L("Sessions a week for each sport. Rough is fine."))
            VStack(spacing: DS.Space.sm) {
                ForEach($sports) { $entry in
                    HStack {
                        Label(entry.sport.name, systemImage: entry.sport.symbol)
                            .font(.headline)
                            .foregroundStyle(DS.Palette.ink)
                        Spacer()
                        FrequencyStepper(value: $entry.perWeek, sport: entry.sport.name)
                    }
                    .padding(.leading, DS.Space.lg)
                    .padding(.trailing, DS.Space.sm)
                    .padding(.vertical, DS.Space.sm)
                    .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.lg))
                }
            }
        }
    }

    private var photosStep: some View {
        page {
            stepTitle(L("Show you in motion"), L("Add at least one clear face photo and one mid-session. Up to 6."))
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                ReorderablePhotoGrid(
                    photos: $photos,
                    slots: 6,
                    addButton: {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            RoundedRectangle(cornerRadius: DS.Radius.lg)
                                .strokeBorder(DS.Palette.ink.opacity(0.25), style: .init(lineWidth: 1.5, dash: [6, 5]))
                                .background(DS.Palette.canvas.opacity(0.6), in: .rect(cornerRadius: DS.Radius.lg))
                                .overlay {
                                    Image(systemName: "plus").font(.title2.weight(.semibold)).foregroundStyle(DS.Palette.ink)
                                }
                        }
                        .accessibilityLabel("Add photo")
                    },
                    onRemove: { i in withAnimation(Motion.snappy) { _ = photos.remove(at: i) } },
                    canRemoveLast: true
                )
                mainFaceHint
            }
            DemoPanel(title: L("Face on the first photo"), selection: $demoFace)
        }
        .task(id: [photos.first ?? "", demoFace.rawValue]) { await checkMainFace() }
    }

    /// The first photo must show a face: it's the one people see first.
    @ViewBuilder
    private var mainFaceHint: some View {
        if photos.isEmpty {
            hint(L("Your first photo needs to show your face clearly."))
        } else {
            switch mainFace {
            case nil:
                HStack(spacing: DS.Space.xs) {
                    ProgressView().controlSize(.mini)
                    Text("Checking your first photo…").font(.footnote).foregroundStyle(DS.Palette.body)
                }
            case .face?:
                EmptyView() // all good: nothing to say
            case .noFace?:
                hint(L("We can't see a face on your first photo. Put a clear photo of you first."), error: true)
            case .tooSmall?:
                hint(L("Your face is too small on your first photo. Use a closer one first."), error: true)
            }
        }
    }


    private func checkMainFace() async {
        mainFace = nil
        guard let first = photos.first else { return }
        switch demoFace {
        case .pass: mainFace = .face
        case .fail: mainFace = .noFace
        case .real: mainFace = await FaceCheck.check(photo: first)
        }
    }


    private func addPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("photo-\(UUID().uuidString).jpg")
        guard (try? data.write(to: url)) != nil else { return }
        let kept = OnboardingStore.persist(photo: url.path)
        // Sent to the backend: compressed, uploaded, then judged by moderation (the tile shows it).
        PhotoModeration.shared.submit(kept)
        withAnimation(Motion.snappy) { photos.append(kept) }
        Haptics.success()
    }

    private var voiceStep: some View {
        page {
            stepTitle(L("Say hi, out loud"), L("A 15-second voice intro. No pressure, you can redo it."))
            VoiceIntroRecorder(result: $voice)
            // In a block, like every text on the page (no loose text on the canvas).
            VStack(alignment: .leading, spacing: DS.Space.md) {
                label(L("Stuck? Talk about"))
                // One symbol per idea (never the same one repeated down a list).
                ForEach([("sun.max", L("What your perfect Sunday session looks like")),
                         ("flag.checkered", L("The race you'd love to finish")),
                         ("fork.knife", L("Your post-workout food ritual"))], id: \.1) { icon, text in
                    Label(text, systemImage: icon).font(.subheadline).foregroundStyle(DS.Palette.body)
                }
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
        }
    }

    private var bioText: String { bio.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Right after "what are you training for": the rest of your routine, all optional.
    private var lifestyleStep: some View {
        page {
            stepTitle(L("Your routine"), L("Shown on your profile. Answer what you like, leave the rest."))
            LifestylePicker(vitals: $lifestyle)
                .padding(DS.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
        }
    }

    /// Right after the photos: the two lines under your name.
    private var bioStep: some View {
        page {
            stepTitle(L("A few words about you"), L("Two lines under your name: how you train, and what you're like after."))
            DrafftTextArea(title: L("Bio"), text: $bio, prompt: L("Weekday dawn runner, weekend long rides…"))
        }
    }

    /// Bound by question, not position: removing a card never reads a stale index.
    private func answerBinding(_ id: String) -> Binding<String> {
        Binding(get: { prompts.first { $0.id == id }?.answer ?? "" },
                set: { v in if let i = prompts.firstIndex(where: { $0.id == id }) { prompts[i].answer = v } })
    }

    private var answeredPrompts: [ProfilePrompt] {
        prompts.filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Written prompts: pick a question, answer it. Up to 3, all optional. Nothing is filled in
    /// for the person.
    private var promptsStep: some View {
        page {
            stepTitle(L("Answer a prompt"), L("Up to 3 short answers on your profile. People like one to start a chat."))
            VStack(spacing: DS.Space.sm) {
                ForEach(Array(prompts.enumerated()), id: \.element.id) { i, prompt in
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        HStack(alignment: .top) {
                            Button { pickingPrompt = i } label: {
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
                            .accessibilityLabel("Question: \(prompt.questionText). Change it")
                            Spacer()
                            Button {
                                Haptics.tap()
                                promptFocus = nil
                                withAnimation(Motion.snappy) { prompts.removeAll { $0.id == prompt.id } }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DS.Palette.body)
                                    .frame(width: 44, height: 44)
                                    .contentShape(.rect)
                            }
                            .accessibilityLabel("Remove this prompt")
                        }
                        HStack(alignment: .bottom, spacing: DS.Space.sm) {
                            TextField("Your answer", text: answerBinding(prompt.id), axis: .vertical)
                                .lineLimit(2...5)
                                .font(.body.weight(.semibold))
                                .focused($promptFocus, equals: i)
                                .frame(minHeight: 44, alignment: .topLeading)
                                .inputStyle(focused: promptFocus == i, fill: DS.Palette.canvasSoft)
                                .revealsOnFocus(promptFocus == i)
                            if promptFocus == i {
                                // Done with this answer: closes the keyboard, stays on the step.
                                Button {
                                    Haptics.tap()
                                    promptFocus = nil
                                } label: {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.heavy))
                                        .foregroundStyle(DS.Palette.onLime)
                                        .frame(width: 44, height: 44)
                                        .background(DS.Palette.lime, in: .circle)
                                }
                                .buttonStyle(PressScaleStyle())
                                .accessibilityLabel("Done with this answer")
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .animation(Motion.snappy, value: promptFocus)
                    }
                    .padding(DS.Space.md)
                    .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.lg))
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
                if prompts.count < 3 {
                    Button {
                        Haptics.select()
                        // The question is chosen in the picker; the card only appears once one is picked.
                        pickingPrompt = prompts.count
                    } label: {
                        Label(prompts.isEmpty ? "Choose a prompt" : "Add another prompt", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Palette.accentInk)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.lg))
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.98))
                }
            }
        }
        .sheet(item: Binding(get: { pickingPrompt.map(PromptSlot.init) }, set: { pickingPrompt = $0?.id })) { slot in
            Group {
                PromptPickerSheet(current: prompts.indices.contains(slot.id) ? prompts[slot.id].question : nil,
                                  used: Set(prompts.map(\.question))) { q in
                    if prompts.indices.contains(slot.id) {
                        prompts[slot.id].question = q
                    } else {
                        withAnimation(Motion.snappy) { prompts.append(.init(question: q, answer: "")) }
                    }
                }
            }
            .sheetSurface()
        }
    }

    private var icebreakerStep: some View {
        page {
            stepTitle(L("Give them an easy opener"), L("Pick a format for your interactive prompt. Matches play it and reply in one tap."))
            IcebreakerEditor(icebreaker: $icebreaker)
        }
    }
}

/// Sign-up stepper: one bar per chapter, filling step by step, with the chapter names under
/// it (the current one bold, finished ones ticked, the next ones quieter).
struct ChapterStepper: View {
    let chapters: [(title: String, steps: Int)]
    /// Index of the current step across the whole flow.
    let current: Int

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            ForEach(Array(chapters.enumerated()), id: \.offset) { i, chapter in
                let start = chapters.prefix(i).reduce(0) { $0 + $1.steps }
                let done = current >= start + chapter.steps
                let active = !done && current >= start
                let fill = done ? 1 : active ? CGFloat(current - start + 1) / CGFloat(max(1, chapter.steps)) : 0
                VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
                    Capsule()
                        .fill(DS.Palette.ink.opacity(0.12))
                        .overlay(alignment: .leading) {
                            GeometryReader { g in
                                Capsule().fill(DS.Palette.ink).frame(width: g.size.width * fill)
                            }
                        }
                        .frame(height: 4)
                    HStack(spacing: 3) {
                        if done {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.heavy))
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text(chapter.title)
                            .font(.caption.weight(active ? .bold : .semibold))
                            .instantWeight()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(active || done ? DS.Palette.ink : DS.Palette.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(Motion.snappy, value: current)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var start = 0
        for (i, c) in chapters.enumerated() {
            if current < start + c.steps {
                return L("\(c.title), step \(current - start + 1) of \(c.steps). Part \(i + 1) of \(chapters.count).")
            }
            start += c.steps
        }
        return L("Sign-up complete")
    }
}

/// Compact − n× a week + control.
struct FrequencyStepper: View {
    @Binding var value: Int
    let sport: String

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            button("minus", enabled: value > 1) { value -= 1 }
            Text(value >= 7 ? "Every day" : "\(value)× a week")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(DS.Palette.ink)
                .frame(minWidth: 84)
                .rollingDigits(wording: value >= 7)
            button("plus", enabled: value < 7) { value += 1 }
        }
        .animation(Motion.snappy, value: value)
        .accessibilityElement()
        .accessibilityLabel("\(sport) sessions per week")
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: if value < 7 { value += 1 }
            case .decrement: if value > 1 { value -= 1 }
            @unknown default: break
            }
        }
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.select()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.footnote.weight(.heavy))
                .foregroundStyle(enabled ? DS.Palette.ink : DS.Palette.mute)
                .frame(width: 36, height: 36)
                .background(DS.Palette.canvasSoft, in: .circle)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!enabled)
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    /// Each chip is measured once per layout pass and reused for sizing and placing
    /// (the sports picker has 80+ chips; measuring them on every call made sheets open late).
    struct Cache { var sizes: [CGSize] }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in cache.sizes {
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for (v, s) in zip(subviews, cache.sizes) {
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

/// Pick what you're looking for, in Drafft's training vocabulary. Tapping the selected option clears it.
struct IntentPicker: View {
    @Binding var selection: Intent?
    var onChange: () -> Void = {}

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            ForEach(Intent.allCases) { option in
                let on = selection == option
                Button {
                    Haptics.select()
                    withAnimation(Motion.select) { selection = on ? nil : option }
                    onChange()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                        Image(systemName: option.symbol)
                            .font(.body.weight(.bold))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label).font(.body.weight(.semibold))
                            // White on the accent only in semibold, at full strength.
                            Text(option.detail)
                                .font(.footnote.weight(on ? .semibold : .regular))
                                .instantWeight()
                                .opacity(on ? 1 : 0.75)
                        }
                        Spacer(minLength: 0)
                        CheckDisc(isOn: on, onLimeFill: on)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
                    }
                    .foregroundStyle(on ? DS.Palette.onLime : DS.Palette.ink)
                    .padding(DS.Space.lg)
                    .background(on ? AnyShapeStyle(DS.Palette.lime) : AnyShapeStyle(DS.Palette.canvas), in: .rect(cornerRadius: DS.Radius.lg))
                }
                .buttonStyle(PressScaleStyle(scale: 0.98))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Text("Tap again to unselect.")
                .font(.footnote)
                .foregroundStyle(DS.Palette.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
