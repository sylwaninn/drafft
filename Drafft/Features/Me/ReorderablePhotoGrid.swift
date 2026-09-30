import SwiftUI

/// 3-column photo grid. Hold a photo, then drag it: the others slide out of the way live,
/// and the new order is committed on release.
struct ReorderablePhotoGrid<AddButton: View>: View {
    @Binding var photos: [String]
    let slots: Int
    @ViewBuilder let addButton: () -> AddButton
    let onRemove: (Int) -> Void
    /// Sign-up can empty the grid; a live profile always keeps one photo.
    var canRemoveLast = false

    @State private var dragging: String?
    @State private var dragOffset: CGSize = .zero
    @State private var order: [String] = []
    @State private var width: CGFloat = 0

    private let columns = 3
    private let spacing: CGFloat = DS.Space.sm

    var body: some View {
        GeometryReader { geo in
            let tileW = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let tileH = tileW * 4 / 3
            let shown = dragging == nil ? photos : order

            ZStack(alignment: .topLeading) {
                // Add buttons fill the free slots.
                ForEach(shown.count..<max(shown.count, slots), id: \.self) { i in
                    addButton()
                        .frame(width: tileW, height: tileH)
                        .offset(position(i, tileW, tileH))
                }
                ForEach(shown, id: \.self) { name in
                    let i = shown.firstIndex(of: name) ?? 0
                    let isDragged = dragging == name
                    tile(name, index: i)
                        .frame(width: tileW, height: tileH)
                        .scaleEffect(isDragged ? 1.08 : 1)
                        .shadow(color: .black.opacity(isDragged ? 0.25 : 0), radius: 14, y: 8)
                        .offset(isDragged ? dragAnchor(name, tileW, tileH) : position(i, tileW, tileH))
                        .zIndex(isDragged ? 1 : 0)
                        .gesture(reorderGesture(name, tileW, tileH))
                        .animation(isDragged ? nil : Motion.snappy, value: shown)
                }
            }
        }
        .frame(height: gridHeight)
        // Also one asked while no grid was on screen (from the banner or a push).
        .onChange(of: PhotoModeration.shared.removeRequest, initial: true) { _, path in
            guard let path, let i = photos.firstIndex(of: path) else { return }
            PhotoModeration.shared.removeRequest = nil
            onRemove(i)
        }
        .alert("Upload failed", isPresented: Binding(
            get: { PhotoModeration.shared.shownFailure.map(photos.contains) ?? false },
            set: { if !$0 { PhotoModeration.shared.shownFailure = nil } }
        )) {
            Button("Retry") {
                if let path = PhotoModeration.shared.shownFailure { PhotoModeration.shared.retry(path) }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(PhotoModeration.shared.shownFailure.map(PhotoModeration.shared.reason) ?? "")
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onAppear { order = photos }
    }

    /// Rows of 3:4 tiles for the measured width.
    private var gridHeight: CGFloat {
        let tileW = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        let rows = Int(ceil(Double(slots) / Double(columns)))
        return CGFloat(rows) * tileW * 4 / 3 + CGFloat(rows - 1) * spacing
    }

    private func position(_ i: Int, _ w: CGFloat, _ h: CGFloat) -> CGSize {
        CGSize(width: CGFloat(i % columns) * (w + spacing), height: CGFloat(i / columns) * (h + spacing))
    }

    /// Where the dragged tile is drawn: its start slot plus the finger's travel.
    private func dragAnchor(_ name: String, _ w: CGFloat, _ h: CGFloat) -> CGSize {
        let start = photos.firstIndex(of: name) ?? 0
        let p = position(start, w, h)
        return CGSize(width: p.width + dragOffset.width, height: p.height + dragOffset.height)
    }

    private func reorderGesture(_ name: String, _ w: CGFloat, _ h: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    if dragging == nil {
                        order = photos
                        dragging = name
                        Haptics.thump()
                    }
                    dragOffset = drag?.translation ?? .zero
                    // Live reorder: find the slot under the tile's centre.
                    let start = position(photos.firstIndex(of: name) ?? 0, w, h)
                    let cx = start.width + dragOffset.width + w / 2
                    let cy = start.height + dragOffset.height + h / 2
                    let col = min(columns - 1, max(0, Int(cx / (w + spacing))))
                    let row = max(0, Int(cy / (h + spacing)))
                    let target = min(order.count - 1, row * columns + col)
                    if let from = order.firstIndex(of: name), from != target {
                        Haptics.select()
                        withAnimation(Motion.snappy) {
                            order.remove(at: from)
                            order.insert(name, at: target)
                        }
                    }
                default: break
                }
            }
            .onEnded { _ in
                guard dragging != nil else { return }
                withAnimation(Motion.snappy) {
                    photos = order
                    dragging = nil
                    dragOffset = .zero
                }
            }
    }

