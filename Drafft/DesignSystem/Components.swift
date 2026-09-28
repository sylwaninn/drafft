import SwiftUI
import ImageIO
import Nuke
import NukeUI

// MARK: - Buttons

enum DrafftButtonKind { case primary, secondary, tertiary, dark, like }

struct DrafftButtonStyle: ButtonStyle {
    var kind: DrafftButtonKind = .primary
    var fullWidth = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            // A long translation takes a second, centred line (the button grows), never "…".
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.9)
            .padding(.vertical, DS.Space.xs)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 52)
            .padding(.horizontal, DS.Space.xl)
            .foregroundStyle(foreground)
            .background(background(pressed: configuration.isPressed), in: .rect(cornerRadius: DS.Radius.xl))
            .overlay {
                if kind == .tertiary {
                    RoundedRectangle(cornerRadius: DS.Radius.xl).strokeBorder(DS.Palette.ink, lineWidth: 1)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
            .contentShape(.rect(cornerRadius: DS.Radius.xl))
    }

    private var foreground: Color {
        switch kind {
        case .primary: DS.Palette.onLime
        case .like: DS.Palette.onLike
        case .secondary, .tertiary: DS.Palette.ink
        case .dark: DS.Palette.lime
        }
    }

    private func background(pressed: Bool) -> AnyShapeStyle {
        switch kind {
        case .primary: AnyShapeStyle(pressed ? DS.Palette.limeActive : DS.Palette.lime)
        case .like: AnyShapeStyle(pressed ? DS.Palette.likeActive : DS.Palette.like)
        case .secondary: AnyShapeStyle(DS.Palette.canvasSoft.opacity(pressed ? 0.7 : 1))
        case .tertiary: AnyShapeStyle(DS.Palette.canvas)
        case .dark: AnyShapeStyle(pressed ? DS.Palette.nightRaised : DS.Palette.night)
        }
    }
}

extension ButtonStyle where Self == DrafftButtonStyle {
    static var drafftPrimary: DrafftButtonStyle { .init(kind: .primary) }
    /// Primary, sized to its label: a single action in the middle of a page (empty states).
    static var drafftPrimaryFit: DrafftButtonStyle { .init(kind: .primary, fullWidth: false) }
    static var drafftSecondary: DrafftButtonStyle { .init(kind: .secondary) }
    static var drafftTertiary: DrafftButtonStyle { .init(kind: .tertiary) }
    static var drafftDark: DrafftButtonStyle { .init(kind: .dark) }
}

struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.92
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // The whole laid-out label takes the touch. Without it only drawn pixels do: a glyph
            // in a 68 pt frame, or a glass circle (glass isn't hit-testable), answered only when
            // the finger landed on the symbol itself.
            .contentShape(.rect)
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

