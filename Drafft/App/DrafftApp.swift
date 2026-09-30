import SwiftUI
import RevenueCat

@main
struct DrafftApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app = AppModel()

    init() {
        Diagnostics.shared.start()
        Images.configure()
        Store.configure()
        Self.styleNavigationBars()
        Self.prewarmPhotos()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                // The app's own language, not the phone's (Text, dates, numbers).
                .environment(\.locale, app.language.locale)
                .tint(DS.Palette.accentInk)
                // No scroll bars on any page or sheet (see `noScrollIndicators`).
                .noScrollIndicators()
                // Never the default white behind transitions.
                .background(DS.Palette.night.ignoresSafeArea())
        }
    }

    /// Decodes, in the background, the bundled photos the first screens draw: the welcome photos.
    /// Photos from the server go through Nuke (`Images`).
    private static func prewarmPhotos() {
        ImageStore.prewarm(full: WelcomeView.photos, small: [], blurred: [])
    }

    /// Large titles in the display face, inline titles in its extra-bold cut, both in ink. No halo:
    /// a UIKit shadow can't tell a sheet from a page, and showed as a coloured rim on white sheets.
    /// Only text attributes are set, so the system bar keeps its glass and scroll-edge blur.
    private static func styleNavigationBars() {
        let ink = UIColor(DS.Palette.ink)
        let bar = UINavigationBar.appearance()
        if let large = UIFont(name: DisplayFont.black, size: 34) {
            bar.largeTitleTextAttributes = [
                .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large),
                .foregroundColor: ink,
                .kern: -0.5
            ]
        }
        if let inline = UIFont(name: DisplayFont.extraBold, size: 17) {
            bar.titleTextAttributes = [
                .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline),
                .foregroundColor: ink
            ]
        }
        // Tab badges in ink, not the system red: the tab bar stays monochrome.
        let onInk = UIColor(DS.Palette.onInk)
        let tabItem = UITabBarItem.appearance()
        tabItem.badgeColor = ink
        tabItem.setBadgeTextAttributes([.foregroundColor: onInk], for: .normal)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var moderation = AccountModeration.shared
    /// The tabs exist from shortly after launch, invisible under the welcome screen or sign-up.
    @State private var tabsMounted = false
    /// The saved session has been checked (signed in straight away, or the welcome screen).
    @State private var sessionChecked = false
    @State private var splashShown = true
    /// Set when the app went to the background; the next `.active` reads what changed while away.
    @State private var returningFromBackground = false
    /// Each tab has been opened once (MainTabs). A signed-in launch lands on the tabs: the splash
    /// stays until they're built, so the first tap on a tab never builds it.
    @State private var tabsBuilt = false
    private var inMain: Bool { app.phase == .main }

    var body: some View {
        rootStack
            // Under the splash, the welcome photos wait for it: it hands over on the photo it shows.
            .environment(\.heroSlideshowLeads, !splashShown)
            // The launch: it covers the first screen until it's ready, then fades onto it.
            .overlay {
                if splashShown {
                    SplashView(isReady: sessionChecked && (inMain ? tabsBuilt : tabsMounted)) { splashShown = false }
                }
            }
            // The server turned an action down because the profile is paused: lock discovery.
            .onReceive(NotificationCenter.default.publisher(for: .profilePausedByServer)) { _ in
                app.serverRefusedPaused()
                // A hold pauses the profile too (and bans it from chats): check which it is.
                Task { await moderation.load() }
            }
            // A moderation hold: the hold screen covers everything, at once, and lifts the same way.
            .onReceive(NotificationCenter.default.publisher(for: .accountHeldByServer)) { _ in
                Task { await moderation.load() }
            }
            .onChange(of: moderation.hold) { _, hold in
                HoldWindow.shared.update(visible: hold != nil)
                // The hold paused the profile; lifting it gave the person's own pause back.
                if hold == nil, app.phase != .welcome { Task { await app.refreshAccount(force: true) } }
            }
            .onChange(of: app.phase) { _, phase in if phase == .welcome { moderation.clear() } }
            .task(id: "\(app.phase == .welcome)\(app.sessionID)") {
                guard app.phase != .welcome else { return }
                // Signed in or launched: the iPhone's DeviceCheck token, for ban evasion (server side),
                // and this opening, for the team's safety checks.
                Task { await DeviceIntegrity.report() }
                Task { await AppOpens.report() }
                // A purchase confirmed earlier but not credited yet: asked for again.
                Task { await PurchaseCredit.shared.resume(app) }
                // Chat: one connection for the account (a second call only reads matches again).
                Task { await ChatService.shared.start(app) }
                await UserChannel.watch(app)
            }
            .onChange(of: scenePhase) { _, p in
                // A real return to the app only: Control Center, a system alert or the app
                // switcher only make it inactive for a moment, and read nothing.
                if p == .background { returningFromBackground = true }
                guard p == .active, returningFromBackground else { return }
                returningFromBackground = false
                guard app.phase != .welcome else { return }
                // The account row (hold, pause, settings, language, card), changed while away.
                Task { await moderation.load() }
                // Photo verdicts given while away (a missed live event): read again, never assumed.
                PhotoModeration.shared.recheck()
                Task { await AppOpens.report() }
                // Credited while away (a purchase on another device, the weekly boost).
                Task { await app.loadWallet() }
                Task { await PurchaseCredit.shared.resume(app) }
                // A session changed or was cancelled while away: read again, its calendar event follows.
                Task { await SessionStore.shared.refresh() }
                // The deck, likes and matches as the server has them now (no card outlives it).
                app.refreshDiscovery()
            }
            // A session that ends on its own (revoked, expired, account deleted elsewhere): back to
            // the welcome screen, which says why.
            .task { await app.watchSession() }
            .drafftConfirm(isPresented: Binding(get: { app.sessionEndedNotice }, set: { app.sessionEndedNotice = $0 }),
                           icon: "user-warning",
                           title: L("You've been logged out"),
                           message: L("Your session ended on this iPhone. Log in again to pick up where you left off."),
                           cancelTitle: L("Got it"), actions: [])
            // Banners that must sit above everything (sheets included) live in their own window.
            .onAppear {
                // The hold is read with the rest of the account's row: one read, one source.
                moderation.refresh = { [app] in await app.refreshAccount(force: true) }
                TopOverlayWindow.shared.install()
                HoldWindow.shared.install(app)
            }
    }

    private var rootStack: some View {
        ZStack {
            // The real tabs are built early, invisibly, under the welcome screen (or sign-up),
            // and walked through once there (MainTabs). Building a tab the first time froze the
            // tab bar for 50 to 125 ms per tab on device; signing in now reveals screens that
            // already exist.
            if tabsMounted || inMain {
                // Under a moderation hold the tabs stay inactive: no permission prompt, cover or
                // banner over the hold screen. They wake up where they were once it's lifted.
                MainTabs(isActive: inMain && moderation.hold == nil,
                         // Hidden under the splash, the welcome screen or sign-up: tabs may be switched.
                         mayPrebuild: Binding(get: { splashShown || !inMain }, set: { _ in })) {
                    tabsBuilt = true
                }
                    .id(app.sessionID)
                    // Hidden, they don't follow the keyboard of the forms on top.
                    .ignoresSafeArea(inMain ? SafeAreaRegions() : .keyboard)
                    .opacity(inMain ? 1 : 0)
                    .allowsHitTesting(inMain)
                    .accessibilityHidden(!inMain)
                    .zIndex(inMain ? 2 : 0)
            }
            // A screen on its way out never takes touches (it stays in the tree for its
            // fade), and the new one is drawn on top from the first frame.
            switch app.phase {
            case .welcome:
                WelcomeView().transition(.opacity)
                    .allowsHitTesting(app.phase == .welcome)
                    .zIndex(1)
            case .onboarding:
                OnboardingView().transition(.move(edge: .trailing))
                    .allowsHitTesting(app.phase == .onboarding)
                    .zIndex(1)
            case .main:
                EmptyView()
            }
        }
        .animation(Motion.gentle, value: app.phase)
        .task {
            // Once the welcome screen has drawn and settled.
            try? await Task.sleep(for: .milliseconds(800))
            tabsMounted = true
        }
        // Signed in on this device before: straight in.
        .task {
            await app.restoreSession()
            sessionChecked = true
        }
    }
}

