import Foundation

/// Mirrors `purposes` in the backend's media-upload-url function (types and size limits live there).
enum MediaPurpose: String, Sendable {
    case profilePhoto = "profile_photo"
    case profileVideo = "profile_video"
    case videoPoster = "video_poster"
    case voiceIntro = "voice_intro"
    case chatPhoto = "chat_photo"
    case chatVideo = "chat_video"
    case chatVoice = "chat_voice"
    case chatFile = "chat_file"
}

/// A presigned PUT to the media bucket, valid for `expiresIn` seconds.
struct UploadTicket: Decodable, Sendable {
    let key: String
    let uploadUrl: URL
    let headers: [String: String]
    let publicUrl: URL
    let expiresIn: Int
}

protocol UploadTicketProviding: Sendable {
    func ticket(for purpose: MediaPurpose, contentType: String, byteSize: Int) async throws -> UploadTicket
}

enum MediaUploadError: Error, Equatable {
    case rejected(code: String)
    case ticketExpired
    case http(Int)
}

/// Asks the media-upload-url Edge Function for a ticket.
struct EdgeFunctionTicketProvider: UploadTicketProviding {
    /// https://<project>.supabase.co/functions/v1
    let functionsURL: URL
    /// The signed-in user's current access token.
    let accessToken: @Sendable () async throws -> String

    func ticket(for purpose: MediaPurpose, contentType: String, byteSize: Int) async throws -> UploadTicket {
        var request = URLRequest(url: functionsURL.appendingPathComponent("media-upload-url"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable { let purpose: String, contentType: String, byteSize: Int }
        request.httpBody = try JSONEncoder().encode(Body(purpose: purpose.rawValue, contentType: contentType, byteSize: byteSize))
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            struct Failure: Decodable { let code: String }
            if let failure = try? JSONDecoder().decode(Failure.self, from: data) {
                // An account on hold can't upload to chats: the hold screen takes over and says why.
                if status == 403, failure.code == "moderated" {
                    await MainActor.run { NotificationCenter.default.post(name: .accountHeldByServer, object: nil) }
                }
                throw MediaUploadError.rejected(code: failure.code)
            }
            throw MediaUploadError.http(status)
        }
        return try JSONDecoder().decode(UploadTicket.self, from: data)
    }
}

/// Uploads files straight to the media bucket in a background URLSession: an upload keeps going when
/// the app is backgrounded or the screen locks, and the system retries on network changes.
final class MediaUploader: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = MediaUploader()
    static let sessionIdentifier = "so.drafft.app.uploads"

    private let lock = NSLock()
    private var waiting: [Int: CheckedContinuation<Void, Error>] = [:]
    private var progressHandlers: [Int: @Sendable (Double) -> Void] = [:]
    /// Set by the app delegate when iOS relaunches the app to deliver background upload events.
    private var backgroundCompletion: (@Sendable () -> Void)?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        // The person is waiting on this upload: start now, don't wait for Wi-Fi or charging.
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    /// PUTs a file to a ticket's URL, retrying transient failures twice (after 1 s, then 2 s).
    /// A 403 means the ticket expired: ask for a new one and call again.
    func upload(_ file: URL, with ticket: UploadTicket, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        var attempt = 0
        while true {
            do {
                try await put(file, ticket: ticket, progress: progress)
                return
            } catch let error as MediaUploadError where error == .ticketExpired {
                throw error
            } catch {
                attempt += 1
                guard attempt < 3 else { throw error }
                try await Task.sleep(for: .seconds(Double(1 << (attempt - 1))))
            }
        }
    }

    func handleEventsForBackgroundSession(completion: @escaping @Sendable () -> Void) {
        lock.withLock { backgroundCompletion = completion }
        _ = session
    }

