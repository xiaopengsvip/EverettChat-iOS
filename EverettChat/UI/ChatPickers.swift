import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AVFoundation

/// 文件选择器（UIDocumentPicker 封装）
struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL, String, Data) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let fileName = url.lastPathComponent
            guard let data = try? Data(contentsOf: url) else { return }
            parent.onPick(url, fileName, data)
        }
    }
}

/// 相机拍摄：拍照 / 录像（系统中文界面自动适配系统语言）
struct CameraPicker: UIViewControllerRepresentable {
    var mode: CameraMode = .photo
    var onCapture: (UIImage) -> Void
    var onVideo: ((URL) -> Void)?
    @Environment(\.dismiss) private var dismiss

    enum CameraMode {
        case photo
        case video
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        if mode == .video {
            picker.mediaTypes = [UTType.movie.identifier]
            picker.videoQuality = .typeMedium
            picker.cameraCaptureMode = .video
        } else {
            picker.mediaTypes = [UTType.image.identifier]
            picker.cameraCaptureMode = .photo
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if parent.mode == .video {
                if let videoURL = info[.mediaURL] as? URL {
                    parent.onVideo?(videoURL)
                }
            } else {
                if let image = info[.originalImage] as? UIImage {
                    parent.onCapture(image)
                }
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
