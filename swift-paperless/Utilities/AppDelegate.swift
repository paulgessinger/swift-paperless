//
//  AppDelegate.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 05.01.26.
//

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
