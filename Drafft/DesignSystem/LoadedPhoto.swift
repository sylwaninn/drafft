import Nuke
import NukeUI
import SwiftUI

/// A photo on the server (`http…`) or picked on this phone (`/…`), through `Images`: the copy the frame
/// needs, decoded in the background at the frame's size, shared downloads, capped caches. A copy already
/// in memory shows on the first frame; otherwise its ThumbHash preview (`MediaPreviews`), or a sage tile,
/// stands in until it's there. On a slow connection a large frame first shows a small copy
/// (`Images.preview`), sharp enough to read the photo, while the right one arrives.
struct LoadedPhoto: View {
    let name: String
    /// Blur radius as a share of the photo's shorter side (0: sharp).
    var blur: CGFloat = 0
    var priority: ImageRequest.Priority = .normal
    @Environment(\.displayScale) private var scale
    /// Decoded once per view (a few microseconds, then cached by key).
    private var preview: UIImage? { MediaPreviews.image(for: name) }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let large = blur == 0 && min(size.width, size.height) >= 200
            LazyImage(request: Images.request(name, points: size, scale: scale, blur: blur),
                      transaction: Transaction(animation: .easeOut(duration: 0.2))) { state in
                // Layers stack, never swap: each sharper one fades in over the last, which stays underneath,
                // so a change of quality is a fade and never a flash of the empty tile.
                ZStack {
                    Rectangle().fill(DS.Palette.canvasSoft)
                    if let preview {
                        fill(Image(uiImage: preview).interpolation(.medium), size)
                    }
                    if large, let small = smallCopy(size, sharp: state.image != nil) {
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
            .priority(priority)
            #if DECK_PHOTO_METRICS
            .onCompletion { DeckPhotoMetrics.finished(name, $0) }
            .onAppear { DeckPhotoMetrics.appeared(name) }
            #endif
            .frame(width: size.width, height: size.height)
        }
    }

    /// Every layer (blurred preview, small copy, sharp copy) fills exactly the same frame, centred, so
    /// the photo never shifts as a sharper one replaces it.
    private func fill(_ image: Image, _ size: CGSize) -> some View {
        image.resizable().scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    /// The small copy: on a limited connection while the sharp one is missing, or whenever it's already in
    /// memory (fetched ahead by the deck's window, or shown before the sharp one arrived, which then fades
    /// in over it).
    private func smallCopy(_ size: CGSize, sharp: Bool) -> ImageRequest? {
        guard let request = Images.preview(name, points: size, scale: scale) else { return nil }
        if ImagePipeline.shared.cache.containsCachedImage(for: request) { return request }
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
