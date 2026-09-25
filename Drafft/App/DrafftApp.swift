import SwiftUI
import RevenueCat

@main
struct DrafftApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app = AppModel()

    init() {
        Probe.start()
        Probe.mark("app init")
        Store.configure()
        Self.styleNavigationBars()
        Self.prewarmPhotos()
        let args = ProcessInfo.processInfo.arguments
        // Demo launch shortcuts for screenshots: -skipAuth, -tab chats, -chat maya
        if args.contains("-skipAuth") { _app = State(initialValue: Self.demoModel(args)) }
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

    /// Large titles in the display face, inline titles in its extra-bold cut, both in ink.
    /// Only text attributes are set, so the system bar keeps its glass and scroll-edge blur.
    private static func styleNavigationBars() {
        let ink = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xF1F3EF) : UIColor(hex: 0x0E0F0C) }
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
        let onInk = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x0E0F0C) : .white }
        let tabItem = UITabBarItem.appearance()
        tabItem.badgeColor = ink
        tabItem.setBadgeTextAttributes([.foregroundColor: onInk], for: .normal)
    }

    @MainActor
    private static func demoModel(_ args: [String]) -> AppModel {
        let m = AppModel()
        m.phase = args.contains("-onboarding") ? .onboarding : .main
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count {
            m.tab = switch args[i + 1] {
            case "chats": .chats
            case "sessions": .sessions
            case "me": .me
            case "likes": .likes
            default: .discover
            }
        }
        if let i = args.firstIndex(of: "-chat"), i + 1 < args.count {
            m.tab = .chats
            m.chatRequest = args[i + 1]
        }
        if args.contains("-tight") {
            // Demo: filters that hide everyone, to show the too-tight state.
            m.filters.maxDistanceKm = 2
            m.filters.sports = [.triathlon, .padel]
            m.filters.sharedSportsOnly = true
        }
        if let i = args.firstIndex(of: "-match"), i + 1 < args.count {
            m.matchScreen = MockData.profile(args[i + 1])
        }
        return m
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    /// The tabs exist from shortly after launch, invisible under the welcome screen or sign-up.
    @State private var tabsMounted = false
    private var inMain: Bool { app.phase == .main }

    var body: some View {
        rootStack
            // Banners that must sit above everything (sheets included) live in their own window.
            .onAppear { TopOverlayWindow.shared.install() }
            .task {
                // Probe: sign in by itself after a few seconds, like a person on the welcome screen.
                guard Probe.on, ProcessInfo.processInfo.arguments.contains("-autoLogin") else { return }
                try? await Task.sleep(for: .seconds(4))
                Probe.mark("auto login")
                app.signIn(onboard: false)
            }
    }

    private var rootStack: some View {
        ZStack {
            // The real tabs are built early, invisibly, under the welcome screen (or sign-up),
            // and walked through once there (MainTabs). Building a tab the first time froze the
            // tab bar for 50 to 125 ms per tab on device; signing in now reveals screens that
            // already exist.
            if tabsMounted || inMain {
                MainTabs(isActive: inMain)
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
        .task { await app.restoreSession() }
        // Links in auth emails (confirm sign-up, reset password).
        .onOpenURL { url in Task { await app.handleAuthLink(url) } }
        .sheet(isPresented: Binding(get: { app.choosingNewPassword }, set: { app.choosingNewPassword = $0 })) {
            NavigationStack { NewPasswordView() }
                .sheetSurface()
        }
    }
}

struct MainTabs: View {
    /// False while the tabs wait, invisible, under the welcome screen or sign-up: nothing here
    /// may ask for a permission, present a screen or show a banner then.
    let isActive: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var location = LocationGate()

    /// Outline when the tab is idle, filled when it's the current one (the system would fill them all).
    private func tabLabel(_ title: String, _ symbol: String, _ tab: AppModel.Tab) -> some View {
        Label(title, systemImage: symbol)
            .environment(\.symbolVariants, app.tab == tab ? .fill : .none)
    }

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            Tab(value: AppModel.Tab.discover) {
                DiscoverView().tint(DS.Palette.accentInk)
            } label: {
                tabLabel(L("Discover"), "flame", .discover)
            }
            Tab(value: AppModel.Tab.likes) {
                LikesTabView().tint(DS.Palette.accentInk)
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
        .onChange(of: app.tab) { _, t in Probe.mark("tab -> \(t)") }
        .task {
            // Built in the background: open each tab once, so each one's screen exists before
            // the first tap. Stops as soon as the person is in (and they land on Discover).
            guard !isActive else { return }
            for t in [AppModel.Tab.likes, .sessions, .chats, .me, .discover] {
                try? await Task.sleep(for: .milliseconds(300))
                guard app.phase != .main else { return }
                Probe.mark("prebuild tab \(t)")
                app.tab = t
            }
        }
        .task(id: isActive) {
            // Probe: switch through every tab, as taps would.
            guard isActive, Probe.on, ProcessInfo.processInfo.arguments.contains("-cycleTabs") else { return }
            Probe.mark("main tabs appeared")
            for t in [AppModel.Tab.chats, .me, .sessions, .likes, .discover, .chats, .me] {
                try? await Task.sleep(for: .seconds(1.5))
                Probe.mark("set tab \(t)")
                app.tab = t
            }
        }
        // drafft tempo follows the App Store: purchases, renewals, cancellations and refunds,
        // on this device or another, arrive through RevenueCat's stream.
        .task {
            await Store.shared.load()
            for await info in Purchases.shared.customerInfoStream {
                app.subscription = Store.shared.subscription(from: info)
            }
        }
        // Notifications: keep the status fresh, schedule session reminders, open tapped chats.
        .task(id: isActive) {
            guard isActive else { return }
            await NotificationService.shared.loadSettings()
            await NotificationService.shared.refresh()
            // Demo: -askNotifications shows the system prompt right away (to test pushes).
            if ProcessInfo.processInfo.arguments.contains("-askNotifications") {
                await NotificationService.shared.requestPermission()
            }
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
        // drafft tempo's weekly boost: credited when due (at the front, or right then if open),
        // announced by a notification the rest of the time.
        .task(id: "\(isActive)\(app.nextWeeklyBoostAt?.timeIntervalSince1970 ?? 0)\(NotificationService.shared.isAllowed)") {
            guard isActive else { return }
            app.creditWeeklyBoosts()
            NotificationService.shared.scheduleWeeklyBoost(at: app.nextWeeklyBoostAt)
            guard let next = app.nextWeeklyBoostAt else { return }
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)))
            app.creditWeeklyBoosts()
        }
        .onChange(of: scenePhase) { _, p in if p == .active && isActive { app.creditWeeklyBoosts() } }
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
