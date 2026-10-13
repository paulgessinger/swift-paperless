//
//  HingeDetector.swift
//  swift-paperless
//

import UIKit

#if HINGE_API
  /// Whether the device has a hinge, learned from the first `UIHingeInteraction`
  /// update that carries one. A capability check rather than a device check:
  /// the fold's reserved region is not reported on the outer display, the hinge is.
  @available(iOS 27.1, *)
  @MainActor
  enum HingeDetector {
    private(set) static var deviceHasHinge = false

    static func observe(_ window: UIWindow) {
      guard !deviceHasHinge,
        !window.interactions.contains(where: { $0 is UIHingeInteraction })
      else { return }
      window.addInteraction(
        UIHingeInteraction { [weak window] _, update in
          guard update.hinge != nil, !deviceHasHinge else { return }
          deviceHasHinge = true
          window?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        })
    }
  }
#endif