struct MainTabs: View {
    /// False while the tabs wait, invisible, under the welcome screen or sign-up: nothing here
    /// may ask for a permission, present a screen or show a banner then.
    let isActive: Bool
    /// Read live at each step of the walk: whether nobody can see the tabs switch.
    @Binding var mayPrebuild: Bool
    /// Called once the walk is over (done, or stopped because the tabs showed).
    var onBuilt: () -> Void = {}
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var location = LocationGate.shared

    /// Line icon when the tab is idle, its Solar bold twin ("<name>-bold") when it's the current one.
    private func tabLabel(_ title: String, _ symbol: String, _ tab: AppModel.Tab) -> some View {
        Label(title, image: app.tab == tab ? "\(symbol)-bold" : symbol)
    }

    /// Opens each tab once while nobody sees it (under the splash on a signed-in launch, under the
    /// welcome screen otherwise), so each one's screen exists before the first tap, then comes back
    /// to the tab it started on. Stops as soon as the tabs show, or if something else picked another
    /// tab (a tapped notification): that choice stays. Signing in puts Discover back mid-walk
    /// (the restored session lands during the splash): the walk goes on.
    private func prebuildTabs() async {
        let start = app.tab
        var shown = start
        defer {
            // Back where it started, unless something else picked a tab meanwhile.
            if app.tab == shown || app.tab == start { app.tab = start }
            onBuilt()
        }
        let tabs: [AppModel.Tab] = [.discover, .likes, .sessions, .chats, .me]
        for t in tabs where t != start {
            try? await Task.sleep(for: .milliseconds(250))
            guard mayPrebuild, app.tab == shown || app.tab == start else { return }
            app.tab = t
            shown = t
        }
        // The last one gets its turn to build too.
        try? await Task.sleep(for: .milliseconds(250))
    }

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            Tab(value: AppModel.Tab.discover) {
                DiscoverView().tint(DS.Palette.accentInk).pausedLock()
            } label: {
                tabLabel(L("Discover"), "fire", .discover)
            }
            Tab(value: AppModel.Tab.likes) {
                LikesTabView().tint(DS.Palette.accentInk).pausedLock(PauseScope.locksLikes)
            } label: {
                tabLabel(L("Likes"), "heart", .likes)
            }
            .badge(app.likedMeCount)
            Tab(value: AppModel.Tab.sessions) {
                SessionsView().tint(DS.Palette.accentInk)
            } label: {
                tabLabel(L("Sessions"), "stopwatch-play", .sessions)
            }
            Tab(value: AppModel.Tab.chats) {
                ConversationsView().tint(DS.Palette.accentInk)
            } label: {
                tabLabel(L("Chats"), "dialog-2", .chats)
            }
            .badge(app.unreadTotal)
            Tab(value: AppModel.Tab.me) {
                MeView().tint(DS.Palette.accentInk)
            } label: {
                tabLabel(L("You"), "user-circle", .me)
            }
        }
        // The tab bar stays monochrome (selected tab in ink): the home already carries the accent,
        // the like green and the red. Each tab's content gets the accent tint back.
        .tint(DS.Palette.ink)
        .tabBarMinimizeBehavior(.onScrollDown)
        .task { await prebuildTabs() }
        // drafft tempo's details (plan, renewal) follow the App Store through RevenueCat's stream, for
        // the signed-in account only. Whether it's on, and every balance, comes from the wallet.
        .task {
            await Store.shared.load()
            for await info in Purchases.shared.customerInfoStream where Store.shared.reportsLinkedAccount {
                app.subscription = Store.shared.subscription(from: info)
            }
        }
        // Notifications: keep the status fresh, open tapped chats. Session reminders are the server's
        // pushes (`session.reminder`), so a cancelled session never leaves one behind.
        .task(id: isActive) {
            guard isActive else { return }
            // In (sign-in, end of sign-up, a hold lifted): discovery as the server has it.
            app.refreshDiscovery()
            await NotificationService.shared.refresh()
        }
        .onChange(of: NotificationService.shared.openChatID) { _, id in
            if let id { app.openChat(id); NotificationService.shared.openChatID = nil }
        }
        .onChange(of: NotificationService.shared.openBoost) { _, open in
            if open { app.tab = .discover; NotificationService.shared.openBoost = false }
        }
        .onChange(of: NotificationService.shared.openSessions) { _, open in
            if open { app.tab = .sessions; NotificationService.shared.openSessions = false }
        }
        // Location is required: while it's off (or never answered), a screen in its own window blocks
        // everything, sheets included, until it's back on. Read again at each return to the app.
        .onAppear { if isActive { location.refresh() } }
        .onChange(of: isActive) { _, active in if active { location.refresh() } }
        .onChange(of: scenePhase) { _, p in if p == .active && isActive { location.refresh() } }
        .onChange(of: isActive && !location.isAllowed, initial: true) { _, blocked in
            LocationWindow.shared.update(visible: blocked, language: app.language.locale)
        }
        .onDisappear { LocationWindow.shared.update(visible: false, language: app.language.locale) }
        // A fresh read found no record of the current terms and the consent to sensitive data: asked
        // at each open until accepted, after the location gate. Unknown (no read yet, offline) asks
        // nothing: the read is retried until it says (refreshAccount), and a sign-up can't finish
        // without the consent on the server (complete_onboarding).
        .fullScreenCover(isPresented: .constant(isActive && location.isAllowed && app.termsConsent == .required)) {
            TermsConsentView()
        }
        .overlay(alignment: .top) {
            if !isActive {
                EmptyView()
            } else if let banner = app.banner {
                MatchBannerView(banner: banner) {
                    app.openChat(person: banner.profile.id)
                } onDismiss: {
                    withAnimation(Motion.snappy) { app.banner = nil }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, DS.Space.xs)
            } else if let notice = app.notice {
                NoticeBannerView(notice: notice) {
                    withAnimation(Motion.snappy) { app.notice = nil }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, DS.Space.xs)
            } else if let id = app.boostBanner {
                BoostBannerView(id: id) {
                    withAnimation(Motion.snappy) { app.boostBanner = nil }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, DS.Space.xs)
            }
        }
        .animation(Motion.bouncy, value: app.banner)
        .animation(Motion.bouncy, value: app.boostBanner)
        .animation(Motion.bouncy, value: app.notice)
        .fullScreenCover(item: $app.matchScreen) { p in
            MatchView(profile: p, me: app.publicMe) {
                app.openChat(person: p.id)
            } onClose: {
                app.matchScreen = nil
            }
        }
    }
}
