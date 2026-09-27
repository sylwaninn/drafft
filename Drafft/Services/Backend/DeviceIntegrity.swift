import DeviceCheck
import Foundation

/// Apple DeviceCheck: at each launch and sign-in, a fresh token goes to the server (`device-check`),
/// which keeps a closed account from coming back on the same iPhone. The token says nothing to the app
/// or the server; only Apple knows which iPhone it stands for. Never on the Simulator.
enum DeviceIntegrity {
    static func report() async {
        guard DCDevice.current.isSupported, await Backend.shared.hasSession,
              let token = try? await DCDevice.current.generateToken() else { return }
        // Builds installed from Xcode use Apple's development DeviceCheck, like their pushes.
        let environment = PushEnvironment.current == "sandbox" ? "development" : "production"
        _ = try? await Backend.shared.function(
            "device-check", ["token": token.base64EncodedString(), "environment": environment])
    }
}
