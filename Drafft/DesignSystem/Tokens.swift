import SwiftUI
import UIKit

// MARK: - Color

extension Color {
    /// Builds a color that resolves differently in light and dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// DESIGN.md palette. Light values are the spec; dark values keep the same roles
/// (ink and canvas swap polarity, lime stays the only accent).
enum DS {
    enum Palette {
        /// The brand accent can switch between the original lime, plum, tangerine and violet (trials).
        /// The token names stay "lime" (the role: the one accent); only the values change.
        enum Accent { case lime, plum, tangerine, violet }
        static let accent: Accent = .tangerine

        private static func pick(_ lime: Color, plum: Color, tangerine: Color, violet: Color) -> Color {
            switch accent { case .lime: lime; case .plum: plum; case .tangerine: tangerine; case .violet: violet }
        }

        static let lime = pick(Color(hex: 0x9FE870), plum: Color(hex: 0xC47EF2),
                               tangerine: Color(hex: 0xFF6B1A), violet: Color(hex: 0x7D70FD))
        static let limeActive = pick(Color(hex: 0xCDFFAD), plum: Color(hex: 0xE3C4FA),
                               tangerine: Color(hex: 0xFFAC7D), violet: Color(hex: 0xB5ADFE))
        static let limeNeutral = pick(Color(hex: 0xC5EDAB), plum: Color(hex: 0xDDB8F7),
                               tangerine: Color(hex: 0xFF9A5F), violet: Color(hex: 0xA49BFE))
        static let limePale = pick(Color(light: 0xE2F6D5, dark: 0x1E2A14), plum: Color(light: 0xF3E8FB, dark: 0x2A1A36),
                                   tangerine: Color(light: 0xFFEBDC, dark: 0x33200F),
                                   violet: Color(light: 0xEEECFF, dark: 0x1E1B3A))
        /// Text and glyphs on the accent. Tangerine and violet: white, by choice (bold labels and icons only).
        static let onLime = pick(Color(hex: 0x0E0F0C), plum: Color(hex: 0x1E0A2B), tangerine: Color(hex: 0xFFFFFF), violet: Color(hex: 0xFFFFFF))
        /// The accent as text or a glyph on neutral surfaces: links, the selected tab, "Typing",
        /// the app tint. Light mode is the accent darkened just enough for 4.5:1 on white (#B84600,
        /// still read as orange, not brown); dark mode lifts it (#FF8A45, 8:1 on the page).
        /// Violet: #6356F5 in light (5:1 on white), #A59CFF in dark (8:1 on the page).
        static let accentInk = pick(Color(light: 0x163300, dark: 0xC5EDAB), plum: Color(light: 0x3E174F, dark: 0xDDB8F7),
                                    tangerine: Color(light: 0xB84600, dark: 0xFF8A45),
                                    violet: Color(light: 0x6356F5, dark: 0xA59CFF))
        /// Selected fill on a night surface (plan rows, time options, icebreaker picks): an accent
        /// wash, never a frame.
        static let selectedOnNight = lime.opacity(0.26)
        /// Glyph discs sitting on an accent fill (the Plus card, a picked sport tile).
        static let onLimeWash = onLime.opacity(0.22)

        /// Liking stays green whatever the brand accent: like buttons, the heart pop, "send like"
        /// and the like messages in chat.
        static let like = Color(hex: 0x9FE870)
        static let likeActive = Color(hex: 0xCDFFAD)
        static let onLike = Color(hex: 0x0E0F0C)

        static let ink = Color(light: 0x0E0F0C, dark: 0xF1F3EF)
        /// Text on an ink fill (tab badges).
        static let onInk = Color(light: 0xFFFFFF, dark: 0x0E0F0C)
        static let body = Color(light: 0x454745, dark: 0xB9BCB7)
        /// Secondary text: at least 4.5:1 on every surface, sage wells and raised sheets included.
        static let mute = Color(light: 0x626461, dark: 0x969994)

