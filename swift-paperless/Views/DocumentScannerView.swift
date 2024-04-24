import os
import PDFKit
import SwiftUI
import VisionKit

struct DocumentScannerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onCompletion: @Sendable (_ result: Result<[URL], Error>) -> Void

    @MainActor
    static var isAvailable: Bool {
        VNDocumentCameraViewController.isSupported
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
                let url = try createPDF(from: scan)
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

        private func createPDF(from scan: VNDocumentCameraScan) throws -> URL {
            let pdfDocument = PDFDocument()
            for i in 0 ..< scan.pageCount {
                if let pdfPage = PDFPage(image: scan.imageOfPage(at: i)) {
                    pdfDocument.insert(pdfPage, at: i)
                } else {
                    throw DocumentScannerError.pdfCreatePageFailed
                }
            }

            let date = Date().formatted(.verbatim(
                "\(year: .extended())-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .oneBased)).\(minute: .twoDigits).\(second: .twoDigits)",
                timeZone: TimeZone.current,
                calendar: .current
            ))

            let url = FileManager.default.temporaryDirectory
                .appending(component: "Scan \(date)")
                .appendingPathExtension("pdf")

            if pdfDocument.write(to: url) {
                return url
            } else {
                throw DocumentScannerError.pdfWriteFailed
            }
        }
    }

    enum DocumentScannerError: LocalizedError {
        case pdfWriteFailed
        case pdfCreatePageFailed

        var errorDescription: String? {
            switch self {
            case .pdfCreatePageFailed:
                return String(localized: .localizable.documentScanErrorCreatePageFailed)
            case .pdfWriteFailed:
                return String(localized: .localizable.documentScanErrorWriteFailed)
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
