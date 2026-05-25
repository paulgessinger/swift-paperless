#if canImport(MessageUI)
  import MessageUI
  import SwiftUI

  public struct MailView: UIViewControllerRepresentable {
    public typealias ResultType = Result<MFMailComposeResult, any Error>

    @Binding var result: ResultType?
    @Binding var isPresented: Bool

    var prepare: ((MFMailComposeViewController) -> Void)? = nil

    public init(
      result: Binding<ResultType?>, isPresented: Binding<Bool>,
      prepare: ((MFMailComposeViewController) -> Void)? = nil
    ) {
      self._result = result
      self._isPresented = isPresented
      self.prepare = prepare
    }

    public class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
      @Binding var result: ResultType?
      @Binding var isPresented: Bool

      init(result: Binding<ResultType?>, isPresented: Binding<Bool>) {
        _result = result
        _isPresented = isPresented
      }

      public func mailComposeController(
        _: MFMailComposeViewController, didFinishWith _: MFMailComposeResult, error _: (any Error)?
      ) {
        isPresented = false
      }
    }

    public func makeCoordinator() -> Coordinator {
      Coordinator(result: $result, isPresented: $isPresented)
    }

    public func makeUIViewController(context: Context) -> some UIViewController {
      let vc = MFMailComposeViewController()
      vc.mailComposeDelegate = context.coordinator
      if let prepare {
        prepare(vc)
      }
      return vc
    }

    public func updateUIViewController(_: UIViewControllerType, context _: Context) {}
  }
#endif
