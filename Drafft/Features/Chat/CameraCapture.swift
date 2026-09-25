import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// What the camera took: a photo, or a video file (in the app's temporary folder).
enum CameraCapture {
    case photo(UIImage)
    case video(URL)
}

/// The system camera, photo or video (the person switches in the camera itself), full screen.
/// Its own controls: shutter, retake, "Use Photo". Videos up to 3 minutes.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (CameraCapture) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoQuality = .typeHigh
        picker.videoMaximumDuration = 180
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                // The picker's file is deleted once it's dismissed: keep a copy.
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString).\(url.pathExtension)")
                if (try? FileManager.default.copyItem(at: url, to: copy)) != nil {
                    parent.onCapture(.video(copy))
                }
            } else if let image = info[.originalImage] as? UIImage {
                parent.onCapture(.photo(image))
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
