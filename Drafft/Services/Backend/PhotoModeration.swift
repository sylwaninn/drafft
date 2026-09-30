import Foundation
import Observation
import UIKit

/// Where a profile photo stands on the server: sent, then judged by moderation (AWS Rekognition in
/// the backend's db-events function). Keyed by the photo's local path, as the photo grids show it.
@MainActor
@Observable
final class PhotoModeration {
    static let shared = PhotoModeration()

    enum State: Equatable {
        case uploading
        case checking
        case approved
        case refused
        /// Borderline for Rekognition, too large for it, or a second review asked: a person decides.
        case inReview
        case failed(String)

        /// Still on its way: the tile is dimmed with a small loader.
        var isWorking: Bool { self == .uploading || self == .checking }
        /// The automatic check has spoken (approved, refused, or handed to a person).
        var isJudged: Bool { self == .approved || self == .refused || self == .inReview }
    }

    /// A refused photo, for its banner and its explanation.
    struct Refusal: Identifiable, Equatable {
        let path: String
        var id: String { path }
    }

    private(set) var states: [String: State] = [:]
    /// Server id of each photo, once registered.
    /// Kept on the device, so a push tapped after the app was closed still finds its photo.
    private(set) var mediaIDs: [String: String] = UserDefaults.standard.dictionary(forKey: "photoModeration.mediaIDs")
        as? [String: String] ?? [:] {
        didSet { UserDefaults.standard.set(mediaIDs, forKey: "photoModeration.mediaIDs") }
    }
    /// The failed photo whose reason is on screen (tap on its badge).
    var shownFailure: String?
    /// In-app banner: a photo was just refused (the push does it when the app is closed).
    var refusalBanner: Refusal?
    /// A photo to take off the profile (from the refusal sheet): the grid showing it removes it.
    var removeRequest: String?

    /// Photos read back from the server (their link, as the grids show them): the id of each one
    /// moderation hasn't approved, so it can be looked at again or removed. Not kept on the device:
    /// every read of the account gives them again.
    private var serverIDs: [String: String] = [:]

    /// The server id of a photo, once registered.
    func id(for path: String) -> String? { mediaIDs[path] ?? serverIDs[path] }

    /// Where a photo stands, as the grid and the profile read it. Nil: nothing to say (a photo on the
    /// server moderation approved, or one never sent).
    func state(of path: String) -> State? { states[path] }

    /// Whether a photo may show as the profile, to the person themselves included: only once approved.
    /// A photo read back from the server with no state was approved (the others are tracked below).
    func isShown(_ path: String) -> Bool {
        guard let state = states[path] else { return !path.hasPrefix("/") }
        return state == .approved
    }

    /// The account's photos as the server has them: a refused one stays on the person's own grid
    /// (to ask for a second look or remove it) and one still pending shows as in review. Neither is
    /// ever on the profile.
    func track(_ photos: [ProfileSync.OwnPhoto]) {
        for photo in photos {
            // One link per photo: the previous signed link of the same photo goes.
            for (link, id) in serverIDs where id == photo.id && link != photo.link {
                serverIDs[link] = nil
                states[link] = nil
            }
            switch photo.status {
            case "approved":
                serverIDs[photo.link] = nil
                states[photo.link] = nil
            case "rejected":
                serverIDs[photo.link] = photo.id
                states[photo.link] = .refused
            default:
                serverIDs[photo.link] = photo.id
                states[photo.link] = .inReview
            }
        }
    }

    /// A picked photo whose state this launch doesn't know (a sign-up resumed after the app was
    /// closed): its verdict read again, or the photo sent again if the server never got it.
    func ensureChecked(_ path: String) {
        guard path.hasPrefix("/"), states[path] == nil else { return }
        guard let id = mediaIDs[path] else { submit(path); return }
        states[path] = .checking
        Task {
            struct Status: Decodable { let status: String }
            guard let data = try? await Backend.shared.select("profile_media?id=eq.\(id)&select=status"),
                  let rows = try? JSONDecoder().decode([Status].self, from: data) else {
                states[path] = .failed(Self.failure(Backend.BackendError.http(0, "unreachable")))
                return
            }
            switch rows.first?.status {
            case "approved": settle(path, .approved)
            case "rejected": states[path] = .refused
            case "pending":
                let verdict = (try? await verdict(for: id)) ?? .inReview
                if states[path] == .checking { settle(path, verdict) }
            default:
                // Gone from the server: sent again.
                mediaIDs[path] = nil
                states[path] = nil
                submit(path)
            }
        }
    }