    private func put(_ file: URL, ticket: UploadTicket, progress: (@Sendable (Double) -> Void)?) async throws {
        var request = URLRequest(url: ticket.uploadUrl)
        request.httpMethod = "PUT"
        // Content-Length comes from the file itself (URLSession ignores a manual one); it matches the
        // signed byteSize because the ticket was requested for this exact file.
        for (name, value) in ticket.headers where name.lowercased() != "content-length" {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let task = session.uploadTask(with: request, fromFile: file)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock {
                    waiting[task.taskIdentifier] = continuation
                    progressHandlers[task.taskIdentifier] = progress
                }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: URLSessionTaskDelegate

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0,
              let handler = lock.withLock({ progressHandlers[task.taskIdentifier] }) else { return }
        handler(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let continuation = lock.withLock {
            progressHandlers[task.taskIdentifier] = nil
            return waiting.removeValue(forKey: task.taskIdentifier)
        }
        // No continuation: an upload from a previous launch, finished in the background.
        guard let continuation else { return }
        if let error {
            continuation.resume(throwing: error)
            return
        }
        switch (task.response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: continuation.resume()
        case 403: continuation.resume(throwing: MediaUploadError.ticketExpired)
        case let status: continuation.resume(throwing: MediaUploadError.http(status))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = lock.withLock { () -> (@Sendable () -> Void)? in
            defer { backgroundCompletion = nil }
            return backgroundCompletion
        }
        DispatchQueue.main.async { completion?() }
    }
}

// MARK: - Prepare, then upload

/// What the backend needs to register an uploaded profile photo or video (add_profile_media).
struct UploadedMedia: Sendable {
    let key: String
    let width: Int
    let height: Int
    let thumbHash: String?
    /// Videos only.
    var duration: Double?
    var posterKey: String?
}

enum MediaUploads {
    /// Compress, then upload. Ticket expiry (10 min) is handled by asking for a fresh one once.
    static func photo(
        _ data: Data,
        purpose: MediaPurpose = .profilePhoto,
        tickets: UploadTicketProviding,
        uploader: MediaUploader = .shared,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> UploadedMedia {
        let photo = try await PhotoCompressor.prepare(data)
        let file = try temporaryFile(photo.data, extension: "jpg")
        defer { try? FileManager.default.removeItem(at: file) }
        let key = try await send(file, byteSize: photo.data.count, contentType: photo.contentType, purpose: purpose,
                                 tickets: tickets, uploader: uploader, progress: progress)
        return UploadedMedia(key: key, width: photo.width, height: photo.height, thumbHash: photo.thumbHash)
    }

    /// Transcodes, uploads the poster, then the video. Progress covers the video bytes. A chat video's
    /// poster goes to the chat folder (`posterPurpose: .chatPhoto`): only chat objects are signed for the
    /// other member of the match.
    static func video(
        _ source: URL,
        purpose: MediaPurpose = .profileVideo,
        settings: VideoCompressor.Settings = .profile,
        posterPurpose: MediaPurpose = .videoPoster,
        tickets: UploadTicketProviding,
        uploader: MediaUploader = .shared,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> UploadedMedia {
        let video = try await VideoCompressor.prepare(source, settings: settings)
        defer { try? FileManager.default.removeItem(at: video.fileURL) }

        let posterFile = try temporaryFile(video.poster.data, extension: "jpg")
        defer { try? FileManager.default.removeItem(at: posterFile) }
        let posterKey = try await send(posterFile, byteSize: video.poster.data.count, contentType: video.poster.contentType,
                                       purpose: posterPurpose, tickets: tickets, uploader: uploader, progress: nil)
        let key = try await send(video.fileURL, byteSize: video.byteSize, contentType: video.contentType, purpose: purpose,
                                 tickets: tickets, uploader: uploader, progress: progress)
        return UploadedMedia(key: key, width: video.width, height: video.height, thumbHash: video.poster.thumbHash,
                             duration: video.duration, posterKey: posterKey)
    }

    /// A recording (.m4a, AAC 48 kb/s mono), as is: it's already small. A voice intro, or a voice message
    /// (`purpose: .chatVoice`).
    static func voice(_ file: URL, purpose: MediaPurpose = .voiceIntro, tickets: UploadTicketProviding,
                      uploader: MediaUploader = .shared) async throws -> String {
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        return try await send(file, byteSize: size, contentType: "audio/mp4", purpose: purpose,
                              tickets: tickets, uploader: uploader, progress: nil)
    }

    private static func send(
        _ file: URL, byteSize: Int, contentType: String, purpose: MediaPurpose,
        tickets: UploadTicketProviding, uploader: MediaUploader, progress: (@Sendable (Double) -> Void)?
    ) async throws -> String {
        var ticket = try await tickets.ticket(for: purpose, contentType: contentType, byteSize: byteSize)
        do {
            try await uploader.upload(file, with: ticket, progress: progress)
        } catch MediaUploadError.ticketExpired {
            ticket = try await tickets.ticket(for: purpose, contentType: contentType, byteSize: byteSize)
            try await uploader.upload(file, with: ticket, progress: progress)
        }
        return ticket.key
    }

    private static func temporaryFile(_ data: Data, extension ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("upload-\(UUID().uuidString).\(ext)")
        try data.write(to: url)
        return url
    }
}
