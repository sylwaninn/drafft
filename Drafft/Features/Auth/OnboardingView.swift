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
    @State private var consent = ConsentDraft()
    /// The terms version the server recorded with the consent this sign-up (`accept_terms`).
    @State private var recordedTerms: String?
    @State private var recordingConsent = false
    @State private var consentError: String?
    @State private var language: AppLanguage = .deviceDefault
    @State private var identity: String?
    @State private var interestedIn: Set<String> = []
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
    @State private var voice: (url: URL, duration: TimeInterval, levels: [Float])?
    @State private var icebreaker: Icebreaker = Icebreaker.Kind.twoTruths.blank
    /// Written prompts (up to 3): a question from the library and their answer.
    @State private var prompts: [ProfilePrompt] = []
    /// Lifestyle answers.
    @State private var lifestyle = Vitals.blank
    @State private var bio = ""
    @State private var pickingPrompt: Int?
    @FocusState private var promptFocus: Int?
    /// The last step sends the profile to the server: spinner, then the server's reason if it refuses.
    @State private var finishing = false
    @State private var finishError: String?
    /// A picked photo that couldn't be opened, until the next pick.
    @State private var photoError: String?

    /// One question per step, grouped in four chapters shown in the stepper: secure the
    /// account, say who you are, how you move, then what people see.
    enum Step: Int, CaseIterable {
        case language, rules, phone
        case name, birthday, gender, showMe, lifestyle, area
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
            case .name, .birthday, .gender, .showMe, .lifestyle, .area: .you
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
        // One header for the whole flow, outside the sliding steps: it never moves with them, and the
        // stepper stays the same view, so its bars fill and its chapters change in place.
        .topBar { header }
        // A different terrain per step, cross-fading as the steps change.
        .background { Rectangle().fill(DS.Palette.canvasSoft).ignoresSafeArea() }
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
        OnboardingHeader(chapters: Step.Chapter.allCases.map { c in (c.title, steps.filter { $0.chapter == c }.count) },
                         step: step, skippable: skippable, confirmLeave: $confirmLeave,
                         back: { go(to: step - 1) }, skip: advance,
                         leave: {
                             // Leaving on purpose starts over: nothing is kept.
                             OnboardingStore.clear()
                             app.signOut()
                         })
    }

    /// The phone check is mandatory: never skippable.
    private var skippable: Bool { Self.optional.contains(current) }
    private static let optional: Set<Step> = [.lifestyle, .bio, .voice, .prompts, .icebreaker, .notifications]

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
                    else { Label(locator.state == .denied ? "Open Settings" : "Allow location", image: "map-point") }
                }
                .disabled(locator.state == .locating)
            } else if current == .notifications && notifications.permission != .allowed {
                PermissionButton(permission: notifications, askTitle: "Turn on notifications", symbol: "bell")
            } else {
                Button(action: advance) {
                    if finishing || recordingConsent {
                        ProgressView().tint(DS.Palette.onLime)
                    } else {
                        Text(step == steps.count - 1 ? "Start swiping" : "Continue")
                    }
                }
                .disabled(!canContinue || finishing || recordingConsent)
            }
        }
    }

    /// One line under the button: why it can't run yet. The line keeps its height when empty,
    /// so the button never jumps.
    @ViewBuilder // Only a real error under Continue: the step itself says what's missing.
    private var footerReason: some View {
        if let r = blockedReason, r.error {
            Text(branded: r.text, font: .footnote.weight(.medium))
                .foregroundStyle(DS.Palette.negative)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DS.Space.xl)
                .transition(.opacity)
        }
    }

    private var blockedReason: (text: String, error: Bool)? {
        if let finishError, step == steps.count - 1 { return (finishError, true) }
        if let consentError, current == .rules { return (consentError, true) }
        switch current {
        case .language: return nil
        case .rules: return complete(.rules) ? nil : (L("Accept the rules and terms to continue."), false)
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
        case .lifestyle: return lifestyle.hasLifestyle ? nil : (L("Answer one, or skip it for now."), false)
        case .bio:
            if bio.count > 200 { return (L("Keep it under 200 characters."), true) }
            return bioText.isEmpty ? (L("Write a few words, or skip it for now."), false) : nil
        case .area: return area == nil && locator.state == .locating ? (L("Finding your area…"), false) : nil
        case .sports: return sports.isEmpty ? (L("Pick at least one sport."), false) : nil
        case .rhythm: return nil
        case .photos:
            if let photoError { return (photoError, true) }
            return photosCheck.reason.map { ($0, photosCheck.needsAction) }
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
        // Once the server holds the consent for these terms, the boxes no longer matter.
        case .rules: consent.isComplete || TermsConsent.isCurrent(recordedTerms)
        case .phone: phone.stage == .verified
        case .name: !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .birthday: birthday != nil && isAdult
        case .gender: identity != nil
        case .showMe: !interestedIn.isEmpty
        case .area: area != nil
        case .sports, .rhythm: !sports.isEmpty
        case .photos: resuming ? !photos.isEmpty : photosCheck == .ready
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
        p.termsVersion = recordedTerms
        p.verifiedPhone = phone.stage == .verified ? phone.displayNumber : nil
        p.identity = identity
        p.interestedIn = Array(interestedIn)
        p.area = area?.name
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
        guard !restored, let p = OnboardingStore.load() else { restored = true; return }
        name = p.name
        if let l = p.language.flatMap(AppLanguage.init(rawValue:)) { language = l; app.language = l }
        birthday = p.birthday
        // Ticked again only if the server recorded them for the terms shown now.
        recordedTerms = p.termsVersion
        consent = .restored(recordedVersion: p.termsVersion)
        if let number = p.verifiedPhone { phone.restoreVerified(number) }
        identity = p.identity
        interestedIn = Set(p.interestedIn)
        if let a = p.area { area = Area(name: a, city: a) }
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
        if current == .rules, !TermsConsent.isCurrent(recordedTerms) { recordConsent(); return }
        guard step < steps.count - 1 else { finish(); return }
        if steps[step + 1].chapter != current.chapter { Haptics.success() } else { Haptics.tap() }
        go(to: step + 1)
    }

    /// Both consents go to the server before anything personal is asked; the step moves on once
    /// they're recorded, or says why not.
    private func recordConsent() {
        consentError = nil
        recordingConsent = true
        Task {
            defer { recordingConsent = false }
            do {
                try await TermsConsent.accept()
                recordedTerms = TermsConsent.version
                advance()
            } catch {
                Haptics.warning()
                switch TermsConsent.failure(for: error) {
                case .signOut: await app.endSession()
                case .message(let text): consentError = text
                }
            }
        }
    }

    /// The new profile holds only what the person answered: nothing from the demo profile.
    private func finish() {
        var vitals = lifestyle
        let p = Profile(
            id: "me",
            name: name.trimmingCharacters(in: .whitespaces),
            age: age ?? 18,
            pronouns: nil, birthday: birthday, gender: identity.flatMap(DiscoverFilters.Audience.init(answer:)),
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
        guard let birthday else { Haptics.warning(); go(to: Step.birthday.rawValue); return } // lost from a restored draft
        let signUp = ProfileSync.SignUp(
            name: p.name, birthday: birthday, gender: identity, interestedIn: interestedIn,
            neighborhood: area?.name ?? "", location: locator.blurred, bio: p.bio,
            lifestyle: lifestyle, icebreaker: icebreaker.isComplete ? icebreaker : nil, sports: sports,
            prompts: answeredPrompts, photos: photos, voice: voice, language: language)
        finishError = nil
        finishing = true
        Task {
            defer { finishing = false }
            // The profile goes to the server first; without a session it fails and says so.
            do {
                try await ProfileSync.finish(signUp)
            } catch ProfileSync.SyncError.refused("terms_required") {
                // The server has no consent on record (the one noted on this phone was lost there):
                // back to the rules step, unticked, to record it again.
                TermsConsent.log.error("complete_onboarding: terms_required although the sign-up recorded them")
                Haptics.warning()
                recordedTerms = nil
                consent = ConsentDraft()
                consentError = ServerMessage.text(forCode: "terms_required")
                go(to: Step.rules.rawValue)
                return
            } catch {
                Haptics.warning()
                finishError = ProfileSync.failure(error, photos: photosCheck)
                return
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

    /// Every step: its own scroll view with the Continue bar attached as a native safe-area bar (the
    /// header is pinned once, on the whole flow), so content scrolls under both with the progressive blur.
    private func page<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        FocusScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xxl) { content() }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.lg)
                .padding(.bottom, DS.Space.xl)
        }
        .scrollDismissesKeyboard(.interactively)
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
                    Image("danger-circle")
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
                DrafftField(title: L("First name"), text: $name, prompt: L("Alex"), contentType: .givenName, submitLabel: .done, limit: 40)
            }
        }
    }

    private var birthdayStep: some View {
        page {
            stepTitle(L("When's your birthday?"), L("Your profile shows your age, never the date."))
            birthdayField
        }
    }

    /// Community rules, then the two required consents (unchecked by default), before anything
    /// personal is asked.
    private var rulesStep: some View {
        page {
            stepTitle(L("A few ground rules"), L("drafft works because everyone plays fair."))
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                fact("user-rounded", L("Be yourself"), L("Your own photos, your real first name and your real age."))
                fact("user-block", L("Respect first"), L("Kind in chat, clear about what you want. No means no."))
                fact("running", L("Meet where others train"), L("First sessions happen in public places: a park, a club, a court."))
                fact("flag", L("Report anything off"), L("Two taps from any profile or chat. Every report is reviewed."))
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
            ConsentChecks(draft: $consent)
                .onChange(of: consent) { consentError = nil }
        }
    }

    /// Typed in three boxes (no wheel, no made-up starting date), then the age it gives, or why not.
    private var birthdayField: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
            label(L("Birthday"))
            BirthdateField(date: $birthday, oldest: Self.oldestBirthday)

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
                            Text(l.name).font(.body.weight(.medium)).foregroundStyle(DS.Palette.ink)
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
                ForEach([("heart", L("New matches and likes")), ("chat-round-line", L("Messages, without the text unless you want it")),
                         ("alarm", L("Session reminders, the evening before and an hour before"))], id: \.1) { icon, text in
                    HStack(spacing: DS.Space.md) {
                        Image(icon)
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
    }

    static var oldestBirthday: Date { Calendar.current.date(byAdding: .year, value: -100, to: .now)! }

    private var genderStep: some View {
        page {
            stepTitle(L("Which describes you best?"), L("You can't change it later. If it's ever wrong, write to the help center in You."))
            choiceRows(["Woman", "Man", "Non-binary"], isOn: { identity == $0 }) { o in
                identity = identity == o ? nil : o
            }
        }
    }

    private var showMeStep: some View {
        page {
            stepTitle(L("Who do you want to meet?"), L("Pick as many as you like. This never shows on your profile."))
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
                        Text(choiceTitle(o)).font(.body.weight(.medium)).foregroundStyle(DS.Palette.ink)
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
                            Image("map-point-remove").foregroundStyle(DS.Palette.mute)
                            Text("Location not shared yet").foregroundStyle(DS.Palette.mute)
                        }
                    }
                    .font(.body)
                    Spacer()
                }
                .padding(.horizontal, DS.Space.lg)
                .frame(minHeight: 52)
                .background(DS.Palette.field, in: .rect(cornerRadius: DS.Radius.md))
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

    /// How location works, plainly: when it's read, how it's blurred, what others see.
    private var locationFacts: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            fact("map-point", L("Read once, not tracked"),
                 L("Your area comes from where you are right now. drafft doesn't follow your moves or track you in the background."))
            fact("radial-blur", L("Blurred before it leaves your phone"),
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
            Image(icon)
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
                        Label(entry.sport.name, image: entry.sport.symbol)
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
                                    Image("add").font(.title2.weight(.semibold)).foregroundStyle(DS.Palette.ink)
                                }
                        }
                        .accessibilityLabel("Add photo")
                    },
                    onRemove: { i in
                        // A draft on the server until sign-up ends: taken off the grid, it goes.
                        PhotoModeration.shared.discard([photos[i]])
                        withAnimation(Motion.snappy) { _ = photos.remove(at: i) }
                    },
                    canRemoveLast: true
                )
                PhotoSetHint(check: photosCheck)
            }
        }
        .task(id: photos.first ?? "") { await checkMainFace() }
        // A sign-up resumed after the app was closed: each photo's verdict read again (or sent again).
        .task(id: photos) { photos.forEach(PhotoModeration.shared.ensureChecked) }
        .onChange(of: photos) { photoError = nil }
    }

    private var photosCheck: PhotoSetCheck { .of(photos, face: mainFace) }

    private func checkMainFace() async {
        mainFace = nil
        let face = await PhotoSetCheck.face(of: photos.first)
        // The first photo changed meanwhile: its own check answers.
        guard !Task.isCancelled else { return }
        mainFace = face
    }


    private func addPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        photoError = nil
        // An iCloud photo that can't download (offline), or a format that won't decode: said, never a
        // pick that does nothing.
        guard let data = try? await item.loadTransferable(type: Data.self),
              let path = await PhotoCompressor.savePicked(data) else {
            Haptics.warning()
            photoError = L("This photo couldn't be opened. Pick another one, or check your connection.")
            return
        }
        let kept = OnboardingStore.persist(photo: path)
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
                ForEach([("sun", L("What your perfect Sunday session looks like")),
                         ("flag-2", L("The race you'd love to finish")),
                         ("chef-hat", L("Your post-workout food ritual"))], id: \.1) { icon, text in
                    Label(text, image: icon).font(.subheadline).foregroundStyle(DS.Palette.body)
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
            LifestylePicker(vitals: $lifestyle, gender: identity.flatMap { DiscoverFilters.Audience(answer: $0) })
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
                                    Image("chevrons-up-down").font(.caption2.weight(.bold))
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
                                Image("trash-bin-minimalistic")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DS.Palette.body)
                                    .frame(width: 44, height: 44)
                                    .contentShape(.rect)
                            }
                            .accessibilityLabel("Remove this prompt")
                        }
                        HStack(alignment: .bottom, spacing: DS.Space.sm) {
                            TextField("Your answer", text: answerBinding(prompt.id), axis: .vertical)
                                .lineLimit(2...5).maxLength(300, of: answerBinding(prompt.id))
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
                                    Image("check")
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
                        Label(prompts.isEmpty ? "Choose a prompt" : "Add another prompt", image: "add")
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
            button("add", enabled: value < 7) { value += 1 }
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
            Image(symbol)
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
