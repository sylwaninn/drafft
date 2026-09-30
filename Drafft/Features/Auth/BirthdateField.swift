import SwiftUI

/// Birthday typed, not scrolled: three boxes (day, month, year, in the app language's order) over one
/// hidden number-pad field, so eight digits in a row fill them and delete walks back. Nothing is set
/// until the date is complete and real; no made-up starting date is ever shown.
struct BirthdateField: View {
    @Binding var date: Date?
    /// Oldest accepted birthday; anything earlier (or in the future) reads as a typo.
    let oldest: Date

    @State private var digits = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    enum Part { case day, month, year }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            ZStack {
                TextField("", text: Binding(get: { digits }, set: enter))
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .revealsOnFocus(focused)
                    .opacity(0.02)
                    .accessibilityLabel("Birthday")
                    .accessibilityValue(date.map { $0.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(.app)) } ?? digits)
                HStack(spacing: DS.Space.sm) {
                    ForEach(Array(order.enumerated()), id: \.offset) { i, part in
                        if i > 0 {
                            Text("/").font(.title3.weight(.semibold)).foregroundStyle(DS.Palette.mute)
                        }
                        box(part)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .contentShape(.rect)
            .onTapGesture { focused = true }

            if invalid {
                Label("Check the date: this one doesn't exist.", image: "danger-circle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DS.Palette.negative)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Motion.snappy, value: invalid)
        .onAppear {
            if let date, digits.isEmpty { digits = Self.digits(of: date, order: order) }
            focused = true
        }
    }

    // MARK: Boxes

    private func box(_ part: Part) -> some View {
        let range = self.range(of: part)
        let typed = String(digits.dropFirst(range.lowerBound).prefix(range.count))
        let current = focused && (digits.count < 8 ? range.contains(digits.count) : part == order.last)
        return (Text(typed).foregroundStyle(DS.Palette.ink)
                + Text(String(placeholder(part).dropFirst(typed.count))).foregroundStyle(DS.Palette.mute))
            .font(.displayBold(26, relativeTo: .title2).monospacedDigit())
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(DS.Palette.field, in: .rect(cornerRadius: DS.Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(invalid ? DS.Palette.negative : current ? DS.Palette.ink : DS.Palette.ink.opacity(0.2),
                                  lineWidth: invalid || current ? 2 : 1)
            }
            // The year takes the room of its four digits.
            .layoutPriority(part == .year ? 1 : 0)
            .frame(maxWidth: part == .year ? .infinity : 88)
    }

    private func placeholder(_ part: Part) -> String {
        switch part {
        case .day: L("DD")
        case .month: L("MM")
        case .year: L("YYYY")
        }
    }

    // MARK: Digits

    /// Day, month and year in the order the app's language writes dates (MM/DD/YYYY in English).
    private var order: [Part] { Self.order(for: .app) }

    static func order(for locale: Locale) -> [Part] {
        let format = DateFormatter.dateFormat(fromTemplate: "ddMMyyyy", options: 0, locale: locale) ?? "dd/MM/yyyy"
        var parts: [Part] = []
        for character in format {
            let part: Part? = switch character {
            case "d": .day
            case "M": .month
            case "y": .year
            default: nil
            }
            if let part, !parts.contains(part) { parts.append(part) }
        }
        return parts.count == 3 ? parts : [.day, .month, .year]
    }

    private func range(of part: Part) -> Range<Int> {
        var start = 0
        for p in order {
            let length = p == .year ? 4 : 2
            if p == part { return start..<start + length }
            start += length
        }
        return 0..<0
    }

    private func enter(_ raw: String) {
        digits = String(raw.filter(\.isNumber).prefix(8))
        guard digits.count == 8 else {
            date = nil
            invalid = false
            return
        }
        let value = { (part: Part) in Int(digits.dropFirst(range(of: part).lowerBound).prefix(range(of: part).count)) ?? 0 }
        let calendar = Self.calendar
        let parts = DateComponents(year: value(.year), month: value(.month), day: value(.day))
        // Real day only (no 31/02), and a birthday a person can have.
        if let d = calendar.date(from: parts), calendar.dateComponents([.year, .month, .day], from: d) == parts,
           d <= .now, d >= oldest {
            date = d
            invalid = false
            Haptics.select()
        } else {
            date = nil
            invalid = true
            Haptics.warning()
        }
    }

    /// A birthday is a calendar day, not an instant: kept at midnight UTC, the way the server writes
    /// it back (`yyyy-MM-dd`). Local midnight in Paris was the previous day in UTC.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }()

    static func digits(of date: Date, order: [Part]) -> String {
        let c = Self.calendar.dateComponents([.year, .month, .day], from: date)
        return order.map { part in
            switch part {
            case .day: String(format: "%02d", c.day ?? 0)
            case .month: String(format: "%02d", c.month ?? 0)
            case .year: String(format: "%04d", c.year ?? 0)
            }
        }.joined()
    }
}
