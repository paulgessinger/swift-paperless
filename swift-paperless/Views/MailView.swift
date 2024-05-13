import MessageUI
import SwiftUI

struct MailView: UIViewControllerRepresentable {
    @Binding var result: Result<MFMailComposeResult, Error>?
    @Binding var isPresented: Bool

    var prepare: ((MFMailComposeViewController) -> Void)? = nil

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        @Binding var result: Result<MFMailComposeResult, Error>?
        @Binding var isPresented: Bool

        init(result: Binding<Result<MFMailComposeResult, Error>?>, isPresented: Binding<Bool>) {
            _result = result
            _isPresented = isPresented
        }

        func mailComposeController(_: MFMailComposeViewController, didFinishWith _: MFMailComposeResult, error _: Error?) {
            isPresented = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(result: $result, isPresented: $isPresented)
    }

    func makeUIViewController(context: Context) -> some UIViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        if let prepare {
            prepare(vc)
        }
        return vc
    }

    func updateUIViewController(_: UIViewControllerType, context _: Context) {}
}
