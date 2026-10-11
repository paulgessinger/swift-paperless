//
//  AppDelegate.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 05.01.26.
//

import AppShared
import AppViews
import Persistence
import UIKit

extension NSNotification.Name {
  static let openShortcutURL = Self("com.paulgessinger.swift-paperless.OpenShorcutURL")
}

class SceneDelegate: NSObject, UIWindowSceneDelegate {
  // Quick Actions deliver per-scene already (UIKit picks the scene the user
  // tapped from). To keep routing state scoped to that one scene we don't
  // touch RouteManager directly — we open the URL on the scene, which
  // round-trips through `scene(_:openURLContexts:)` and SwiftUI's
  // `.onOpenURL`, landing in this scene's MainView.
  func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    if let urlString = shortcutItem.userInfo?["url"] as? String,
      let url = URL(string: urlString)
    {
      windowScene.open(url, options: nil, completionHandler: nil)
      completionHandler(true)
    } else {
      completionHandler(false)
    }
  }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // Cold-launch shortcut. Defer the open until after SwiftUI has built
    // the scene's view hierarchy — otherwise `.onOpenURL` isn't registered
    // yet when we try to deliver.
    guard
      let shortcutItem = connectionOptions.shortcutItem,
      let urlString = shortcutItem.userInfo?["url"] as? String,
      let url = URL(string: urlString)
    else { return }
    Task { @MainActor in
      await scene.open(url, options: nil)
    }
  }
}

class AppDelegate: NSObject, UIApplicationDelegate {
  /// Release the SQLite write lock before iOS suspends the process — a write
  /// still holding it at suspension is a `0xDEAD10CC` termination.
  /// `DatabaseSuspensionController` decides when, given background work.
  ///
  /// Notifications rather than `applicationDidEnterBackground(_:)`, which UIKit
  /// never calls once an app adopts scenes (this one vends a
  /// `UIWindowSceneDelegate`, above). They are also process-wide, where a
  /// scene's `.background` is not: on iPad one window backgrounds while the
  /// others stay on screen.
  ///
  /// `queue: nil` to run synchronously — a queued block could land after the
  /// process was already suspended.
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    let suspension = AppStackHolder.suspension
    suspension.attach(
      isInBackground: application.applicationState == .background,
      requestTime: BackgroundTime.request)
    BackgroundTaskManager.registerTasks()
    // Covers a first launch and Background App Refresh being turned back on;
    // a pending request is left alone.
    BackgroundTaskManager.ensureScheduled()

    // UIKit posts these on the main thread, and `queue: nil` delivers there.
    let center = NotificationCenter.default
    center.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
    ) { _ in
      MainActor.assumeIsolated {
        suspension.didEnterBackground()
        BackgroundTaskManager.ensureScheduled()
      }
    }
    center.addObserver(
      forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil
    ) { _ in
      MainActor.assumeIsolated { suspension.willEnterForeground() }
    }
    return true
  }

  /// iPhones stay portrait; a foldable iPhone also rotates to landscape on both
  /// displays. The inner display ignores this mask anyway, so it decides the
  /// outer one. iPad keeps every orientation.
  func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
    #if HINGE_API
      if #available(iOS 27.1, *), let window {
        HingeDetector.observe(window)
        if HingeDetector.deviceHasHinge { return .allButUpsideDown }
      }
    #endif
    return .portrait
  }

  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(
      name: "Default Configuration",
      sessionRole: connectingSceneSession.role
    )
    configuration.delegateClass = SceneDelegate.self  // Register your SceneDelegate
    return configuration
  }

  //  func application(
  //          _ application: UIApplication,
  //          didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  //      ) -> Bool {
  //          // Inject coordinator into scene delegate
  //          if let sceneDelegate = UIApplication.shared.connectedScenes
  //              .compactMap({ $0.delegate as? SceneDelegate })
  //              .first {
  //              sceneDelegate.routeManager = routeManager
  //          }
  //          return true
  //      }
}

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
