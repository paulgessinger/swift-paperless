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
  func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    if let urlString = shortcutItem.userInfo?["url"] as? String,
      let url = URL(string: urlString)
    {
      RouteManager.shared.pendingURL = url
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
    // Handle shortcut on app launch
    if let shortcutItem = connectionOptions.shortcutItem {
      if let urlString = shortcutItem.userInfo?["url"] as? String,
        let url = URL(string: urlString)
      {
        //        NotificationCenter.default.post(name: .openShortcutURL, object: url)
        RouteManager.shared.pendingURL = url
      }
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