    private func tile(_ name: String, index: Int) -> some View {
        Photo(name: name)
            .clipShape(.rect(cornerRadius: DS.Radius.lg))
            // Dimmed while it's not live on the profile: being checked (with a small loader), refused
            // (red chip, a tap explains why) or in review. Accepted: nothing.
            .overlay {
                if let state = PhotoModeration.shared.state(of: name),
                   state.isWorking || state == .refused || state == .inReview {
                    Color.black.opacity(0.38)
                        .clipShape(.rect(cornerRadius: DS.Radius.lg))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let state = PhotoModeration.shared.state(of: name), dragging == nil {
                    switch state {
                    case .uploading, .checking:
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                            .padding(DS.Space.sm)
                            .accessibilityLabel("Checking this photo")
                    case .approved:
                        EmptyView()
                    case .refused:
                        ModerationBadge(state: state)
                            .padding(DS.Space.xs)
                            .allowsHitTesting(false)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    case .inReview:
                        ModerationBadge(state: state)
                            .padding(DS.Space.xs)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    case .failed:
                        // Tap for the reason, and to try again.
                        Button { PhotoModeration.shared.shownFailure = name } label: {
                            ModerationBadge(state: state).frame(minHeight: 44).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, DS.Space.xs)
                        .accessibilityHint("Shows why, and lets you try again")
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
            }
            .onTapGesture {
                if PhotoModeration.shared.state(of: name) == .refused {
                    PhotoRefusalPresenter.show(.init(path: name))
                }
            }
            .animation(Motion.snappy, value: PhotoModeration.shared.state(of: name))
            .overlay(alignment: .topTrailing) {
                if (photos.count > 1 || canRemoveLast) && dragging == nil {
                    Button {
                        Haptics.tap()
                        onRemove(index)
                    } label: {
                        Image("close")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(DS.Palette.ink)
                            .frame(width: 26, height: 26)
                            .background(DS.Palette.canvas, in: .circle)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("Remove photo \(index + 1)")
                }
            }
            .contentShape(.rect(cornerRadius: DS.Radius.lg))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Photo \(index + 1) of \(photos.count)")
            .accessibilityActions {
                if index > 0 {
                    Button("Move earlier") { move(index, to: index - 1) }
                }
                if index < photos.count - 1 {
                    Button("Move later") { move(index, to: index + 1) }
                }
            }
    }

    private func move(_ from: Int, to: Int) {
        var list = photos
        let item = list.remove(at: from)
        list.insert(item, at: to)
        withAnimation(Motion.snappy) { photos = list }
    }
}

/// Where a new photo stands with the server, when there's something to say: refused (red), in
/// review, or failed. A chip, in a block like every text.
private struct ModerationBadge: View {
    let state: PhotoModeration.State

    var body: some View {
        // On a narrow tile a long translation leaves the symbol alone (VoiceOver still reads it).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                Image(symbol).font(.caption2.weight(.heavy))
                Text(label).font(.caption2.weight(.bold)).fixedSize()
            }
            Image(symbol).font(.caption2.weight(.heavy))
                .accessibilityLabel(label)
        }
        .foregroundStyle(state == .refused ? .white : DS.Palette.ink)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(state == .refused ? AnyShapeStyle(DS.Palette.negative) : AnyShapeStyle(DS.Palette.canvas), in: .capsule)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch state {
        case .refused: "forbidden-circle"
        case .inReview: "hourglass"
        default: "danger-triangle"
        }
    }

    private var label: String {
        switch state {
        case .refused: L("Refused")
        case .inReview: L("In review")
        default: L("Failed, tap to see why")
        }
    }
}