/// Text actions ("Clear filters", "Forgot?", "Resend code"): the full 44 pt row takes the touch,
/// not just the letters, and the label dims while pressed.
struct TextLinkStyle: ButtonStyle {
    var minHeight: CGFloat = 44
    var fullWidth = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        // Disabled: mute grey at full strength (6:1 on light and dark sheets), not a faded
        // accent, so it stays readable while clearly out of play.
        Group {
            if isEnabled { configuration.label } else { configuration.label.foregroundStyle(DS.Palette.mute) }
        }
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: minHeight)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(Motion.select, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TextLinkStyle {
    static var textLink: TextLinkStyle { .init() }
    static func textLink(minHeight: CGFloat = 44, fullWidth: Bool) -> TextLinkStyle {
        .init(minHeight: minHeight, fullWidth: fullWidth)
    }
}

// MARK: - Chips

struct SportChip: View {
    let sport: Sport
    var selected = false
    var onDark = false
    /// Unselected fill override (e.g. sage chips on a white block).
    var fill: Surface?

    var body: some View {
        HStack(spacing: DS.Space.xs + 2) {
            Image(systemName: sport.symbol)
                .font(.subheadline.weight(.semibold))
            Text(sport.name)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .foregroundStyle(foreground)
        .background(background, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sport.name)
    }

    private var foreground: Color {
        if selected { return DS.Palette.onLime }
        return onDark ? .white : DS.Palette.ink
    }

    private var background: AnyShapeStyle {
        if selected { return AnyShapeStyle(DS.Palette.lime) }
        if let fill { return AnyShapeStyle(fill) }
        return onDark ? AnyShapeStyle(.white.opacity(0.16)) : AnyShapeStyle(DS.Palette.canvas)
    }
}

// MARK: - Text field

struct DrafftField: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""
    var isSecure = false
    var error: String?
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .next
    /// The server's length limit for the field, if any: typing stops there.
    var limit: Int?
    var onSubmit: () -> Void = {}

    @State private var revealed = false
    @FocusState private var focused: Bool
    @Environment(\.focusScroller) private var scroller
    @State private var anchor = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DS.Palette.ink)
            HStack(spacing: DS.Space.sm) {
                Group {
                    if isSecure && !revealed {
                        SecureField(title, text: $text, prompt: Text(prompt).foregroundStyle(DS.Palette.mute))
                    } else {
                        TextField(title, text: $text, prompt: Text(prompt).foregroundStyle(DS.Palette.mute))
                    }
                }
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(isSecure || keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled(isSecure || keyboard == .emailAddress)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .maxLength(limit ?? .max, of: $text)
                .focused($focused)
                .font(.body)
                .foregroundStyle(DS.Palette.ink)
                // The text field fills the whole row, so any touch on it lands in it.
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(.rect)

                if isSecure {
                    Button {
                        revealed.toggle()
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .foregroundStyle(DS.Palette.body)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel(revealed ? "Hide password" : "Show password")
                }
            }
            .padding(.leading, DS.Space.lg)
            .padding(.trailing, isSecure ? 0 : DS.Space.lg)
            .frame(minHeight: 52)
            // The padding around the text counts too: the whole field focuses it.
            .contentShape(.rect(cornerRadius: DS.Radius.md))
            .onTapGesture { focused = true }
            .background(DS.Palette.field, in: .rect(cornerRadius: DS.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(borderColor, lineWidth: focused || error != nil ? 2 : 1)
            }
            .animation(Motion.gentle, value: focused)
            .onChange(of: focused) { _, on in if on { scroller?.reveal(anchor) } }

            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DS.Palette.negative)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Motion.snappy, value: error)
        .id(anchor)
    }

    private var borderColor: Color {
        if error != nil { return DS.Palette.negative }
        return focused ? DS.Palette.ink : DS.Palette.ink.opacity(0.35)
    }
}

// MARK: - Photo

/// Photo that fills its frame without distorting. `name` is an asset name, a file path
/// (starting with "/") for photos the user picked, or a URL for photos on the server. Give `side` (the frame's shorter side, in
/// points) for small displays: a downsampled copy is drawn instead of the full photo. `blur`
/// (points, with `side`) draws a copy with the blur baked in, instead of a live blur filter.
struct Photo: View {
    let name: String
    var side: CGFloat?
    var blur: CGFloat = 0

