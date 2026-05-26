#if canImport(MessageUI)
  import MessageUI
  import SwiftUI

  #if canImport(UIKit)
    import UIKit
  #endif

  public struct FeedbackMailContext: Sendable {
    public var device: String
    public var os: String
    public var locale: String
    public var serverURL: String?
    public var username: String?

    @MainActor
    public static func make(connectionManager: ConnectionManager? = nil) -> FeedbackMailContext {
      var context = systemOnly()
      guard let connectionManager,
        let activeConnectionId = connectionManager.activeConnectionId,
        let stored = connectionManager.connections[activeConnectionId]
      else {
        return context
      }
      context.serverURL = stored.url.absoluteString
      context.username = stored.user.username
      return context
    }

    @MainActor
    private static func systemOnly() -> FeedbackMailContext {
      #if canImport(UIKit)
        let device = "\(UIDevice.current.model) (\(deviceModelIdentifier))"
        let os = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
      #else
        let device = "Unknown"
        let os = "Unknown"
      #endif

      return FeedbackMailContext(
        device: device,
        os: os,
        locale: Locale.current.identifier,
        serverURL: nil,
        username: nil
      )
    }

    func messageFooter() -> String {
      let version = Bundle.main.releaseVersionNumber ?? "?"
      let build = Bundle.main.buildVersionNumber ?? "?"

      var lines = [
        "---",
        "App version: \(version) (\(build)), \(Bundle.main.appConfiguration.rawValue)",
        "Device: \(device)",
        "OS: \(os)",
        "Locale: \(locale)",
      ]

      if let serverURL {
        lines.append("Server: \(serverURL)")
      }
      if let username {
        lines.append("User: \(username)")
      }

      return lines.joined(separator: "\n")
    }

    #if canImport(UIKit)
      private static var deviceModelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { buffer in
          buffer.compactMap { byte in
            byte != 0 ? Character(UnicodeScalar(UInt8(byte))) : nil
          }
        }.map(String.init).joined()
      }
    #endif
  }

  public enum FeedbackMail {
    public static let recipient = "swift-paperless@paulgessinger.com"

    @MainActor
    public static var canSendMail: Bool {
      MFMailComposeViewController.canSendMail()
    }

    @MainActor
    public static func prepare(
      _ viewController: MFMailComposeViewController,
      logFileURL: URL?,
      context: FeedbackMailContext
    ) {
      viewController.setToRecipients([recipient])
      if let logFileURL, let data = try? Data(contentsOf: logFileURL) {
        viewController.addAttachmentData(data, mimeType: "text/plain", fileName: "logs.txt")
      }

      viewController.setMessageBody(context.messageFooter(), isHTML: false)
    }
  }

  public struct FeedbackMailRequest: Identifiable {
    public let id = UUID()
    public let logFileURL: URL
    public let context: FeedbackMailContext

    @MainActor
    public init(logFileURL: URL, connectionManager: ConnectionManager? = nil) {
      self.logFileURL = logFileURL
      self.context = .make(connectionManager: connectionManager)
    }
  }

  extension View {
    @ViewBuilder
    public func feedbackMailSheet(item: Binding<FeedbackMailRequest?>) -> some View {
      sheet(item: item) { _ in
        FeedbackMailSheetContent(request: item)
      }
    }
  }

  private struct FeedbackMailSheetContent: View {
    @Binding var request: FeedbackMailRequest?
    @State private var result: MailView.ResultType?
    @State private var isPresented = true

    var body: some View {
      if let request {
        // @FIXME: Weird empty bottom row that seems to come from MessageUI itself
        MailView(result: $result, isPresented: $isPresented) { viewController in
          FeedbackMail.prepare(
            viewController, logFileURL: request.logFileURL, context: request.context)
        }
        .onChange(of: isPresented) {
          if !isPresented {
            self.request = nil
          }
        }
      }
    }
  }
#endif