    /// Waits for a picked photo to be uploaded and registered (moderation may still be running).
    /// Nil if it failed.
    func waitForID(_ path: String) async -> String? {
        if states[path] == nil && mediaIDs[path] == nil { submit(path) }
        for _ in 0..<600 {
            if let id = mediaIDs[path] { return id }
            if case .failed = states[path] { return nil }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    /// Clears a failed attempt and sends the photo again.
    func retry(_ path: String) {
        states[path] = nil
        submit(path)
    }

    /// The failure reason for a photo, in plain words when we know the cause.
    func reason(_ path: String) -> String {
        guard case .failed(let message) = states[path] else { return "" }
        return message
    }

    /// Why a photo couldn't be sent, as its tile explains it: a refusal by the server in its own
    /// words (photo limit, file too large…), the connection only when that's the likely cause.
    private static func failure(_ error: Error) -> String {
        if case Backend.BackendError.signedOut = error { return L("Log in again to send your photos.") }
        if let text = ServerMessage.text(for: error) { return text }
        if ServerMessage.code(of: error) != nil { return ServerMessage.generic }
        return L("It couldn't be sent. Check your connection and try again.")
    }

    /// Compress, upload to the media bucket, register it (add_profile_media), then follow its
    /// moderation status until it's decided.
    func submit(_ path: String) {
        guard states[path] == nil else { return }
        states[path] = .uploading
        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try Data(contentsOf: URL(fileURLWithPath: path))
                }.value
                let tickets = EdgeFunctionTicketProvider(functionsURL: BackendConfig.functionsURL) {
                    try await Backend.shared.accessToken()
                }
                let uploaded = try await MediaUploads.photo(data, tickets: tickets)
                // The session exists now: this device can receive the "refused" push.
                await NotificationService.shared.syncPushToken()
                states[path] = .checking
                var args: [String: Any] = ["p_key": uploaded.key, "p_width": uploaded.width, "p_height": uploaded.height]
                if let hash = uploaded.thumbHash { args["p_thumbhash"] = hash }
                let row = try await Backend.shared.rpc("add_profile_media", args)
                struct Row: Decodable { let id: String }
                let id = try JSONDecoder().decode(Row.self, from: row).id
                mediaIDs[path] = id
                let verdict = try await verdict(for: id)
                // A live `media` event may have settled it already (apply): only a newer word counts.
                if states[path] == .checking { settle(path, verdict) }
            } catch {
                states[path] = .failed(Self.failure(error))
            }
        }
    }

    /// Asks a person to look at a refused photo again. It stays off the profile meanwhile.
    func requestReview(_ path: String) async throws {
        // Not uploaded (yet): nothing the team could look at, so never say it was sent.
        guard let id = id(for: path) else { throw Backend.BackendError.http(404, "photo not on the server") }
        _ = try await Backend.shared.rpc("request_media_review", ["p_media": id])
        states[path] = .inReview
    }

    /// Takes a refused photo off the profile: from the grid, and from the server.
    func remove(_ path: String) {
        removeRequest = path
        if let id = id(for: path) {
            Task { _ = try? await Backend.shared.rpc("delete_media", ["p_id": id]) }
        }
        states[path] = nil
        mediaIDs[path] = nil
        serverIDs[path] = nil
    }

    /// A `media` event from the person's Realtime topic (UserChannel): the automatic
    /// check or the team decided on one of their photos. The tile follows at once; a refusal gets
    /// its banner, with the second look offered by its explanation. A photo this device doesn't
    /// know (added from another phone) is left alone.
    func apply(mediaID: String, status: String) {
        guard let path = path(of: mediaID) else { return }
        switch status {
        case "approved": settle(path, .approved)
        case "rejected": settle(path, .refused)
        // Back to pending: a second look was asked (here or on another device).
        case "pending" where states[path] == .refused: settle(path, .inReview)
        default: break
        }
    }

    /// The photo a server id belongs to: picked on this device, or read back from the server.
    private func path(of mediaID: String) -> String? {
        mediaIDs.first(where: { $0.value == mediaID })?.key ?? serverIDs.first(where: { $0.value == mediaID })?.key
    }

    /// Sets a photo's verdict; announces a refusal once, when it becomes one.
    private func settle(_ path: String, _ state: State) {
        let was = states[path]
        states[path] = state
        if state == .refused && was != .refused { announceRefusal(path) }
    }

    /// From the push: shows the explanation for that photo, once the app is on screen (a tap on a
    /// push can launch it: its window takes a moment to exist).
    func openRefusal(mediaID: String) {
        guard let path = path(of: mediaID) else { return }
        states[path] = .refused
        refusalBanner = nil
        Task {
            for _ in 0..<30 {
                if UIApplication.shared.applicationState == .active, TopOverlayWindow.appWindow?.rootViewController != nil {
                    // Let the launch or the return from the background finish its transition.
                    try? await Task.sleep(for: .milliseconds(400))
                    PhotoRefusalPresenter.show(Refusal(path: path))
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Open app: a banner. Closed or in the background: the server's push says it.
    private func announceRefusal(_ path: String) {
        guard UIApplication.shared.applicationState == .active else { return }
        Haptics.warning()
        refusalBanner = Refusal(path: path)
    }

    /// Polls the status (every second, up to 30 s). Still pending after that: a person decides, and
    /// their decision arrives as a `media` event (apply).
    private func verdict(for id: String) async throws -> State {
        struct Status: Decodable { let status: String }
        for _ in 0..<30 {
            try await Task.sleep(for: .seconds(1))
            let data = try await Backend.shared.select("profile_media?id=eq.\(id)&select=status")
            switch try JSONDecoder().decode([Status].self, from: data).first?.status {
            case "approved": return .approved
            case "rejected": return .refused
            default: continue
            }
        }
        return .inReview
    }
}

extension Profile {
    /// The same profile with only the photos that may show (`PhotoModeration.isShown`), in order: the
    /// first approved one is the portrait.
    @MainActor func showingApprovedPhotos() -> Profile {
        let shown = allPhotos.filter { !$0.isEmpty && PhotoModeration.shared.isShown($0) }
        var profile = self
        profile.portrait = shown.first ?? ""
        profile.photos = Array(shown.dropFirst())
        return profile
    }
}
