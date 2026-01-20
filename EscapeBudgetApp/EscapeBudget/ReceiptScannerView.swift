import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ReceiptScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var showingFilePicker = false
    @State private var selectedImage: UIImage?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    let onReceiptScanned: (UIImage) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.Spacing.xLarge) {
                Spacer()

                Image(systemName: "doc.text.image")
                    .appIconHero()
                    .foregroundStyle(.secondary)

                VStack(spacing: AppTheme.Spacing.compact) {
                    Text("Scan Receipt")
                        .font(.title2.bold())

                    Text("Take a photo, select from your library, or choose a file")
                        .appSecondaryBodyText()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(spacing: AppTheme.Spacing.tight) {
                    Button {
                        checkCameraAndPresent()
                    } label: {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Take Photo")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .appPrimaryCTA()
                    .controlSize(.large)

                    Button {
                        showingPhotoPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text("Choose from Library")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .appSecondaryCTA()
                    .controlSize(.large)

                    Button {
                        showingFilePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text("Choose from Files")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .appSecondaryCTA()
                    .controlSize(.large)
                }
                .padding(.horizontal)

                if isProcessing {
                    ProgressView("Processing receipt...")
                        .padding()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .appCaptionText()
                        .foregroundStyle(.red)
                        .padding()
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Add Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraView { image in
                    selectedImage = image
                    processImage(image)
                }
            }
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: Binding(
                    get: { nil },
                    set: { newValue in
                        if let newValue {
                            loadPhoto(from: newValue)
                        }
                    }
                ),
                matching: .images
            )
            .sheet(isPresented: $showingFilePicker) {
                DocumentPicker(
                    allowedContentTypes: [.image, .pdf],
                    onDocumentPicked: { url in
                        loadFile(from: url)
                    }
                )
            }
        }
    }

    private func checkCameraAndPresent() {
        // Check if camera is available (not available on simulator)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showingCamera = true
        } else {
            errorMessage = "Camera not available. Please use a physical device or choose from library/files instead."
        }
    }

    private func loadPhoto(from item: PhotosPickerItem) {
        isProcessing = true
        errorMessage = nil

        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        selectedImage = image
                        processImage(image)
                    }
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = "Failed to load image"
                }
            }
        }
    }

    private func loadFile(from url: URL) {
        isProcessing = true
        errorMessage = nil

        // Start accessing security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Failed to access file"
            isProcessing = false
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            try SensitiveFileProtection.validateImportableFile(
                at: url,
                maxBytes: 25 * 1024 * 1024,
                allowedExtensions: ["pdf", "png", "jpg", "jpeg", "heic", "tiff", "bmp"]
            )

            let data = try Data(contentsOf: url, options: [.mappedIfSafe])

            // Check if it's a PDF or image
            if url.pathExtension.lowercased() == "pdf" {
                // Convert first page of PDF to image
                if let image = convertPDFToImage(data: data) {
                    selectedImage = image
                    processImage(image)
                } else {
                    errorMessage = "Failed to convert PDF to image"
                    isProcessing = false
                }
            } else if let image = UIImage(data: data) {
                selectedImage = image
                processImage(image)
            } else {
                errorMessage = "Unsupported file format"
                isProcessing = false
            }
        } catch {
            if (error as? SensitiveFileProtection.ValidationError) != nil {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = "Failed to load file"
            }
            isProcessing = false
        }
    }

    private func convertPDFToImage(data: Data) -> UIImage? {
        guard let provider = CGDataProvider(data: data as CFData),
              let pdfDoc = CGPDFDocument(provider),
              let page = pdfDoc.page(at: 1) else {
            return nil
        }

        let pageRect = page.getBoxRect(.mediaBox)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)

        let image = renderer.image { context in
            UIColor.white.set()
            context.fill(pageRect)

            context.cgContext.translateBy(x: 0, y: pageRect.size.height)
            context.cgContext.scaleBy(x: 1.0, y: -1.0)
            context.cgContext.drawPDFPage(page)
        }

        return image
    }

    private func processImage(_ image: UIImage) {
        isProcessing = true
        errorMessage = nil

        // Pass image back to parent
        onReceiptScanned(image)
        dismiss()
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImageCaptured: (UIImage) -> Void

        init(onImageCaptured: @escaping (UIImage) -> Void) {
            self.onImageCaptured = onImageCaptured
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImageCaptured(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Document Picker

struct DocumentPicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let onDocumentPicked: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentPicked: onDocumentPicked)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDocumentPicked: (URL) -> Void

        init(onDocumentPicked: @escaping (URL) -> Void) {
            self.onDocumentPicked = onDocumentPicked
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onDocumentPicked(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            controller.dismiss(animated: true)
        }
    }
}

#Preview {
    ReceiptScannerView { _ in }
}
