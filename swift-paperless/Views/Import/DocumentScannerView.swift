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

struct DocumentScannerView: UIViewControllerRepresentable {
  @Binding var isPresented: Bool
  let onCompletion: @Sendable (_ result: Result<[URL], any Error>) -> Void

  @MainActor
  static var isAvailable: Bool {
    get async {
      await isCameraViewControllerSupported()
    }
  }

  class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
    @Binding var isPresented: Bool
    let completionHandler: @Sendable (_ result: Result<[URL], any Error>) -> Void

    private var hasConfigured = false

    init(
      isPresented: Binding<Bool>,
      onCompletion: @Sendable @escaping (_ result: Result<[URL], any Error>) -> Void
    ) {
      _isPresented = isPresented
      completionHandler = onCompletion
    }

    func configureScanner(_ vc: VNDocumentCameraViewController) {
      guard !hasConfigured else { return }
      hasConfigured = true

      let flashEnabled = AppSettings.value(for: .scannerFlashEnabled, or: false)
      let autoscanEnabled = AppSettings.value(for: .scannerAutoscanEnabled, or: true)

      let view = vc.view!
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(500))
        Coordinator.applySettings(in: view, flash: flashEnabled, autoscan: autoscanEnabled)
      }
    }

    // MARK: - Scanner Settings

    enum SettingResult: CustomStringConvertible {
        case success
        case controlNotFound(searched: [String])
        case activationFailed(reason: String)
        case skipped(reason: String)

        var description: String {
            switch self {
            case .success:
                "success"
            case let .controlNotFound(searched):
                "controlNotFound(searched: \(searched))"
            case let .activationFailed(reason):
                "activationFailed(\(reason))"
            case let .skipped(reason):
                "skipped(\(reason))"
            }
        }
    }

    @MainActor
    private static func applySettings(in view: UIView, flash: Bool, autoscan: Bool) {
        let config = ScannerSettingsConfiguration.forCurrentOS()
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion

        Logger.shared.info(
            """
            Scanner settings applying - iOS \(osVersion.majorVersion).\(osVersion.minorVersion), \
            flash: \(flash), autoscan: \(autoscan), supported: \(config.isSupported)
            """
        )

        let diagnostics = captureViewHierarchyDiagnostics(in: view)
        Logger.shared.notice("Scanner view hierarchy: \(diagnostics)")

        if flash {
            let result = applyFlashSetting(in: view, config: config)
            Logger.shared.info("Flash setting result: \(result)")
        }

        if !autoscan {
            let result = disableAutoscan(in: view, config: config)
            Logger.shared.info("Autoscan setting result: \(result)")
        }
    }

    @MainActor
    private static func captureViewHierarchyDiagnostics(in view: UIView) -> String {
        var controls: [(label: String?, title: String?, type: String)] = []

        func traverse(_ v: UIView) {
            if let control = v as? UIControl {
                controls.append((
                    label: control.accessibilityLabel,
                    title: (control as? UIButton)?.currentTitle,
                    type: String(describing: type(of: control))
                ))
            }
            v.subviews.forEach(traverse)
        }

        traverse(view)

        if controls.isEmpty {
            return "No controls found"
        }

        return controls.map { "[\($0.type): '\($0.label ?? "")' / '\($0.title ?? "")']" }
            .joined(separator: ", ")
    }

    @MainActor
    private static func applyFlashSetting(
        in view: UIView,
        config: ScannerSettingsConfiguration
    ) -> SettingResult {
        let pattern = config.flashPattern

        guard let flashButton = findButton(in: view, matching: pattern) else {
            Logger.shared.warning("Scanner: Flash settings button not found")
            return .controlNotFound(searched: pattern.accessibilityLabels + pattern.buttonTitles)
        }

        switch pattern.activationMethod {
        case .sendActions:
            flashButton.sendActions(for: .touchUpInside)
            return .success

        case .tapInnerButton:
            if let innerButton = flashButton.subviews.first(where: { $0 is UIButton }) as? UIButton {
                innerButton.sendActions(for: .touchUpInside)
                return .success
            }
            return .activationFailed(reason: "No inner button found")

        case let .openMenuThenTap(menuItemTitle):
            flashButton.sendActions(for: .touchUpInside)

            Task { @MainActor in
                try? await Task.sleep(for: config.menuDelay)
                if let menuItem = findButton(in: view, titleEquals: menuItemTitle) {
                    menuItem.sendActions(for: .touchUpInside)
                    Logger.shared.info("Flash menu item '\(menuItemTitle)' tapped")
                } else {
                    Logger.shared.warning("Scanner: Flash menu item '\(menuItemTitle)' not found")
                }
            }
            return .success
        }
    }

    @MainActor
    private static func disableAutoscan(
        in view: UIView,
        config: ScannerSettingsConfiguration
    ) -> SettingResult {
        let enabledPattern = config.autoscanEnabledPattern
        let disabledPattern = config.autoscanDisabledPattern

        if findControl(in: view, matching: disabledPattern) != nil {
            return .skipped(reason: "Already disabled")
        }

        guard let autoControl = findControl(in: view, matching: enabledPattern) else {
            Logger.shared.warning("Scanner: Autoscan control not found")
            return .controlNotFound(searched: enabledPattern.accessibilityLabels)
        }

        switch enabledPattern.activationMethod {
        case .sendActions:
            autoControl.sendActions(for: .touchUpInside)
            return .success

        case .tapInnerButton:
            if let innerButton = autoControl.subviews.first(where: { $0 is UIButton }) as? UIButton {
                innerButton.sendActions(for: .touchUpInside)
                return .success
            }
            return .activationFailed(reason: "No inner button found")

        case let .openMenuThenTap(menuItemTitle):
            autoControl.sendActions(for: .touchUpInside)

            Task { @MainActor in
                try? await Task.sleep(for: config.menuDelay)
                if let menuItem = findButton(in: view, titleEquals: menuItemTitle) {
                    menuItem.sendActions(for: .touchUpInside)
                } else {
                    Logger.shared.warning("Scanner: Autoscan menu item '\(menuItemTitle)' not found")
                }
            }
            return .success
        }
    }

    @MainActor
    private static func findButton(in view: UIView, matching pattern: ScannerButtonPattern) -> UIButton? {
        for label in pattern.accessibilityLabels {
            if let button = findButton(in: view, accessibilityLabelContains: label) {
                return button
            }
        }

        for title in pattern.buttonTitles {
            if let button = findButton(in: view, titleEquals: title) {
                return button
            }
        }

        return nil
    }

    @MainActor
    private static func findControl(in view: UIView, matching pattern: ScannerButtonPattern) -> UIControl? {
        for label in pattern.accessibilityLabels {
            if let control = findControl(in: view, accessibilityLabelContains: label) {
                return control
            }
        }
        return nil
    }

    @MainActor
    private static func findButton(in view: UIView, accessibilityLabelContains search: String) -> UIButton? {
        if let button = view as? UIButton,
           let label = button.accessibilityLabel,
           label.localizedCaseInsensitiveContains(search)
        {
            return button
        }
        for subview in view.subviews {
            if let found = findButton(in: subview, accessibilityLabelContains: search) {
                return found
            }
        }
        return nil
    }

    @MainActor
    private static func findButton(in view: UIView, titleEquals title: String) -> UIButton? {
        if let button = view as? UIButton,
           button.currentTitle == title
        {
            return button
        }
        for subview in view.subviews {
            if let found = findButton(in: subview, titleEquals: title) {
                return found
            }
        }
        return nil
    }

    @MainActor
    private static func findControl(in view: UIView, accessibilityLabelContains search: String) -> UIControl? {
        if let control = view as? UIControl,
           let label = control.accessibilityLabel,
           label.localizedCaseInsensitiveContains(search)
        {
            return control
        }
        for subview in view.subviews {
            if let found = findControl(in: subview, accessibilityLabelContains: search) {
                return found
            }
        }
        return nil
    }

    func documentCameraViewController(
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

    func documentCameraViewControllerDidCancel(_: VNDocumentCameraViewController) {
      isPresented = false
    }

    func documentCameraViewController(
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

  func makeCoordinator() -> Coordinator {
    Coordinator(isPresented: $isPresented, onCompletion: onCompletion)
  }

  func makeUIViewController(context: Context) -> some UIViewController {
    let vc = VNDocumentCameraViewController()
    vc.delegate = context.coordinator
    return vc
  }

  func updateUIViewController(_ vc: UIViewControllerType, context: Context) {
    if let documentVC = vc as? VNDocumentCameraViewController {
      context.coordinator.configureScanner(documentVC)
    }
  }
}
