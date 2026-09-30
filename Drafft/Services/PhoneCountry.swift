import Foundation
import PhoneNumberKit

/// A country at the phone step: every region Google's libphonenumber knows (PhoneNumberKit), searchable
/// by name or dial code. Which lines get a code is the server's call (Twilio Lookup, mobile lines only).
struct PhoneCountry: Hashable, Identifiable {
    /// ISO 3166 region code ("FR").
    let region: String
    /// "+33"
    let dial: String
    /// A mobile number of the country, written the national way: the field's placeholder.
    let example: String
    var id: String { region }
    /// The region's flag, from its two letters.
    var flag: String {
        String(String.UnicodeScalarView(region.unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }))
    }
    /// Country name in the app's language.
    var name: String { Locale.app.localizedString(forRegionCode: region) ?? region }

    /// Loads the metadata once (a few ms), on first use.
    @MainActor static let phoneNumbers = PhoneNumberUtility()

    @MainActor static let all: [PhoneCountry] = phoneNumbers.allCountries().compactMap { country($0) }

    @MainActor static func country(_ region: String) -> PhoneCountry? {
        guard region.count == 2, let code = phoneNumbers.countryCode(for: region) else { return nil }
        let example = phoneNumbers.getFormattedExampleNumber(forCountry: region, ofType: .mobile, withFormat: .national)
        return PhoneCountry(region: region, dial: "+\(code)", example: example ?? "")
    }

    /// The iPhone's region, else France.
    @MainActor static var initial: PhoneCountry {
        Locale.current.region.flatMap { country($0.identifier) } ?? country("FR") ?? all[0]
    }

    /// A number the phone step takes: valid for the country, and a mobile line (or one that may be, as
    /// in the US). Digits only, typed the national way ("06 12…" or "6 12…").
    @MainActor static func mobileNumber(_ national: String, in country: PhoneCountry) -> PhoneNumber? {
        let digits = national.filter(\.isNumber)
        guard !digits.isEmpty, let number = try? phoneNumbers.parse(digits, withRegion: country.region),
              country.dial == "+\(number.countryCode)",
              number.type == .mobile || number.type == .fixedOrMobile else { return nil }
        return number
    }

    /// The number typed the international way ("+44 7…", "0044 7…", or the exit code of the country
    /// picked, like 011 from the US): the country its calling code names, and the national part after
    /// it, formatted when complete ("07700 900123"). Nil when it's typed the national way ("06 12…",
    /// "6 12…"): the picked country reads it. Every country libphonenumber knows, shared codes included
    /// (+1 US or Canada, +44 UK or Jersey, +7 Russia or Kazakhstan: the number itself says which).
    @MainActor static func international(_ typed: String, from current: PhoneCountry) -> (country: PhoneCountry, national: String)? {
        let digits = typed.filter { $0.isASCII && $0.isNumber }
        let rest: Substring
        if let first = typed.first(where: { !$0.isWhitespace }), first == "+" || first == "＋" {
            rest = Substring(digits)
        } else if let exit = exitCodeLength(of: digits, in: current.region) {
            rest = digits.dropFirst(exit)
        } else {
            return nil
        }
        // Calling codes are 1 to 3 digits and none is the start of another (E.164): the first match is it.
        for length in 1...3 where rest.count >= length {
            guard let code = UInt64(rest.prefix(length)), phoneNumbers.countries(withCode: code)?.isEmpty == false else { continue }
            let national = String(rest.dropFirst(length))
            let full = try? phoneNumbers.parse("+" + rest, ignoreType: true)
            let region = full.flatMap(phoneNumbers.getRegionCode(of:))
                ?? (phoneNumbers.countryCode(for: current.region) == code ? current.region : phoneNumbers.mainCountry(forCode: code))
            guard let country = region.flatMap(country) else { return nil }
            let formatted = full.map { phoneNumbers.format($0, toType: .national) } ?? national
            return (country, formatted)
        }
        return nil
    }

    /// How many leading digits are the picked country's exit code (00 in most of the world, 011 in
    /// North America…), from libphonenumber's metadata. Nil when the digits don't start with it.
    @MainActor private static func exitCodeLength(of digits: String, in region: String) -> Int? {
        guard let pattern = phoneNumbers.metadata(for: region)?.internationalPrefix,
              let regex = try? NSRegularExpression(pattern: "^(?:\(pattern))"),
              let match = regex.firstMatch(in: digits, range: NSRange(digits.startIndex..., in: digits)),
              match.range.length > 0, match.range.length < digits.count else { return nil }
        return match.range.length
    }

    /// The account's number as Supabase Auth keeps it ("33612345678"), written the international way.
    @MainActor static func display(_ stored: String) -> String {
        let e164 = "+" + stored.filter(\.isNumber)
        guard let number = try? phoneNumbers.parse(e164, ignoreType: true) else { return e164 }
        return phoneNumbers.format(number, toType: .international)
    }
}
