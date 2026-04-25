//
//  PhotoLibraryPicker.swift
//  Chiron
//
//  PHPickerViewController bridge for choosing a profile photo from the library.
//  Using PHPicker (over UIImagePickerController) means we don't need
//  NSPhotoLibraryUsageDescription — the picker runs out-of-process and only
//  hands us the chosen image.
//

import SwiftUI
import PhotosUI

struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker

        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { [weak self] reading, _ in
                guard let image = reading as? UIImage else { return }
                DispatchQueue.main.async {
                    self?.parent.onImagePicked(image)
                }
            }
        }
    }
}