    var body: some View {
        Color.clear
            .overlay {
                if name.hasPrefix("http") || name.hasPrefix("/") {
                    LoadedPhoto(name: name)
                } else if let img = blur > 0
                            ? ImageStore.blurred(name, fraction: blur / max(side ?? 200, 1))
                            : side == nil ? ImageStore.preparedFull(name) : ImageStore.image(name, side: side) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Image(name).resizable().scaledToFill()
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// A photo on the server (`http…`) or picked on this phone (`/…`), through `Images`: decoded in the
/// background at the frame's size, shared downloads, capped caches. A copy already in memory shows
/// on the first frame; otherwise its ThumbHash preview (`MediaPreviews`), or a sage tile, stands in
/// until it's there.
private struct LoadedPhoto: View {
    let name: String
    @Environment(\.displayScale) private var scale
    /// Decoded once per view (a few microseconds, then cached by key).
    private var preview: UIImage? { MediaPreviews.image(for: name) }

    var body: some View {
        GeometryReader { geo in
            LazyImage(request: Images.request(name, points: geo.size, scale: scale),
                      transaction: Transaction(animation: .easeOut(duration: 0.2))) { state in
                ZStack {
                    Rectangle().fill(DS.Palette.canvasSoft)
                    if state.image == nil, let preview {
                        Image(uiImage: preview).resizable().interpolation(.medium).scaledToFill()
                    }
                    if let image = state.image {
                        image.resizable().scaledToFill().transition(.opacity)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Photos and video posters sent in chat (kept as Data on the message): their size is read from
/// the header, without decoding, and the pixels are decoded in the background at the bubble's size.
enum MessageImage {
    /// Pixel size, upright (EXIF orientation applied), from the image header only.
    static func size(of data: Data) -> CGSize? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return orientation >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }

    static func request(_ id: UUID, data: Data, points: CGSize, scale: CGFloat) -> ImageRequest {
        let side = max(points.width, points.height) * scale
        var request = ImageRequest(id: "message-\(id.uuidString)-\(Int(side))", data: { data })
        request.thumbnail = .init(size: CGSize(width: side, height: side), unit: .pixels, contentMode: .aspectFill)
        return request
    }
}

/// A chat photo or poster from its bytes, decoded off the main thread (see `MessageImage`).
struct MessagePhoto: View {
    let id: UUID
    let data: Data
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { geo in
            LazyImage(request: MessageImage.request(id, data: data, points: geo.size, scale: scale)) { state in
                ZStack {
                    DS.Palette.night
                    state.image?.resizable().scaledToFill()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 48
    var ring = false
    var body: some View {
        Photo(name: name, side: size)
            .frame(width: size, height: size)
            .clipShape(.circle)
            .padding(ring ? 3 : 0)
            .overlay {
                if ring { Circle().strokeBorder(DS.Palette.lime, lineWidth: 2.5) }
            }
    }
}

// MARK: - Google mark

// MARK: - Text that never truncates

/// A label and a trailing value side by side while both fit in full; otherwise the value moves
/// under the label. Neither is ever cut with "…", whatever the language.
struct AdaptiveRow<Leading: View, Trailing: View>: View {
    var spacing: CGFloat = DS.Space.sm
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: spacing) {
                leading.fixedSize()
                Spacer(minLength: spacing)
                trailing.fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                leading.fixedSize(horizontal: false, vertical: true)
                trailing.fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Sports line

/// Sport names on one line, never truncated: shows as many as fit, then "+X".
struct SportsLine: View {
    let sports: [Sport]
    var font: Font = .subheadline
    var color: Color = DS.Palette.body

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: sports.count, through: 1, by: -1)), id: \.self) { shown in
                let names = sports.prefix(shown).map(\.name).joined(separator: ", ")
                let rest = sports.count - shown
                Text(rest > 0 ? "\(names) +\(rest)" : names)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .font(font)
        .foregroundStyle(color)
        .accessibilityElement()
        .accessibilityLabel(sports.map(\.name).joined(separator: ", "))
    }
}

// MARK: - Sport badges

/// Sports as a stack of round badges, like overlapping avatars: each sport's symbol on a solid
/// disc, ringed in the surface colour so neighbours stay distinct. Beyond `limit`, the last disc
/// says "+X". Names are read by VoiceOver.
struct SportBadgeStack: View {
    let sports: [Sport]
    var size: CGFloat = 36
    var limit = 4
    /// The block the stack sits on: the ring that separates the discs.
    var surface: Color = DS.Palette.night
    /// Solid (never translucent, or overlaps would show): the card's white-14 % wash, flattened.
    var fill: Color = Color(light: 0x303230, dark: 0x41443D)
    var glyph: Color = .white

    var body: some View {
        let overflow = sports.count > limit
        let shown = overflow ? Array(sports.prefix(limit - 1)) : sports
        HStack(spacing: -size * 0.18) {
            ForEach(shown) { sport in
                disc { Image(systemName: sport.symbol).font(.system(size: size * 0.42, weight: .bold)) }
            }
            if overflow {
                disc {
                    Text(verbatim: "+\(sports.count - shown.count)")
                        .font(.system(size: size * 0.36, weight: .heavy).monospacedDigit())
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(sports.map(\.name).joined(separator: ", "))
    }

    private func disc<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .foregroundStyle(glyph)
            .frame(width: size, height: size)
            .background(fill, in: .circle)
            .overlay(Circle().strokeBorder(surface, lineWidth: 3))
    }
}

// MARK: - Checkbox

/// Square checkbox: lime when on, big enough to hit and read, quick to tick.
/// A checkbox is the one selection mark too: a large CheckDisc in a 44 pt target.
struct DrafftCheckbox: View {
    let isOn: Bool
    var body: some View {
        CheckDisc(isOn: isOn, size: 28, ring: DS.Palette.ink.opacity(0.45))
            .frame(width: 44, height: 44)
    }
}

// MARK: - Check disc

/// The one selection mark: an accent disc with an on-accent tick when on, a ring when off.
/// The tick is always drawn in on-lime, so it reads on any surface (white, sage, night).
struct CheckDisc: View {
    let isOn: Bool
    var size: CGFloat = 24
    /// Ring colour when off (lighter on night surfaces).
    var ring: Color = DS.Palette.ink.opacity(0.25)
    /// On a lime row the disc inverts (ink disc, lime tick), so it never melts into the fill.
    var onLimeFill = false

    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(onLimeFill ? DS.Palette.onLime : DS.Palette.lime)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.46, weight: .heavy))
                    .foregroundStyle(onLimeFill ? DS.Palette.lime : DS.Palette.onLime)
            } else {
                Circle().strokeBorder(ring, lineWidth: 2)
            }
        }
        .frame(width: size, height: size)
        .animation(.snappy(duration: 0.12), value: isOn)
        .accessibilityHidden(true)
    }
}

extension View {
    /// A selection's weight switch lands in the same frame as the tap, even inside an animated
    /// transaction (the check disc animates on its own).
    func instantWeight() -> some View { transaction { $0.animation = nil } }

    /// A changing label: its digits roll (`numericText`) while the wording stays the same; when the
    /// words change ("Any" ↔ "3 selected", "Resend in 0:05" ↔ "Resend code") the old and new
    /// labels cross-fade in place instead, so a longer old label never slides out of its block.
    func rollingDigits(wording: some Hashable, countsDown: Bool = false) -> some View {
        contentTransition(.numericText(countsDown: countsDown))
            .id(wording)
            .transition(.opacity)
    }
}

extension String {
    /// The words without the numbers, to tell a count change from a wording change.
    var wording: String { filter { !$0.isNumber } }

    /// At most `limit` characters as the database counts them (Unicode scalars, `char_length`),
    /// never splitting a character.
    func limited(to limit: Int) -> String {
        guard unicodeScalars.count > limit else { return self }
        var out = ""
        for ch in self {
            guard out.unicodeScalars.count + ch.unicodeScalars.count <= limit else { break }
            out.append(ch)
        }
        return out
    }
}

extension View {
    /// Typing stops at the server's limit for that field (its `check` constraint), so a save is
    /// never refused for length.
    func maxLength(_ limit: Int, of text: Binding<String>) -> some View {
        onChange(of: text.wrappedValue) { _, value in
            let kept = value.limited(to: limit)
            if kept != value { text.wrappedValue = kept }
        }
    }
}

/// Multi-line field in the DrafftField pattern: label above, one bordered box that takes
/// touches everywhere, the character count tucked in its bottom corner.
struct DrafftTextArea: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""
    var limit = 200
    /// Page fill by default; sage when the area sits on a white block.
    var fill: Surface = DS.Palette.canvas
    /// Off when the surrounding block already names the field.
    var showsTitle = true

    @FocusState private var focused: Bool

    private var over: Bool { text.count > limit }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs + 2) {
            if showsTitle {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Palette.ink)
            }
            VStack(alignment: .trailing, spacing: DS.Space.xs) {
                TextField(title, text: $text, prompt: Text(prompt).foregroundStyle(DS.Palette.mute), axis: .vertical)
                    .lineLimit(4...8)
                    .font(.body)
                    .foregroundStyle(DS.Palette.ink)
                    .focused($focused)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Text(over ? "\(text.count - limit) too many" : "\(limit - text.count) left")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    // Body grey, not mute: the area often sits on sage, where mute is under 4.5:1.
                    .foregroundStyle(over ? DS.Palette.negative : DS.Palette.body)
                    .rollingDigits(wording: over)
                    .animation(Motion.snappy, value: text.count)
            }
            .padding(DS.Space.lg)
            .frame(minHeight: 140, alignment: .top)
            .contentShape(.rect(cornerRadius: DS.Radius.lg))
            .onTapGesture { focused = true }
            .background(fill, in: .rect(cornerRadius: DS.Radius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .strokeBorder(over ? DS.Palette.negative : focused ? DS.Palette.ink : DS.Palette.ink.opacity(0.35),
                                  lineWidth: focused || over ? 2 : 1)
            }
            .animation(Motion.gentle, value: focused)
            .revealsOnFocus(focused)

        }
    }
}
