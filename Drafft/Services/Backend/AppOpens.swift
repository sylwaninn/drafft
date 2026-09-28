import Foundation
import UIKit

/// Each time the app comes to the front, signed in: which iPhone, iOS and app version, locale and time
/// zone (`report_app_open`). The server adds the IP and country. For the team's safety checks only (ban
/// evasion, shared devices, the last time someone opened drafft); the server keeps it 180 days to a year.
enum AppOpens {
    static func report() async {
        guard await Backend.shared.hasSession,
              let install = await UIDevice.current.identifierForVendor else { return }
        let info = Bundle.main.infoDictionary ?? [:]
        let device: [String: Any] = [
            "model": model,
            "os": await UIDevice.current.systemVersion,
            "app": info["CFBundleShortVersionString"] as? String ?? "",
            "build": info["CFBundleVersion"] as? String ?? "",
            "locale": Locale.current.identifier,
            "timezone": TimeZone.current.identifier
        ]
        _ = try? await Backend.shared.rpc(
            "report_app_open", ["p_install": install.uuidString, "p_device": device])
    }

    /// The hardware identifier ("iPhone17,1"), not the marketing name.
    private static var model: String {
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { Data($0.prefix { $0 != 0 }) }
        return String(bytes: machine, encoding: .utf8) ?? ""
    }
}
