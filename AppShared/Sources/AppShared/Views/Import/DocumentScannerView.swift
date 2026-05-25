import PDFKit
import SwiftUI
import VisionKit
import os

private func isCameraViewControllerSupported() async -> Bool {
  await withCheckedContinuation { continuation in
    Task.detached {
      await continuation.resume(returning: VNDocumentCameraViewController.isSupported)
    }
  }
}

public struct DocumentScannerView: UIViewControllerRepresentable {
  @Binding public var isPresented: Bool
  public let onCompletion: @Sendable (_ result: Result<[URL], any Error>) -> Void

  public init(
    isPresented: Binding<Bool>,
    onCompletion: @escaping @Sendable (_ result: Result<[URL], any Error>) -> Void
  ) {
    self._isPresented = isPresented
    self.onCompletion = onCompletion
  }

  @MainActor
  public static var isAvailable: Bool {
    get async {
      await isCameraViewControllerSupported()
    }
  }

  public class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
    @Binding var isPresented: Bool
    let completionHandler: @Sendable (_ result: Result<[URL], any Error>) -> Void

    init(
      isPresented: Binding<Bool>,
      onCompletion: @Sendable @escaping (_ result: Result<[URL], any Error>) -> Void
    ) {
      _isPresented = isPresented
      completionHandler = onCompletion
    }

    public func documentCameraViewController(
      _: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
    ) {
      Logger.shared.notice("Document scanner receives scan")
      do {
        Logger.shared.notice("Attempt to make PDF")

        let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
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

    public func documentCameraViewControllerDidCancel(_: VNDocumentCameraViewController) {
      isPresented = false
    }

    public func documentCameraViewController(
      _: VNDocumentCameraViewController, didFailWithError error: any Error
    ) {
      Logger.shared.notice("Document scanner receives error")
      isPresented = false
      Task { [completionHandler = self.completionHandler] in
        Logger.shared.error("Document scanner error: \(error)")
        completionHandler(.failure(error))
      }
    }
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(isPresented: $isPresented, onCompletion: onCompletion)
  }

  public func makeUIViewController(context: Context) -> some UIViewController {
    let vc = VNDocumentCameraViewController()
    vc.delegate = context.coordinator
    return vc
  }

  public func updateUIViewController(_: UIViewControllerType, context _: Context) {}
}
