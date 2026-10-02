import Foundation

/// A value that may leave the phone in an event, a tag or a log line: a number, a yes/no, a short code,
/// or a few codes. Never free text (`PrivacyGuard` checks the codes).
enum TelemetryValue: Sendable, Equatable, CustomStringConvertible {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case strings([String])

    /// For the SDKs, which take `Any`.
    var raw: Any {
        switch self {
        case let .bool(v): v
        case let .int(v): v
        case let .double(v): v
        case let .string(v): v
        case let .strings(v): v
        }
    }

    var description: String {
        switch self {
        case let .bool(v): String(v)
        case let .int(v): String(v)
        case let .double(v): String(v)
        case let .string(v): v
        case let .strings(v): v.joined(separator: ",")
        }
    }
}

/// What can be a property: numbers, booleans, strings (checked to be codes), lists of codes, and the
/// enums of `AnalyticsEvent` (their raw value, a snake_case code).
protocol TelemetryValueConvertible: Sendable {
    var telemetryValue: TelemetryValue { get }
}

extension Bool: TelemetryValueConvertible { var telemetryValue: TelemetryValue { .bool(self) } }
extension Int: TelemetryValueConvertible { var telemetryValue: TelemetryValue { .int(self) } }
extension Double: TelemetryValueConvertible { var telemetryValue: TelemetryValue { .double(self) } }
extension String: TelemetryValueConvertible { var telemetryValue: TelemetryValue { .string(self) } }
extension TelemetryValue: TelemetryValueConvertible { var telemetryValue: TelemetryValue { self } }

extension Array: TelemetryValueConvertible where Element == String {
    var telemetryValue: TelemetryValue { .strings(self) }
}

extension TelemetryValueConvertible where Self: RawRepresentable, RawValue == String {
    var telemetryValue: TelemetryValue { .string(rawValue) }
}

extension String {
    /// A Swift name as a code: `tooManyCodes` becomes `too_many_codes`.
    var snakeCased: String {
        replacingOccurrences(of: "([a-z])([A-Z])", with: "$1_$2", options: .regularExpression).lowercased()
    }
}

/// Properties as written at the call: a nil value is left out.
typealias TelemetryProperties = [String: (any TelemetryValueConvertible)?]
