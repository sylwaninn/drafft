import SwiftUI

/// Where a profile's photos stand, the same at sign-up and in Edit profile. They go on (continue, save)
/// only once moderation has judged every photo and the first one is approved with a face (checked here,
/// then again on the server, which also refuses to delete the last one): a photo being checked, refused
/// or waiting for a person never opens or keeps a profile. Refused or waiting photos after the first may
/// stay (a second look can be asked from their tile): the server never shows them.
enum PhotoSetCheck: Equatable {
    case empty, checking, ready, firstRefused, firstInReview, noFace, tooSmall, failed

    /// `face`: the face check of the first photo (`face(of:)`), nil while it runs.
    @MainActor
    static func of(_ photos: [String], face: FaceCheck.Result?) -> PhotoSetCheck {
        guard let first = photos.first, !first.isEmpty else { return .empty }
        // A photo read back from the server with no state was approved (`PhotoModeration.isShown`).
        let states = photos.map { PhotoModeration.shared.state(of: $0) ?? ($0.hasPrefix("/") ? nil : .approved) }
        if states[0] == .refused { return .firstRefused }
        if face == .noFace { return .noFace }
        if face == .tooSmall { return .tooSmall }
        if states.contains(where: { if case .failed = $0 { true } else { false } }) { return .failed }
        if face == nil || states.contains(where: { $0?.isJudged != true }) { return .checking }
        if states[0] == .inReview { return .firstInReview }
        return .ready
    }

    /// The face on a profile's first photo. A photo already on the server was checked there, with its
    /// verdict (the server picks the portrait by it): its word is taken. Picked photos are checked here.
    @MainActor
    static func face(of path: String?) async -> FaceCheck.Result? {
        guard let path, !path.isEmpty else { return nil }
        guard path.hasPrefix("/") else { return PhotoModeration.shared.isFaceless(path) ? .noFace : .face }
        return await FaceCheck.check(photo: path)
    }

    /// Something the person has to change (not just wait for).
    var needsAction: Bool {
        switch self {
        case .firstRefused, .noFace, .tooSmall, .failed: true
        case .empty, .checking, .ready, .firstInReview: false
        }
    }

    /// One line for the validate button's footer; nil once ready.
    var reason: String? {
        switch self {
        case .empty: L("Add at least one photo.")
        // Only the photo being checked says so (its tile's loader): no line.
        case .checking, .ready: nil
        case .firstInReview: L("Our team is checking your first photo. Put another one first, or wait.")
        case .firstRefused, .noFace, .tooSmall: L("Put a clear photo of your face first.")
        case .failed: L("A photo couldn't be sent. Tap it to see why, then try again.")
        }
    }
}

/// Under the photo grid: what the first photo still needs, or that the photos are being checked.
struct PhotoSetHint: View {
    let check: PhotoSetCheck

    var body: some View {
        switch check {
        case .empty:
            line(L("Your first photo needs to show your face clearly."))
        case .checking, .ready:
            // All good, or a photo still being checked: its tile's loader says it, nothing more here.
            EmptyView()
        case .firstRefused:
            line(L("Your first photo wasn't approved. Put another one first."), error: true)
        case .firstInReview:
            line(L("Our team is checking your first photo. Put another one first, or wait."))
        case .noFace:
            line(L("We can't see a face on your first photo. Put a clear photo of you first."), error: true)
        case .tooSmall:
            line(L("Your face is too small on your first photo. Use a closer one first."), error: true)
        case .failed:
            line(L("A photo couldn't be sent. Tap it to see why, then try again."), error: true)
        }
    }

    @ViewBuilder
    private func line(_ text: String, error: Bool = false) -> some View {
        if error {
            Label { Text(branded: text, font: .footnote.weight(.medium)) } icon: {
                Image("danger-circle")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(DS.Palette.negative)
        } else {
            // Body grey: mute is under 4.5:1 on the sage page.
            Text(branded: text, font: .footnote).foregroundStyle(DS.Palette.body)
        }
    }
}

extension View {
    /// Leaving a page with changes not saved asks first (photos just added would be lost). `discard`
    /// puts everything back as it was at the last save (new photo drafts deleted), then leaves.
    func unsavedBackGuard(_ active: Bool, photos: Bool, isPresented: Binding<Bool>,
                          discard: @escaping () -> Void) -> some View {
        navigationBarBackButtonHidden(active)
            .toolbar {
                if active {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back", image: .icon("alt-arrow-left")) { isPresented.wrappedValue = true }
                    }
                }
            }
            .drafftConfirm(isPresented: isPresented, icon: "trash-bin-minimalistic",
                           title: photos ? L("Discard your photo changes?") : L("Discard your changes?"),
                           message: photos ? L("Photos you added will be deleted, and the others go back as they were.")
                               : L("What you changed since your last save will be lost."),
                           cancelTitle: L("Keep editing"),
                           actions: [ConfirmAction(title: L("Discard changes"), kind: .destructive, action: discard)])
    }
}

/// On the Photos row: how many photos moderation refused (tap the row, then a photo, to see why).
struct RefusedCountChip: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image("forbidden-circle").font(.caption2.weight(.heavy))
            Text(count == 1 ? L("1 refused") : L("\(count) refused"))
                .font(.caption.weight(.bold))
                .fixedSize()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(DS.Palette.negative, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}
