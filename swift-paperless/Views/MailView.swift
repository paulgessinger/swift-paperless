import MessageUI
import SwiftUI

struct MailView: UIViewControllerRepresentable {
    typealias ResultType = Result<MFMailComposeResult, any Error>

    @Binding var result: ResultType?
    @Binding var isPresented: Bool

    var prepare: ((MFMailComposeViewController) -> Void)? = nil

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        @Binding var result: ResultType?
        @Binding var isPresented: Bool

        init(result: Binding<ResultType?>, isPresented: Binding<Bool>) {
            _result = result
            _isPresented = isPresented
        }

        func mailComposeController(_: MFMailComposeViewController, didFinishWith _: MFMailComposeResult, error _: (any Error)?) {
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
