import SwiftUI
import UIKit
import AVKit
import QuickLook

/// A photo, video or file from a chat, opened full screen.
struct MediaItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case photo(asset: String?, data: Data?)
        case video(URL)
        case file(URL)
    }

    /// The message it belongs to.
    let id: UUID
    let kind: Kind

    /// The picture itself, for photos (asset or sent data).
    var image: UIImage? {
        guard case let .photo(asset, data) = kind else { return nil }
        if let asset { return UIImage(named: asset) }
        return data.flatMap(UIImage.init(data:))
    }

    /// Every photo and video of a conversation, in order: what the viewer swipes through.
    static func gallery(of convo: Conversation) -> [MediaItem] {
        convo.messages.compactMap { m in
            switch m.content {
            case let .photo(asset, data): return MediaItem(id: m.id, kind: .photo(asset: asset, data: data))
            case let .video(url, _, _): return MediaItem(id: m.id, kind: .video(url))
            default: return nil
            }
        }
    }
}

/// Full-screen viewer: swipe between the chat's photos and videos, pinch or double-tap to zoom
/// (and pan while zoomed), swipe down to close when not zoomed, share. Videos use the system player.
/// Files open alone in Quick Look.
struct MediaViewer: View {
    let items: [MediaItem]
    @State private var current: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var zoomed = false
    @State private var drag: CGFloat = 0
    @State private var chromeHidden = false

    init(items: [MediaItem], start: MediaItem) {
        self.items = items.contains(where: { $0.id == start.id }) ? items : [start]
        _current = State(initialValue: start.id)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - min(0.7, abs(drag) / 350))
                .ignoresSafeArea()

            if case .file(let url) = items.first?.kind, items.count == 1 {
                QuickLookPreview(url: url).ignoresSafeArea()
            } else {
                TabView(selection: $current) {
                    ForEach(items) { item in
                        page(item)
                            .tag(item.id)
                            .ignoresSafeArea()
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
                .offset(y: drag)
                .scaleEffect(1 - min(0.12, abs(drag) / 2500))
                // Vertical swipe to close; horizontal swipes page, and it's off while zoomed.
                .simultaneousGesture(closeDrag, isEnabled: !zoomed)
            }
        }
        .overlay(alignment: .top) { if !chromeHidden { topBar } }
        .animation(Motion.snappy, value: chromeHidden)
        .statusBarHidden()
        .onChange(of: current) { _, _ in zoomed = false }
    }

    @ViewBuilder
    private func page(_ item: MediaItem) -> some View {
        switch item.kind {
        case .photo:
            if let image = item.image {
                ZoomableImage(image: image, zoomed: $zoomed) {
                    chromeHidden.toggle()
                }
                .accessibilityLabel("Photo")
            } else {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.white.opacity(0.5))
            }
        case .video(let url):
            SystemVideoPlayer(url: url, playing: current == item.id)
        case .file(let url):
            QuickLookPreview(url: url)
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .accessibilityLabel("Close")
            Spacer()
            if items.count > 1, let index = items.firstIndex(where: { $0.id == current }) {
                Text("\(index + 1) of \(items.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.md)
                    .frame(height: 32)
                    .glassEffect(.regular, in: .capsule)
            }
            Spacer()
            if let shareable {
                ShareLink(item: shareable, preview: SharePreview("Photo", image: shareable)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .accessibilityLabel("Share")
            } else if case .video(let url) = items.first(where: { $0.id == current })?.kind {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .accessibilityLabel("Share")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.top, DS.Space.sm)
        .transition(.opacity)
    }

    private var shareable: Image? {
        items.first(where: { $0.id == current })?.image.map { Image(uiImage: $0) }
    }

    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { v in
                // Only a clearly vertical drag: horizontal ones belong to paging.
                guard drag != 0 || abs(v.translation.height) > abs(v.translation.width) * 1.4 else { return }
                drag = v.translation.height
            }
            .onEnded { v in
                if abs(drag) > 120 || abs(v.predictedEndTranslation.height) > 400 {
                    dismiss()
                } else {
                    withAnimation(Motion.snappy) { drag = 0 }
                }
            }
    }
}

// MARK: - Zoomable photo

/// UIScrollView zoom, like Photos: pinch, pan while zoomed, bounce, double tap zooms on the tapped
/// point (and back). A single tap shows or hides the viewer's controls.
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    @Binding var zoomed: Bool
    var onSingleTap: () -> Void

    func makeUIView(context: Context) -> ZoomScrollView {
        let view = ZoomScrollView(image: image)
        view.onZoomChange = { zoomed = $0 }
        view.onSingleTap = onSingleTap
        return view
    }

    func updateUIView(_ view: ZoomScrollView, context: Context) {
        view.onZoomChange = { zoomed = $0 }
        view.onSingleTap = onSingleTap
        if !zoomed, view.zoomScale != view.minimumZoomScale { view.setZoomScale(view.minimumZoomScale, animated: true) }
    }
}

final class ZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView: UIImageView
    var onZoomChange: (Bool) -> Void = { _ in }
    var onSingleTap: () -> Void = {}

    init(image: UIImage) {
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        delegate = self
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        minimumZoomScale = 1
        maximumZoomScale = 4
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        backgroundColor = .clear

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard zoomScale == minimumZoomScale, bounds.width > 0 else { return }
        // The whole photo fits the screen at scale 1, in its own proportions.
        let size = imageView.image?.size ?? bounds.size
        let fit = min(bounds.width / size.width, bounds.height / size.height)
        imageView.frame = CGRect(x: 0, y: 0, width: size.width * fit, height: size.height * fit)
        contentSize = imageView.frame.size
        center()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        center()
        onZoomChange(zoomScale > minimumZoomScale + 0.01)
    }

    /// Keeps the photo centred when it's smaller than the screen on an axis.
    private func center() {
        let x = max(0, (bounds.width - contentSize.width) / 2)
        let y = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    @objc private func doubleTapped(_ tap: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = tap.location(in: imageView)
            let scale: CGFloat = 2.5
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: true)
        }
    }

    @objc private func singleTapped() { onSingleTap() }
}

// MARK: - Video

/// The system player (controls, scrubbing, AirPlay, picture in picture), paused when its page
/// isn't the one on screen.
private struct SystemVideoPlayer: UIViewControllerRepresentable {
    let url: URL
    let playing: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: url)
        controller.allowsPictureInPicturePlayback = true
        controller.view.backgroundColor = .clear
        if playing { controller.player?.play() }
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if playing { controller.player?.play() } else { controller.player?.pause() }
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        controller.player?.pause()
    }
}

// MARK: - Files

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
