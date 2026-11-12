//
//  DocumentCamera.swift
//  AppShared
//

#if os(iOS)
  import VisionKit

  /// VisionKit's document camera, which the Scan Document menu item needs.
  public enum DocumentCamera {
    /// Whether this device supports the document camera. Both the scan menu
    /// item and the features telemetry reports as available read this.
    @MainActor
    public static var isAvailable: Bool {
      get async {
        await withCheckedContinuation { continuation in
          Task.detached {
            await continuation.resume(returning: VNDocumentCameraViewController.isSupported)
          }
        }
      }
    }
  }
#endif
