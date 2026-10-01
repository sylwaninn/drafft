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
    @Environment(\.isNightSurface) private var onNight

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
        case .primary: onNight ? DS.Palette.onAccentOnNight : DS.Palette.onLime
        case .like: DS.Palette.onLike
        case .secondary, .tertiary: DS.Palette.ink
        case .dark: DS.Palette.accentOnNight
        }
    }

    private func background(pressed: Bool) -> AnyShapeStyle {
        switch kind {
        case .primary where onNight: AnyShapeStyle(pressed ? DS.Palette.accentOnNightActive : DS.Palette.accentOnNight)
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
            Image(sport.symbol)
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
                        Image(revealed ? "eye-closed" : "eye")
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
                Label(error, image: "danger-circle")
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
    /// Download order among photos waiting (the deck: the card in play first).
    var priority: ImageRequest.Priority = .normal

    var body: some View {
        Color.clear
            .overlay {
                if name.hasPrefix("http") || name.hasPrefix("/") {
                    // Blurred at decode time, never a live blur (locked likes).
                    LoadedPhoto(name: name, blur: blur / max(side ?? 200, 1), priority: priority)
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

/// A photo on the server (`http…`) or picked on this phone (`/…`), through `Images`: the copy the frame
/// needs, decoded in the background at the frame's size, shared downloads, capped caches. A copy already
/// in memory shows on the first frame; otherwise its ThumbHash preview (`MediaPreviews`), or a sage tile,
/// stands in until it's there. On a slow connection a large frame first shows a small copy
/// (`Images.preview`), sharp enough to read the photo, while the right one arrives.
private struct LoadedPhoto: View {
    let name: String
    /// Blur radius as a share of the photo's shorter side (0: sharp).
    var blur: CGFloat = 0
    var priority: ImageRequest.Priority = .normal
    @Environment(\.displayScale) private var scale
    /// Decoded once per view (a few microseconds, then cached by key).
    private var preview: UIImage? { MediaPreviews.image(for: name) }

    var body: some View {
        GeometryReader { geo in
            LazyImage(request: Images.request(name, points: geo.size, scale: scale, blur: blur),
                      transaction: Transaction(animation: .easeOut(duration: 0.2))) { state in
                ZStack {
                    Rectangle().fill(DS.Palette.canvasSoft)
                    if state.image == nil, let preview {
                        Image(uiImage: preview).resizable().interpolation(.medium).scaledToFill()
                    }
                    if state.image == nil, blur == 0, min(geo.size.width, geo.size.height) >= 200,
                       NetworkQuality.shared.isLimited {
                        LazyImage(request: Images.preview(name, points: geo.size, scale: scale)) { small in
                            if let image = small.image { image.resizable().scaledToFill() }
                        }
                    }
                    if let image = state.image {
                        image.resizable().scaledToFill().transition(.opacity)
                    }
                }
            }
            .priority(priority)
            #if DECK_PHOTO_METRICS
            .onCompletion { DeckPhotoMetrics.finished(name, $0) }
            .onAppear { DeckPhotoMetrics.appeared(name) }
            #endif
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

    static func request(_ id: String, data: Data, points: CGSize, scale: CGFloat) -> ImageRequest {
        let side = max(points.width, points.height) * scale
        var request = ImageRequest(id: "message-\(id)-\(Int(side))", data: { data })
        request.thumbnail = .init(size: CGSize(width: side, height: side), unit: .pixels, contentMode: .aspectFill)
        return request
    }
}

/// A chat photo or poster from its bytes, decoded off the main thread (see `MessageImage`).
struct MessagePhoto: View {
    let id: String
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
    @Environment(\.isNightSurface) private var onNight
    var body: some View {
        Photo(name: name, side: size)
            .frame(width: size, height: size)
            .clipShape(.circle)
            .padding(ring ? 3 : 0)
            .overlay {
                if ring { Circle().strokeBorder(onNight ? DS.Palette.accentOnNight : DS.Palette.lime, lineWidth: 2.5) }
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

// MARK: - Sports on one line

/// Sports as named chips on a single line, never two: as many as fit in order, then "+X" for the
/// rest. When not even one chip and its "+X" fit, the shortest name leads instead, cut short if it
/// still doesn't fit (the one place a sport name is truncated).
struct SportChipsLine: View {
    let sports: [Sport]

    var body: some View {
        SingleLineChips(spacing: DS.Space.xs + 2) {
            ForEach(sports) { SportChip(sport: $0, onDark: true).lineLimit(1) }
            // One candidate "+X" per possible count; the layout shows the one it needs.
            ForEach(1..<max(sports.count, 1), id: \.self) { hidden in
                Text(verbatim: "+\(hidden)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.sm)
                    .background(.white.opacity(0.16), in: .capsule)
                    .fixedSize()
                    .layoutValue(key: HiddenCount.self, value: hidden)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(sports.map(\.name).joined(separator: ", "))
    }
}

private struct HiddenCount: LayoutValueKey {
    static let defaultValue: Int? = nil
}

/// One row: the longest prefix of the items that fits with its "+X" badge; otherwise the narrowest
/// item alone, squeezed to the room its badge leaves. Unused subviews are parked out of sight.
private struct SingleLineChips: Layout {
    var spacing: CGFloat

    private struct Plan { var frames: [Int: CGRect] = [:]; var size: CGSize = .zero }

    private func plan(width: CGFloat, subviews: Subviews) -> Plan {
        let items = subviews.indices.filter { subviews[$0][HiddenCount.self] == nil }
        let badges = Dictionary(uniqueKeysWithValues: subviews.indices.compactMap { i in
            subviews[i][HiddenCount.self].map { ($0, i) }
        })
        let ideal = { (i: Int) in subviews[i].sizeThatFits(.unspecified) }

        func row(_ entries: [(Int, CGFloat?)]) -> Plan {
            var p = Plan(), x: CGFloat = 0
            let height = entries.map { ideal($0.0).height }.max() ?? 0
            for (i, forced) in entries {
                let w = forced ?? ideal(i).width
                let h = subviews[i].sizeThatFits(ProposedViewSize(width: w, height: nil)).height
                p.frames[i] = CGRect(x: x, y: (height - h) / 2, width: w, height: h)
                x += w + spacing
            }
            p.size = CGSize(width: max(0, x - spacing), height: height)
            return p
        }

        guard !items.isEmpty else { return Plan() }
        for shown in stride(from: items.count, through: 1, by: -1) {
            let hidden = items.count - shown
            var entries: [(Int, CGFloat?)] = items.prefix(shown).map { ($0, nil) }
            if hidden > 0, let b = badges[hidden] { entries.append((b, nil)) }
            let total = entries.reduce(0) { $0 + ideal($1.0).width } + spacing * CGFloat(entries.count - 1)
            if total <= width { return row(entries) }
        }
        // Not even one chip with its badge: the shortest sport leads, cut to the room left.
        let lead = items.min { ideal($0).width < ideal($1).width } ?? items[0]
        let badge = items.count > 1 ? badges[items.count - 1] : nil
        let room = width - (badge.map { ideal($0).width + spacing } ?? 0)
        var entries: [(Int, CGFloat?)] = [(lead, max(0, min(ideal(lead).width, room)))]
        if let badge { entries.append((badge, nil)) }
        return row(entries)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let p = plan(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? p.size.width, height: p.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = plan(width: bounds.width, subviews: subviews)
        for i in subviews.indices {
            if let f = p.frames[i] {
                subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
            } else {
                subviews[i].place(at: CGPoint(x: -10_000, y: -10_000), proposal: .zero)
            }
        }
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
    @Environment(\.isNightSurface) private var onNight

    var body: some View {
        let accent = onNight ? DS.Palette.accentOnNight : DS.Palette.lime
        let onAccent = onNight ? DS.Palette.onAccentOnNight : DS.Palette.onLime
        ZStack {
            if isOn {
                Circle().fill(onLimeFill ? onAccent : accent)
                Image("check")
                    .font(.system(size: size * 0.46, weight: .heavy))
                    .foregroundStyle(onLimeFill ? accent : onAccent)
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