        /// Blocks (white cards on the sage page). In a sheet they become wells: see `Surface`.
        static let canvas = Surface.block
        /// The page (sage). In a sheet it's the lifted tone: see `Surface`.
        static let canvasSoft = Surface.page
        /// The fixed tones, for the rare place that needs a `Color` whatever the surface.
        static let white = Color(light: 0xFFFFFF, dark: 0x1A1C18)
        /// Every input (text field, code and date boxes, pickers dressed as fields): the lifted
        /// white on a page, in a sheet's sage well, anywhere. Never the colour of what's around it.
        static let field = white
        /// The page tone follows the accent, so the page never keeps the colour of a former one:
        /// violet gets a cool grey with a touch of violet (#EDECF2). Same lightness as the old sage, so
        /// white blocks still stand out; body 7.8:1, mute 5.1:1 and accent ink 4.6:1 on it.
        static let sage = pick(Color(light: 0xE8EBE6, dark: 0x0E0F0C), plum: Color(light: 0xF1E9F4, dark: 0x120D14),
                               tangerine: Color(light: 0xF6EDE6, dark: 0x14100C),
                               violet: Color(light: 0xEDECF2, dark: 0x0E0E11))
        static let hairline = pick(Color(light: 0xD6DAD3, dark: 0x2C2F29), plum: Color(light: 0xE0D5E5, dark: 0x2E2830),
                                   tangerine: Color(light: 0xE6DBD2, dark: 0x302A25),
                                   violet: Color(light: 0xD9D8E0, dark: 0x2A2A30))

        /// Always-dark surface used for the polarity-flipped moments. In dark mode it's lifted a
        /// step above the page (which is near-black there too), so night blocks stay distinct.
        static let night = Color(light: 0x0E0F0C, dark: 0x23261F)
        static let nightRaised = Color(light: 0x1D1F1A, dark: 0x2E3229)
        /// Hairline around coloured blocks: invisible in light mode, a faint edge in dark mode.
        static let blockEdge = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.09) : .clear })
        /// Veil over the cards waiting behind the top one on Discover: sage in light mode, a
        /// lifted grey in dark mode so they don't sink into the black page.
        static let deckVeil = pick(Color(light: 0xE8EBE6, dark: 0x1A1C18), plum: Color(light: 0xF1E9F4, dark: 0x1D1820),
                                   tangerine: Color(light: 0xF6EDE6, dark: 0x1F1A16),
                                   violet: Color(light: 0xEDECF2, dark: 0x1B1B20))
        /// Short modal sheets (confirmations, purchase confirmation, photo refused) sit a step
        /// above anything under them, other sheets included. Light mode: white; dark mode: a grey
        /// lifted above the page, night blocks and regular sheets (`Surface`).
        static let sheetRaised = Color(light: 0xFFFFFF, dark: 0x2A2D26)

        static let positive = Color(hex: 0x2EAD4B)
        static let positiveDeep = Color(light: 0x054D28, dark: 0x7FD493)
        static let warning = Color(hex: 0xFFD11A)
        static let negative = Color(hex: 0xD03238)
        static let accentOrange = Color(hex: 0xFFC091)
        static let accentCyan = Color(hex: 0x38C8FF)
    }

    // MARK: Spacing (4pt base)
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    // MARK: Radius
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }
}

// MARK: - Type

/// Display face: Inter Display Black stands in for the proprietary Wise Sans (DESIGN.md substitute).
/// Everything else stays on San Francisco text styles so Dynamic Type works.
enum DisplayFont {
    static let black = "InterDisplay-Black"
    static let extraBold = "InterDisplay-ExtraBold"
}

extension Font {
    /// Heavy 900 display, scaled with Dynamic Type relative to a text style.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom(DisplayFont.black, size: size, relativeTo: style)
    }

    static func displayBold(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(DisplayFont.extraBold, size: size, relativeTo: style)
    }
}

extension View {
    /// Tight leading for 900 display (DESIGN.md: line-height ≈ 0.85× size).
    func displayLeading(_ size: CGFloat) -> some View {
        self.lineSpacing(-size * 0.12)
            .tracking(-size * 0.01)
    }
}

// MARK: - Motion

