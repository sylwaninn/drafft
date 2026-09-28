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
                // Never the default white behind transitions.
                .background(DS.Palette.night.ignoresSafeArea())
        }
    }

    /// Decodes, in the background, the photos the first screens draw: the welcome photos, the
    /// top of the deck, and every avatar and locked-like copy the tabs show. The first visit
    /// of a tab then draws without decoding, and the tab bar answers straight away.
    private static func prewarmPhotos() {
        let people = MockData.profiles.map(\.portrait) + [MockData.me.portrait]
        let deck = MockData.deck.prefix(3).flatMap { [$0.portrait] + $0.photos.prefix(1) }
        ImageStore.prewarm(
            full: WelcomeView.photos + deck,
            small: people.flatMap { [(name: $0, side: 32), (name: $0, side: 56), (name: $0, side: 88)] },
            blurred: MockData.deck.map(\.portrait).flatMap { [(name: $0, fraction: 0.1), (name: $0, fraction: 4.0 / 24)] })
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
            // The launch: it covers the first screen until it's ready, then fades onto it.
            .overlay {
                if splashShown {
                    SplashView(isReady: sessionChecked && (inMain ? tabsBuilt : tabsMounted)) { splashShown = false }
                }
            }
            // The server turned an action down because the profile is paused: lock discovery.
            .onReceive(NotificationCenter.default.publisher(for: .profilePausedByServer)) { _ in
                app.applyServerPause(true)
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
                Task { await AppOpens.report() }
                // Credited while away (a purchase on another device, the weekly boost).
                Task { await app.loadWallet() }
                Task { await PurchaseCredit.shared.resume(app) }
                // A session changed or was cancelled while away: its calendar event follows.
                Task { await SessionCalendar.shared.refresh() }
            }
            // A session that ends on its own (revoked, expired, account deleted elsewhere): back to
            // the welcome screen, which says why.
            .task { await app.watchSession() }
            .drafftConfirm(isPresented: Binding(get: { app.sessionEndedNotice }, set: { app.sessionEndedNotice = $0 }),
                           icon: "person.crop.circle.badge.exclamationmark",
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
    @State private var location = LocationGate()

    /// Outline when the tab is idle, filled when it's the current one (the system would fill them all).
    private func tabLabel(_ title: String, _ symbol: String, _ tab: AppModel.Tab) -> some View {
        Label(title, systemImage: symbol)
            .environment(\.symbolVariants, app.tab == tab ? .fill : .none)
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
                tabLabel(L("Discover"), "flame", .discover)
            }
            Tab(value: AppModel.Tab.likes) {
                LikesTabView().tint(DS.Palette.accentInk).pausedLock(PauseScope.locksLikes)
            } label: {
                tabLabel(L("Likes"), "heart", .likes)
            }
            .badge(app.likedMe.count)
            Tab(value: AppModel.Tab.sessions) {
                SessionsView().tint(DS.Palette.accentInk)
            } label: {
                tabLabel(L("Sessions"), "flag.2.crossed", .sessions)
            }
            Tab(value: AppModel.Tab.chats) {
                ConversationsView().tint(DS.Palette.accentInk)
            } label: {
                tabLabel(L("Chats"), "bubble.left.and.bubble.right", .chats)
            }
            .badge(app.unreadTotal)
            Tab(value: AppModel.Tab.me) {
                MeView().tint(DS.Palette.accentInk)
            } label: {
                tabLabel(L("You"), "person.crop.circle", .me)
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
        // Notifications: keep the status fresh, schedule session reminders, open tapped chats.
        .task(id: isActive) {
            guard isActive else { return }
            await NotificationService.shared.refresh()
        }
        .task(id: "\(isActive)" + app.upcomingSessions.map { "\($0.1.id)\($0.1.status)" }.joined()) {
            guard isActive else { return }
            NotificationService.shared.scheduleSessionReminders(
                app.upcomingSessions.filter { $0.1.status == .accepted }
                    .map { (id: $0.1.id, title: L("\($0.1.displayTitle) with \($0.0.profile.name)"), date: $0.1.date, chatID: $0.0.id) })
        }
        .onChange(of: NotificationService.shared.openChatID) { _, id in
            if let id { app.openChat(id); NotificationService.shared.openChatID = nil }
        }
        .onChange(of: NotificationService.shared.openBoost) { _, open in
            if open { app.tab = .discover; NotificationService.shared.openBoost = false }
        }
        // Location is required: if it's turned off, block until it's back on.
        .onAppear { if isActive { location.refresh() } }
        .onChange(of: isActive) { _, active in if active { location.refresh() } }
        .onChange(of: scenePhase) { _, p in if p == .active && isActive { location.refresh() } }
        .fullScreenCover(isPresented: .constant(isActive && location.isBlocked)) { LocationRequiredView() }
        .overlay(alignment: .top) {
            if !isActive {
                EmptyView()
            } else if let banner = app.banner {
                MatchBannerView(banner: banner) {
                    app.openChat(banner.profile.id)
                } onDismiss: {
                    withAnimation(Motion.snappy) { app.banner = nil }
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
        .fullScreenCover(item: $app.matchScreen) { p in
            MatchView(profile: p, me: app.me) {
                app.openChat(p.id)
            } onClose: {
                app.matchScreen = nil
            }
        }
    }
}
