import Foundation
import Network
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

    /// Keyed by `slot`: a photo on the server keeps its state when its signed link changes.
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

    /// Photos read back from the server, by `slot`: their id, so they can be looked at again or
    /// removed. Not kept on the device: every read of the account gives them again.
    private var serverIDs: [String: String] = [:]
    /// The latest link of each photo read back from the server, by `slot`: what a banner shows.
    private var links: [String: String] = [:]
    /// Photos read back from the server on which it found no face, by `slot`.
    private var faceless: Set<String> = []
    /// Photos picked, then left without being saved: deleted from the server as soon as they're on it.
    private var discarded: Set<String> = []
    /// Picked photos on the server whose verdict couldn't be read (no connection): still being checked,
    /// never taken as approved, read again as soon as the connection is back (`recheck`).
    private var unresolved: Set<String> = []
    /// Photos whose upload started in this launch: another start is a retry.
    @ObservationIgnored private var attempted: Set<String> = []
    private let network = NWPathMonitor()

    private init() {
        // Back online: the verdicts missed meanwhile are read again.
        network.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in PhotoModeration.shared.recheck() }
        }
        network.start(queue: DispatchQueue(label: "photoModeration.network"))
    }

    /// What a photo is known by: a picked file by its path, a photo on the server by its object key
    /// (its signed link changes every few minutes, the photo doesn't).
    private func slot(_ path: String) -> String {
        guard path.hasPrefix("http"), let url = URL(string: path) else { return path }
        return MediaURL.key(of: url) ?? MediaURL.canonical(url).absoluteString
    }

    /// The server id of a photo, once registered.
    func id(for path: String) -> String? { mediaIDs[path] ?? serverIDs[slot(path)] }

    /// Where a photo stands, as the grid and the profile read it. Nil: nothing to say (a photo on the
    /// server moderation approved, or one never sent).
    func state(of path: String) -> State? { states[slot(path)] }

    /// Whether the server found no face on a photo read back from it (never checked: false).
    func isFaceless(_ path: String) -> Bool { faceless.contains(slot(path)) }

    /// Whether a photo may show as the profile, to the person themselves included: only once approved.
    /// A photo read back from the server with no state was approved (the others are tracked below).
    func isShown(_ path: String) -> Bool {
        guard let state = state(of: path) else { return !path.hasPrefix("/") }
        return state == .approved
    }

    /// The account's photos as the server has them: a refused one stays on the person's own grid
    /// (to ask for a second look or remove it) and one still pending shows as in review. Neither is
    /// ever on the profile.
    func track(_ photos: [ProfileSync.OwnPhoto]) {
        for photo in photos {
            let key = slot(photo.link)
            // Its id stays known once approved: a later refusal (the team, a second look) must still reach it.
            serverIDs[key] = photo.id
            links[key] = photo.link
            if photo.faceless { faceless.insert(key) } else { faceless.remove(key) }
            switch photo.status {
            case "approved": states[key] = nil
            case "rejected": states[key] = .refused
            default: states[key] = .inReview
            }
        }
    }

    /// A picked photo whose state this launch doesn't know (a sign-up resumed after the app was
    /// closed): its verdict read again, or the photo sent again if the server never got it.
    func ensureChecked(_ path: String) {
        guard path.hasPrefix("/"), states[slot(path)] == nil else { return }
        guard let id = mediaIDs[path] else { submit(path); return }
        states[slot(path)] = .checking
        Task { await follow(path, id: id) }
    }

    /// Reads again the verdict of every picked photo still waiting for one: back online, back in the
    /// app. One the server has settled meanwhile takes its word; the others keep waiting.
    func recheck() {
        let waiting = mediaIDs.filter { path, _ in
            unresolved.contains(path) || states[slot(path)] == .inReview
        }
        for (path, id) in waiting where states[slot(path)] != .refused && states[slot(path)] != .approved {
            unresolved.remove(path)
            states[slot(path)] = states[slot(path)] == .inReview ? .inReview : .checking
            Task { await follow(path, id: id) }
        }
    }

    /// Follows a registered photo's verdict. Only the server's word settles it: without a connection it
    /// stays being checked (never approved by default) until `recheck` reads it again.
    private func follow(_ path: String, id: String) async {
        do {
            switch try await verdict(for: id) {
            case .some(let verdict):
                // A live `media` event may have settled it already (apply): only a newer word counts.
                if states[slot(path)] == .checking || states[slot(path)] == .inReview { settle(path, verdict) }
            case .none:
                // Gone from the server: sent again.
                mediaIDs[path] = nil
                states[slot(path)] = nil
                submit(path)
            }
        } catch {
            Telemetry.unexpected(error, "photos", "verdict")
            unresolved.insert(path)
        }
    }

    /// Waits for a picked photo to be uploaded and registered (moderation may still be running).
    /// Nil if it failed.
    func waitForID(_ path: String) async -> String? {
        if states[slot(path)] == nil && mediaIDs[path] == nil { submit(path) }
        for _ in 0..<600 {
            if let id = mediaIDs[path] { return id }
            if case .failed = states[slot(path)] { return nil }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    /// Clears a failed attempt and sends the photo again.
    func retry(_ path: String) {
        states[slot(path)] = nil
        // Already on the server (only its verdict couldn't be read): read it again, never a second upload.
        if mediaIDs[path] != nil { ensureChecked(path) } else { submit(path) }
    }

    /// The failure reason for a photo, in plain words when we know the cause.
    func reason(_ path: String) -> String {
        guard case .failed(let message) = states[slot(path)] else { return "" }
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
        guard states[slot(path)] == nil else { return }
        states[slot(path)] = .uploading
        Telemetry.track(.photoUploadStarted(where: ScreenTracker.currentID, retry: attempted.contains(path)))
        attempted.insert(path)
        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try Data(contentsOf: URL(fileURLWithPath: path))
                }.value
                let tickets = EdgeFunctionTicketProvider(functionsURL: BackendConfig.functionsURL) {
                    try await Backend.shared.accessToken()
                }
                let uploaded = try await Telemetry.trace("media.upload", "profile photo") { span in
                    span.setData("bytes", .int(data.count))
                    return try await MediaUploads.photo(data, tickets: tickets)
                }
                // The session exists now: this device can receive the "refused" push.
                await NotificationService.shared.syncPushToken()
                states[slot(path)] = .checking
                // A draft: on the profile only once the person saves (save_profile_media).
                var args: [String: Any] = ["p_key": uploaded.key, "p_width": uploaded.width, "p_height": uploaded.height,
                                           "p_draft": true]
                if let hash = uploaded.thumbHash { args["p_thumbhash"] = hash }
                let row = try await Backend.shared.rpc("add_profile_media", args)
                struct Row: Decodable { let id: String }
                let id = try JSONDecoder().decode(Row.self, from: row).id
                // Left without saving while it was on its way: it goes at once.
                if discarded.remove(path) != nil {
                    states[slot(path)] = nil
                    Task { await Self.deleteOnServer(id) }
                    return
                }
                mediaIDs[path] = id
                await follow(path, id: id)
            } catch {
                Telemetry.track(.photoUploadFailed(Telemetry.reason(error)))
                Telemetry.unexpected(error, "photos", "upload")
                states[slot(path)] = .failed(Self.failure(error))
            }
        }
    }

    /// Deletes a photo the person took off (refused, or a draft never saved). The screen already let it go,
    /// so a failure isn't put back on it: tried again a few times (offline, a server hiccup) so it doesn't
    /// come back with the next read. A refusal with a code is the server's answer, never tried again:
    /// already gone (`not_found`) is done, and one it won't delete (`portrait_required`) stays refused.
    /// Drafts missed here are deleted by the server after a few days.
    static func deleteOnServer(_ id: String) async {
        for attempt in 0..<4 {
            do {
                _ = try await Backend.shared.rpc("delete_media", ["p_id": id])
                return
            } catch {
                if ServerMessage.code(of: error) != nil || error is CancellationError { return }
                if case Backend.BackendError.signedOut = error { return }
                if attempt < 3 { try? await Task.sleep(for: .seconds(2 << attempt)) }
            }
        }
    }

    /// Asks a person to look at a refused photo again. It stays off the profile meanwhile.
    func requestReview(_ path: String) async throws {
        // Not uploaded (yet): nothing the team could look at, so never say it was sent.
        guard let id = id(for: path) else { throw Backend.BackendError.http(404, "not_found") }
        _ = try await Backend.shared.rpc("request_media_review", ["p_media": id])
        Telemetry.track(.photoReviewRequested)
        states[slot(path)] = .inReview
    }

    /// Takes a refused photo off the profile: from the grid, and from the server. Its state stays
    /// refused while a screen still holds it (a photo that's gone never passes for an approved one).
    func remove(_ path: String) {
        Telemetry.track(.photoRemoved)
        removeRequest = path
        if let id = id(for: path) {
            Task { await Self.deleteOnServer(id) }
        }
        mediaIDs[path] = nil
        serverIDs[slot(path)] = nil
    }

    /// Photos picked but not saved (the person left, or took them off the grid): drafts, never on the
    /// profile, deleted from the server now, or as soon as their upload registers them. The server
    /// deletes the ones this misses after a few days.
    func discard(_ paths: [String]) {
        for path in paths where path.hasPrefix("/") {
            if let id = mediaIDs[path] {
                Task { await Self.deleteOnServer(id) }
                mediaIDs[path] = nil
                states[slot(path)] = nil
            } else if states[slot(path)]?.isWorking == true {
                discarded.insert(path)
            } else {
                states[slot(path)] = nil
            }
        }
    }

    /// A `media` event from the person's Realtime topic (UserChannel): the automatic
    /// check or the team decided on one of their photos. The tile follows at once; a refusal gets
    /// its banner, with the second look offered by its explanation. A photo this device doesn't
    /// know (added from another phone) is left alone.
    func apply(mediaID: String, status: String) {
        // The same photo can be known by its local path and by its server link: both follow.
        for path in paths(of: mediaID) {
            switch status {
            case "approved": settle(path, .approved)
            case "rejected": settle(path, .refused, announce: path == paths(of: mediaID).first)
            // Back to pending: a second look was asked (here or on another device).
            case "pending" where states[slot(path)] == .refused: settle(path, .inReview)
            default: break
            }
        }
    }

    /// Every path a server id is known by: picked on this device, and read back from the server.
    private func paths(of mediaID: String) -> [String] {
        mediaIDs.filter { $0.value == mediaID }.map(\.key)
            + serverIDs.filter { $0.value == mediaID }.compactMap { links[$0.key] }
    }

    /// Sets a photo's verdict; announces a refusal once, when it becomes one.
    private func settle(_ path: String, _ state: State, announce: Bool = true) {
        let was = states[slot(path)]
        states[slot(path)] = state
        if was != state {
            switch state {
            case .approved: Telemetry.track(.photoModerated("approved"))
            case .refused: Telemetry.track(.photoModerated("refused"))
            case .inReview: Telemetry.track(.photoModerated("in_review"))
            default: break
            }
        }
        if state == .refused && was != .refused && announce { announceRefusal(path) }
    }

    /// From the push: shows the explanation for that photo, once the app is on screen (a tap on a
    /// push can launch it: its window takes a moment to exist). False when the photo isn't known
    /// (nothing is shown).
    @discardableResult
    func openRefusal(mediaID: String) -> Bool {
        let paths = paths(of: mediaID)
        guard let path = paths.first else { return false }
        paths.forEach { states[slot($0)] = .refused }
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
        return true
    }

    /// Open app: a banner. Closed or in the background: the server's push says it.
    private func announceRefusal(_ path: String) {
        guard UIApplication.shared.applicationState == .active else { return }
        Haptics.warning()
        refusalBanner = Refusal(path: path)
    }

    /// Polls the status (every second, up to 30 s). Still pending after that: a person decides, and
    /// their decision arrives as a `media` event (apply) or on the next `recheck`. Nil: the photo is no
    /// longer on the server. Throws when the server can't be reached: nothing is decided then.
    private func verdict(for id: String) async throws -> State? {
        struct Status: Decodable { let status: String }
        for attempt in 0..<30 {
            if attempt > 0 { try await Task.sleep(for: .seconds(1)) }
            let data = try await Backend.shared.select("profile_media?id=eq.\(id)&select=status")
            let rows = try JSONDecoder().decode([Status].self, from: data)
            guard let status = rows.first?.status else { return nil }
            switch status {
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
