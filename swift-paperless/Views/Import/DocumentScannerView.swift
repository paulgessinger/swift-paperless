import os
import PDFKit
import SwiftUI
import VisionKit

private func isCameraViewControllerSupported() async -> Bool {
    await withCheckedContinuation { continuation in
        Task.detached {
            await continuation.resume(returning: VNDocumentCameraViewController.isSupported)
        }
    }
}

struct DocumentScannerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onCompletion: @Sendable (_ result: Result<[URL], Error>) -> Void

    @MainActor
    static var isAvailable: Bool {
        get async {
            await isCameraViewControllerSupported()
        }
    }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        @Binding var isPresented: Bool
        let completionHandler: @Sendable (_ result: Result<[URL], Error>) -> Void

        init(isPresented: Binding<Bool>, onCompletion: @Sendable @escaping (_ result: Result<[URL], Error>) -> Void) {
            _isPresented = isPresented
            completionHandler = onCompletion
        }

        func documentCameraViewController(_: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            Logger.shared.notice("Document scanner receives scan")
            do {
                Logger.shared.notice("Attempt to make PDF")

                let images = (0 ..< scan.pageCount).map { scan.imageOfPage(at: $0) }
                let url = try createPDFFrom(images: images)

                isPresented = false
                Task { [completionHandler = self.completionHandler] in
                    Logger.shared.notice("PDF conversion success")
                    completionHandler(.success([url]))
                }
            } catch {
                isPresented = false
                Task { [completionHandler = self.completionHandler] in
                    Logger.shared.error("PDF conversion failure: \(error)")
                    completionHandler(.failure(error))
                }
            }
        }

        func documentCameraViewControllerDidCancel(_: VNDocumentCameraViewController) {
            isPresented = false
        }

        func documentCameraViewController(_: VNDocumentCameraViewController, didFailWithError error: Error) {
            Logger.shared.notice("Document scanner receives error")
            isPresented = false
            Task { [completionHandler = self.completionHandler] in
                Logger.shared.error("Document scanner error: \(error)")
                completionHandler(.failure(error))
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onCompletion: onCompletion)
    }

    func makeUIViewController(context: Context) -> some UIViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_: UIViewControllerType, context _: Context) {}
}
