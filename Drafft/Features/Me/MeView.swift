import SwiftUI

/// The "You" tab: your card at the top, then settings grouped by what people come here to do.
struct MeView: View {
    @Environment(AppModel.self) private var app
    @State private var sheet: MeSheet?
    @State private var confirmLogout = false
    @State private var scrollOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum MeSheet: String, Identifiable {
        case edit, preview, filters, email, phone, password, export, delete, paywall, notifications, language
        case blocked, safety, help, legal, consent, subscription
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Space.md) {
                    // While paused, a strip slides out from under the card: the card and what
                    // it says about you, then that no one sees it for now.
                    VStack(spacing: -DS.Radius.xl) {
                        profileCard.zIndex(1)
                        if app.profilePaused {
                            PausedStrip()
                                .transition(reduceMotion ? .opacity : .move(edge: .top))
                        }
                    }
                    if !app.isPremium { plusCard }
                    group(L("Discovery")) {
                        row(L("Filters"), icon: "tuning-2", value: filtersSummary) { sheet = .filters }
                        separator
                        toggleRow(L("Pause my profile"), icon: "pause",
                                  // One text, on or off: the strip under the card says it's on.
                                  detail: L("Hides you from Discover and likes. Your chats and sessions carry on."),
                                  tint: DS.Palette.paused, isOn: $app.profilePaused)
                    }
                    group(L("Preferences")) {
                        row(L("Notifications"), icon: "bell",
                            value: NotificationService.shared.isAllowed ? L("Matches, messages, sessions") : L("Off")) { sheet = .notifications }
                        separator
                        row(L("Language"), icon: "global", value: app.language.name) { sheet = .language }
                    }
                    group(L("Account")) {
                        row(L("Email"), icon: "letter", value: app.email) { sheet = .email }
                        separator
                        row(L("Phone"), icon: "phone", value: app.phoneNumber ?? L("Add your number")) { sheet = .phone }
                        separator
                        row(L("Password"), icon: "key", value: L("Change your password")) { sheet = .password }
                        // Only while subscribed: without it, the tier card above is the way in.
                        if app.isPremium, let sub = app.subscription {
                            separator
                            row("drafft tempo", icon: MeView.sparkIcon,
                                value: sub.willRenew
                                    ? L("Renews \(sub.periodEnds.formatted(.dateTime.day().month(.abbreviated).locale(.app)))")
                                    : L("Ends \(sub.periodEnds.formatted(.dateTime.day().month(.abbreviated).locale(.app)))")) { sheet = .subscription }
                        }
                    }
                    group(L("Privacy & data")) {
                        row(L("Blocked people"), icon: "user-block",
                            value: app.blockedCount == 0 ? L("No one") : "\(app.blockedCount)") { sheet = .blocked }
                        separator
                        row(L("Export my data"), icon: "download-minimalistic",
                            value: app.dataExportRequestedAt == nil ? L("Sent to you by email") : L("Requested, check your inbox")) { sheet = .export }
                        separator
                        // drafft can't work without the gender: withdrawing the consent is deleting the account.
                        row(L("Sensitive data consent"), icon: "lock-keyhole-minimalistic",
                            value: L("Withdrawing it means deleting your account.")) { sheet = .consent }
                    }
                    group(L("Help")) {
                        row(L("Safety tips"), icon: "shield-check", value: L("Meeting someone for the first time")) { sheet = .safety }
                        separator
                        row(L("Help center"), icon: "question-circle", value: nil) { sheet = .help }
                        separator
                        row(L("Legal information"), icon: "document-text", value: nil) { sheet = .legal }
                    }
                    VStack(spacing: 0) {
                        Button { confirmLogout = true } label: {
                            Text("Log out")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(DS.Palette.ink)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .contentShape(.rect)
                        }
                        separator
                        Button { sheet = .delete } label: {
                            Text("Delete account")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(DS.Palette.negative)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .contentShape(.rect)
                        }
                    }
                    .padding(.horizontal, DS.Space.lg)
                    .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
                    // Under the last block, the page's one quiet footnote (a user-requested exception
                    // to "no loose text"): which app this is, down to the build.
                    Text(branded: Self.buildLabel, font: .caption)
                        .foregroundStyle(DS.Palette.mute)
                        .padding(.top, DS.Space.xs)
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.xxl)
                // The strip comes and goes with the pause (the switch or the server): the blocks
                // under it slide along, without a bounce (a spring overshooting read as a jolt).
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35), value: app.profilePaused)
            }
            .contentMargins(.top, DS.Space.xs, for: .scrollContent)
            .trackingScrollOffset($scrollOffset)
            .background(DS.Palette.canvasSoft)
            .toolbarVisibility(.hidden, for: .navigationBar)
            // No title on You: just the blur under the status bar.
            .topBar { Color.clear.frame(height: DS.Space.xs) }
            .drafftConfirm(isPresented: $confirmLogout, icon: "logout-2",
                           title: L("Log out?"),
                           message: L("Your matches and chats stay safe. Log back in to see them."),
                           actions: [ConfirmAction(title: L("Log out"), kind: .destructive) { app.signOut() }])
            .sheet(item: $sheet) { s in
                Group {
                    switch s {
                    case .edit: EditProfileView(profile: app.me).trackScreen(.editProfile)
                    case .preview:
                        NavigationStack {
                            ProfileDetailView(profile: app.publicMe, mode: .me)
                                .toolbar {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        Button("Close", image: .icon("close")) { sheet = nil }
                                    }
                                }
                        }
                    case .filters: FiltersSheet(filters: app.filters)
                    case .email: ChangeEmailSheet()
                    case .phone: ChangePhoneSheet()
                    case .notifications: NotificationsSettingsView()
                    case .language: LanguageSheet()
                    case .password: ChangePasswordSheet()
                    case .export: ExportDataSheet()
                    case .delete: DeleteAccountSheet()
                    case .paywall:
                        PaywallView(headline: L("Train at your tempo."),
                                    pitch: L("See who already likes you, send unlimited likes and get a free boost every week."))
                    case .subscription: SubscriptionSheet()
                    case .blocked: BlockedPeopleSheet()
                    case .safety: SafetyTipsSheet()
                    case .help: SupportSheet()
                    case .legal: LegalDocsListSheet()
                    case .consent: DeleteAccountSheet(withdrawsConsent: true)
                    }
                }
                .sheetSurface()
            }
        }
    }

    /// "drafft 1.0 (12)", with the environment in the name off production ("drafft β").
    private static let buildLabel: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let name = info["CFBundleDisplayName"] as? String ?? "drafft"
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        return "\(name) \(version) (\(build))"
    }()

    // MARK: Profile card

    @ViewBuilder
    private var profileCard: some View {
        if app.profileLoad == .loaded { loadedProfileCard } else { profileLoadCard }
    }

    /// Until the server's profile is in: loading, or why it isn't and a way to try again. Never a
    /// profile that isn't theirs, and nothing to edit or preview yet.
    private var profileLoadCard: some View {
        let failed = app.profileLoad == .failed
        return VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.lg) {
                Circle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 84, height: 84)
                    .overlay {
                        if failed {
                            Image("user-rounded").font(.system(size: 32, weight: .bold)).foregroundStyle(.white)
                        } else {
                            ProgressView().tint(.white)
                        }
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(failed ? L("Your profile couldn't load") : L("Loading your profile"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if failed {
                        Text(app.profileLoadFailure ?? L("Check your connection and try again."))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            if failed {
                Button { Task { await app.loadProfile() } } label: {
                    Label("Try again", image: "refresh")
                }
                .buttonStyle(.drafftPrimary)
            }
        }
        .padding(DS.Space.xl)
        .nightBlock()
        .animation(Motion.snappy, value: app.profileLoad)
    }

    private var loadedProfileCard: some View {
        let completion = app.profileCompletion
        return VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.lg) {
                Button { sheet = .preview } label: {
                    Photo(name: app.publicMe.portrait, side: 84)
                        .frame(width: 84, height: 84)
                        .clipShape(.circle)
                        .overlay(Circle().strokeBorder(DS.Palette.accentOnNight, lineWidth: 3))
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Preview my profile")
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    // Same line as your profile page: display name, the age set apart without a comma.
                    NameAgeLine(profile: app.me, nameSize: 32, nameColor: .white, ageColor: .white.opacity(0.8))
                        .accessibilityAddTraits(.isHeader)
                    // Named chips on one line: what fits, then "+X".
                    SportChipsLine(sports: app.me.sports.map(\.sport))
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }

            if completion.value < 1 {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    // The next step shares the line while it fits in full, under it otherwise.
                    AdaptiveRow {
                        Text("Profile \(Int(completion.value * 100))% complete")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    } trailing: {
                        if let next = completion.next {
                            Text(next).font(.footnote).foregroundStyle(DS.Palette.accentOnNight)
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.14))
                            Capsule().fill(DS.Palette.accentOnNight).frame(width: geo.size.width * completion.value)
                        }
                    }
                    .frame(height: 6)
                    .accessibilityElement()
                    .accessibilityLabel("Profile \(Int(completion.value * 100)) percent complete")
                }
            }

            HStack(spacing: DS.Space.sm) {
                Button { sheet = .edit } label: {
                    Label("Edit profile", image: "pen")
                }
                .buttonStyle(.drafftPrimary)
                Button { sheet = .preview } label: {
                    Image("eye")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.14), in: .circle)
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Preview my profile")
            }
        }
        .padding(DS.Space.xl)
        .nightBlock()
    }

    private var plusCard: some View {
        Button { sheet = .paywall } label: {
            HStack(spacing: DS.Space.md) {
                // The sign as a round sticker (the empty tabs' sticker, still): a night disc with the
                // filled spark, a white edge, its top-right corner slightly lifted.
                StillSticker(tempoSize: 50)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(branded: L("Get drafft tempo"), font: .headline, brandWeight: .heavy, tierColor: DS.Palette.tierOnAccent)
                        .foregroundStyle(DS.Palette.onLime)
                    // White on the accent only in semibold or bolder, at full strength.
                    Text("Undo your last swipe, see who likes you, unlimited likes.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DS.Palette.onLime)
                }
                Spacer(minLength: 0)
                Image("alt-arrow-right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(DS.Palette.onLime)
            }
            .padding(DS.Space.lg)
            .background(DS.Palette.lime, in: .rect(cornerRadius: DS.Radius.xl))
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
    }

    private var filtersSummary: String {
        let f = app.filters
        let ages = "\(f.ages.lowerBound)–\(f.ages.upperBound)"
        return "\(f.distanceLabel), \(ages), \(f.audience.title)"
    }

    // MARK: Rows

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote.weight(.bold))
                .foregroundStyle(DS.Palette.mute)
                .padding(.top, DS.Space.lg)
                .padding(.bottom, DS.Space.xs)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.bottom, DS.Space.xs)
        .background(DS.Palette.canvas, in: .rect(cornerRadius: DS.Radius.xl))
    }

    private var separator: some View {
        Rectangle().fill(DS.Palette.hairline).frame(height: 1).padding(.leading, 52)
    }

    /// Marker for rows that use the drafft tempo spark instead of an SF Symbol.
    static let sparkIcon = "drafft.spark"

    @ViewBuilder
    private func icon(_ name: String) -> some View {
        Group {
            if name == Self.sparkIcon {
                SparkPlus().fill(DS.Palette.ink).frame(width: 18, height: 13)
            } else {
                Image(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Palette.ink)
            }
        }
        .frame(width: 36, height: 36)
        .background(DS.Palette.canvasSoft, in: .circle)
    }

    private func row(_ title: String, icon name: String, value: String?, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: DS.Space.md) {
                icon(name)
                VStack(alignment: .leading, spacing: 1) {
                    Text(branded: title, font: .body.weight(.semibold), brandWeight: .heavy).foregroundStyle(DS.Palette.ink)
                    if let value {
                        Text(value).font(.footnote).foregroundStyle(DS.Palette.body).lineLimit(2)
                    }
                }
                Spacer(minLength: DS.Space.sm)
                Image("alt-arrow-right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(DS.Palette.mute)
            }
            .padding(.vertical, DS.Space.md)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Same layout as `row`, but nothing to open: not a button, no chevron.
    private func infoRow(_ title: String, icon name: String, value: String) -> some View {
        HStack(spacing: DS.Space.md) {
            icon(name)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(DS.Palette.ink)
                Text(value).font(.footnote).foregroundStyle(DS.Palette.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.md)
        .accessibilityElement(children: .combine)
    }

    private func toggleRow(_ title: String, icon name: String, detail: String? = nil,
                           tint: Color = DS.Palette.lime, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: DS.Space.md) {
                icon(name)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(DS.Palette.ink)
                    if let detail {
                        Text(detail).font(.footnote).foregroundStyle(DS.Palette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .tint(tint)
        .padding(.vertical, DS.Space.md)
        .onChange(of: isOn.wrappedValue) { Haptics.select() }
    }
}

/// While the profile is paused, the strip under the You card: the same colour as the switch that
/// paused it, and what it means in one line. The switch in Discovery is the way back.
private struct PausedStrip: View {
    var body: some View {
        // On the title's baseline: the icon stays by the title when a translation wraps.
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
            Image("pause")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DS.Palette.onPaused)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Profile paused")
                    .font(.subheadline.weight(.bold))
                Text("No one sees you in Discover.")
                    .font(.footnote)
            }
            .foregroundStyle(DS.Palette.onPaused)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Radius.xl + DS.Space.md)
        .padding(.bottom, DS.Space.md)
        // Square at the top: it continues the card rather than sitting behind it.
        .background(DS.Palette.paused, in: .rect(bottomLeadingRadius: DS.Radius.xl, bottomTrailingRadius: DS.Radius.xl))
        .accessibilityElement(children: .combine)
    }
}
