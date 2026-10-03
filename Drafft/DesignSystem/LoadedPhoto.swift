import Nuke
import NukeUI
import SwiftUI

/// A photo on the server (`http…`) or picked on this phone (`/…`), through `Images`: the copy the frame
/// needs, decoded in the background at the frame's size, shared downloads, capped caches. A copy already
/// in memory shows on the first frame; otherwise its ThumbHash preview (`MediaPreviews`), or a sage tile,
/// stands in until it's there. On a slow connection a large frame first shows a small copy
/// (`Images.preview`), sharp enough to read the photo, while the right one arrives. An open profile's photo
/// (`detail`) wider than the copy already on this phone shows that copy at once (`Images.standIn`, the deck
/// card's, typically) while the wider one arrives, instead of a loader.
struct LoadedPhoto: View {
    let name: String
    /// Blur radius as a share of the photo's shorter side (0: sharp).
    var blur: CGFloat = 0
    var priority: ImageRequest.Priority = .normal
    var detail = false
    @Environment(\.displayScale) private var scale
    /// The running load: its priority follows the card's place without restarting it (a changed request
    /// would cancel the download and start over).
    @State private var task: ImageTask?
    /// The stand-in, once drawn: kept (the same request, so it isn't loaded again) under the sharp copy until
    /// that one has faded in, then let go: the view holds one copy, and the memory cache may evict the other.
    @State private var keptStandIn: ImageRequest?
    /// The sharp copy is drawn: a stand-in finishing after it is never kept.
    @State private var sharp = false
    /// Decoded once per view (a few microseconds, then cached by key).
    private var preview: UIImage? { MediaPreviews.image(for: name) }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let large = blur == 0 && min(size.width, size.height) >= 200
            LazyImage(request: Images.request(name, points: size, scale: scale, blur: blur, detail: detail),
                      transaction: Transaction(animation: .easeOut(duration: 0.2))) { state in
                // Layers stack, never swap: each sharper one fades in over the last, which stays underneath,
                // so a change of quality is a fade and never a flash of the empty tile.
                ZStack {
                    Rectangle().fill(DS.Palette.canvasSoft)
                    if let preview {
                        fill(Image(uiImage: preview).interpolation(.medium), size)
                    }
                    if large, let stand = standIn(size, sharp: state.image != nil) {
                        LazyImage(request: stand, transaction: Transaction(animation: .easeOut(duration: 0.2))) { copy in
                            if let image = copy.image {
                                fill(image, size).transition(.opacity)
                            }
                        }
                        .onCompletion { result in
                            if case .success = result, !sharp { keptStandIn = stand }
                        }
                        .frame(width: size.width, height: size.height)
                    } else if large, let small = smallCopy(size, sharp: state.image != nil) {
                        LazyImage(request: small, transaction: Transaction(animation: .easeOut(duration: 0.2))) { copy in
                            if let image = copy.image {
                                fill(image, size).transition(.opacity)
                            } else if state.image == nil {
                                PhotoLoader()
                            }
                        }
                        #if DECK_PHOTO_METRICS
                        .onCompletion { DeckPhotoMetrics.preview(name, $0) }
                        #endif
                        .frame(width: size.width, height: size.height)
                    } else if large, state.image == nil {
                        PhotoLoader()
                    }
                    if let image = state.image {
                        fill(image, size).transition(.opacity)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()
            }
            .onStart { started in
                started.priority = priority
                task = started
            }
            .onCompletion { result in
                #if DECK_PHOTO_METRICS
                DeckPhotoMetrics.finished(name, result)
                #endif
                guard case .success = result else { return }
                sharp = true
                guard keptStandIn != nil else { return }
                // Past the sharp copy's 0.2 s fade, the stand-in under it goes.
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    keptStandIn = nil
                }
            }
            #if DECK_PHOTO_METRICS
            .onAppear { DeckPhotoMetrics.appeared(name) }
            #endif
            .frame(width: size.width, height: size.height)
        }
        .onChange(of: priority) { _, now in task?.priority = now }
    }

    /// Every layer (blurred preview, small copy, sharp copy) fills exactly the same frame, centred, so
    /// the photo never shifts as a sharper one replaces it.
    private func fill(_ image: Image, _ size: CGSize) -> some View {
        image.resizable().scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    /// An open profile's stand-in: the one already drawn, or, while the sharp copy is missing, a smaller copy
    /// already on this phone.
    private func standIn(_ size: CGSize, sharp drawn: Bool) -> ImageRequest? {
        guard detail else { return nil }
        if let keptStandIn { return keptStandIn }
        return drawn ? nil : Images.standIn(name, points: size, scale: scale)
    }

    /// The small copy: on a limited connection while the sharp one is missing, or whenever it's already in
    /// memory (fetched ahead by the deck's window, or shown before the sharp one arrived, which then fades
    /// in over it).
    private func smallCopy(_ size: CGSize, sharp: Bool) -> ImageRequest? {
        guard let request = Images.preview(name, points: size, scale: scale) else { return nil }
        if ImagePipeline.shared.cache.containsCachedImage(for: request, caches: [.memory]) { return request }
        return !sharp && NetworkQuality.shared.isLimited ? request : nil
    }
}

/// A spinner over a large photo still showing only its blurred preview (never over the small copy: that
/// one is readable). It appears after a moment, so a photo that arrives quickly never flashes it.
private struct PhotoLoader: View {
    @State private var shown = false

    var body: some View {
        ProgressView()
            .tint(.white)
            .shadow(color: .black.opacity(0.35), radius: 6)
            .opacity(shown ? 1 : 0)
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.easeOut(duration: 0.2)) { shown = true }
            }
            .accessibilityHidden(true)
    }
}