enum Motion {
    /// Selection feedback (chips, tiles, discs): short and critically damped, done before the
    /// finger is off the glass. Never a spring for a colour change.
    static let select = Animation.easeOut(duration: 0.1)
    static let snappy = Animation.spring(response: 0.22, dampingFraction: 0.86)
    static let bouncy = Animation.spring(response: 0.3, dampingFraction: 0.72)
    static let gentle = Animation.easeOut(duration: 0.18)
    /// Progress that should be seen moving (sign-up stepper bars): longer than snappy, no overshoot.
    static let progress = Animation.spring(response: 0.5, dampingFraction: 0.9)
}

// MARK: - Haptics

/// Generators are kept and re-prepared after each use: a fresh generator fired at once wakes the
/// Taptic Engine late, and the tick lands after the visual change.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    static func tap() { light.impactOccurred(); light.prepare() }
    static func thump() { medium.impactOccurred(); medium.prepare() }
    static func success() { notification.notificationOccurred(.success); notification.prepare() }
    static func warning() { notification.notificationOccurred(.warning); notification.prepare() }
    static func select() { selection.selectionChanged(); selection.prepare() }
}

// MARK: - Brand name

/// The product is "drafft", always lowercase, in UI copy and in the app name. With no capital to
/// mark it, the word is set one weight above the sentence around it (semibold in regular text),
/// so it reads as a name, not a typo.
///
/// The paid tier is "drafft tempo": both words lowercase, same face and weight, "tempo" in the
/// accent so the tier reads as one name with its own colour. No capital, no "+".
enum Brand {
    static let name = "drafft"
    static let tier = "tempo"
    static let tierName = "drafft tempo"
}

extension Text {
    /// Copy that may mention the brand: each "drafft" / "drafft tempo" (any case) is set as the
    /// brand, the rest stays as written. `font` is the sentence's font; `brandWeight` is one step
    /// above the sentence's weight. `tierColor` colours "tempo": `accentInk` on light surfaces
    /// (default), `lime` on night, `night` on an accent fill.
    init(branded string: String, font: Font, brandWeight: Font.Weight = .semibold,
         tierColor: Color = DS.Palette.accentInk) {
        var out = Text(verbatim: "")
        var rest = Substring(string)
        while let r = rest.range(of: Brand.name, options: .caseInsensitive) {
            out = Text("\(out)\(Text(verbatim: String(rest[..<r.lowerBound])))")
            var word = Text(verbatim: Brand.name).fontWeight(brandWeight)
            var after = rest[r.upperBound...]
            if let t = after.range(of: " \(Brand.tier)", options: [.caseInsensitive, .anchored]) {
                let tier = Text(verbatim: Brand.tier)
                    .fontWeight(brandWeight)
                    .foregroundStyle(tierColor)
                word = Text("\(word) \(tier)")
                after = after[t.upperBound...]
            }
            out = Text("\(out)\(word)")
            rest = after
        }
        self = Text("\(out)\(Text(verbatim: String(rest)))").font(font)
    }
}

// MARK: - Surfaces

/// Page and block tones that know where they are. On a screen: sage page, white blocks. In a
/// sheet the pair flips: the sheet is the lifted white (in dark mode, the lifted grey) and its
/// blocks sink into sage wells, so a sheet never shares its colour with the page it covers.
/// Sheets opt in with `.sheetSurface()` (every `.sheet` in the app does).
struct Surface: ShapeStyle {
    enum Role { case page, block }
    let role: Role

    static let page = Surface(role: .page)
    static let block = Surface(role: .block)

    func resolve(in environment: EnvironmentValues) -> Color {
        (role == .page) != environment.isSheetSurface ? DS.Palette.sage : DS.Palette.white
    }
}

extension EnvironmentValues {
    @Entry var isSheetSurface = false
}

extension View {
    /// Marks a sheet's content: page and block tones flip (see `Surface`), and the sheet's own
    /// background (under the grabber, behind the keyboard) is the lifted tone.
    func sheetSurface() -> some View {
        presentationBackground(DS.Palette.canvasSoft)
            .environment(\.isSheetSurface, true)
    }
}
