//
//  swift_paperlessApp.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import Common
import Networking
import SwiftUI
import os

struct MainView: View {
  @State private var showLoginScreen = false

  @State private var storeReady = false
  @State private var showLoadingScreen = false
  @State private var store: DocumentStore?
  @State private var initialDisplay = true
  @State private var showSettings = false

  @StateObject private var manager = ConnectionManager()
  @StateObject private var imagePipelineProvider = ImagePipelineProvider()

  @StateObject private var errorController: ErrorController

  @Environment(\.scenePhase) var scenePhase

  @ObservedObject private var appSettings = AppSettings.shared

  @State private var releaseNotesModel = ReleaseNotesViewModel()

  @StateObject private var biometricLockManager: BiometricLockManager

  @Environment(RouteManager.self) private var routeManager

  init() {
    _ = AppSettings.shared
    let errorController = ErrorController()
    _errorController = StateObject(wrappedValue: errorController)
    _biometricLockManager = StateObject(
      wrappedValue: BiometricLockManager(errorController: errorController))
  }

  private func handleUrlOpen(_ url: URL) {
    Logger.shared.info("App opened with URL: \(url)")

    let route: Route
    do {
      route = try Route(from: url)
    } catch {
      Logger.shared.error(
        "Unable to parse route from URL: \(url), error: \(String(describing: error))")
      errorController.push(error: error)
      return
    }

    Logger.shared.info("Parsed route is: \(String(describing: route))")

    let targetConnection: StoredConnection? = {

      guard let server = route.server else {
        // no incoming server, assume current server
        return nil
      }

      Logger.shared.info("Attempting to change connection to \(server)")

      guard
        let target = manager.connections.first(where: { element in
          let conn = element.value

          guard var connComponents = URLComponents(url: conn.url, resolvingAgainstBaseURL: false)
          else {
            return false
          }

          // need to add a scheme since username parsing ostensibly depends on it
          let scheme = connComponents.scheme ?? "http"
          connComponents.scheme = scheme
          guard let routeComponents = URLComponents(string: "\(scheme)://\(server)") else {
            return false
          }

          // if route url has user, copy over for comparison
          if routeComponents.user != nil {
            // incoming route has no user, check against no-user stored urls
            connComponents.user = conn.user.username
          }

          guard let connString = connComponents.url?.absoluteString,
            let routeString = routeComponents.url?.absoluteString
          else {
            return false
          }

          return connString == routeString

        })
      else {
        return nil
      }

      return target.value
    }()

    Task {
      if let targetConnection {
        Logger.shared.info(
          "Identified \(String(describing: targetConnection)) as the target connection")
        if manager.activeConnectionId == targetConnection.id {
          Logger.shared.debug("Active connection is already \(targetConnection.id), not changing")
        } else {
          Logger.shared.debug("Changing active connection to \(targetConnection.id)")
          manager.activeConnectionId = targetConnection.id
          await refreshConnection(animated: false)
        }
      } else {
        if let server = route.server {
          Logger.shared.warning(
            "Unable to change connection to \(server) to accomodate route request")
        }
      }

      routeManager.pendingRoute = route
    }
  }

  private func refreshConnection(animated: Bool) async {
    Logger.api.info("Connection info changed, reloading!")
    if let conn = manager.connection {
      storeReady = false
      if animated {
        showLoadingScreen = true
      }

      func sleep(_ duration: Duration) async {
        if animated {
          try? await Task.sleep(for: duration)
        }
      }

      Logger.api.info("Valid connection from connection manager: \(String(describing: conn))")
      if let store {
        await sleep(.seconds(0.1))
        store.eventPublisher.send(.repositoryWillChange)
        await sleep(.seconds(0.3))
        await store.set(
          repository: ApiRepository(connection: conn, mode: Bundle.main.appConfiguration.mode))
        imagePipelineProvider.update(delegate: store.repository.delegate)
        storeReady = true
        try? await store.fetchAll()
        store.startTaskPolling()
        await sleep(.seconds(0.3))
        showLoadingScreen = false
      } else {
        store = await DocumentStore(
          repository: ApiRepository(connection: conn, mode: Bundle.main.appConfiguration.mode))
        imagePipelineProvider.update(delegate: store!.repository.delegate)
        storeReady = true
        try? await store!.fetchAll()
        store!.startTaskPolling()
        showLoadingScreen = false
      }
      showLoginScreen = false
    } else {
      imagePipelineProvider.update(delegate: nil)
      storeReady = false
      Logger.shared.trace("App does not have any active connection, show login screen")
      showLoginScreen = true
      showLoadingScreen = false
    }
  }

  private func setupQuickActions() {
    let inboxAction = UIApplicationShortcutItem(
      type: "com.paulgessinger.swift-paperless.ActionScan",
      localizedTitle: String(localized: .localizable(.scanDocument)),
      localizedSubtitle: nil,
      icon: UIApplicationShortcutIcon(systemImageName: "document.viewfinder"),
      userInfo: ["url": "x-paperless://v1/scan" as any NSSecureCoding]
    )

    UIApplication.shared.shortcutItems = [inboxAction]
  }

  var body: some View {
    VStack {
      ZStack {
        if manager.connection != nil, storeReady {
          DocumentView(showSettings: $showSettings)
            .errorOverlay(errorController: errorController)
            .environmentObject(store!)
            .environmentObject(manager)

            .overlay {
              if AppSettings.shared.enableBiometricAppLock,
                biometricLockManager.lockState == .locked || scenePhase == .inactive
              {
                InactiveView()
                  .transition(.opacity)
              }
            }
        }

        VStack {
          if showLoadingScreen {
            MainLoadingView(
              url: manager.connection?.url.absoluteString,
              manager: manager
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(BackgroundColorModifier())
          }
        }
        .animation(.default, value: showLoadingScreen)
      }
    }
    .animation(.default, value: storeReady)

    .environmentObject(errorController)
    .environmentObject(biometricLockManager)
    .environmentObject(imagePipelineProvider)

    .fullScreenCover(isPresented: $showLoginScreen) {
      LoginView(connectionManager: manager)
        .errorOverlay(errorController: errorController)
        .environmentObject(errorController)
        .interactiveDismissDisabled()
    }

    .fullScreenCover(isPresented: $releaseNotesModel.showReleaseNotes) {
      ReleaseNotesCoverView(releaseNotesModel: $releaseNotesModel)
    }

    .sheet(isPresented: $showSettings) {
      if let store {
        SettingsView()
          .environmentObject(manager)
          .environmentObject(store)
          .environmentObject(errorController)
          .environmentObject(biometricLockManager)
      }
    }

    .task {
      biometricLockManager.lockIfEnabled()

      Logger.shared.info("INITIAL ROUTE: \(String(describing:RouteManager.shared.pendingURL))")
      Logger.shared.info("INITIAL ROUTE: \(String(describing:routeManager.pendingURL))")
      setupQuickActions()

      Logger.shared.notice("Checking login status")
      await refreshConnection(animated: initialDisplay)
      initialDisplay = false

      // @TODO: Remove in a few versions
      Task {
        try? await Task.sleep(for: .seconds(3))
        await manager.migrateToMultiServer()
      }
    }

    .onReceive(manager.eventPublisher) { event in
      switch event {
      case .connectionChange(let animated):
        Task { await refreshConnection(animated: animated) }
      case .logout:
        showLoginScreen = true
      }
    }

    .onChange(of: scenePhase) { _, value in
      switch value {
      case .inactive:
        Logger.shared.notice("App becomes inactive")

      case .background:
        Logger.shared.notice("App goes to background")
        biometricLockManager.lockIfEnabled()

      case .active:
        store?.startTaskPolling()

        Logger.shared.notice("App becomes active")

        Task { await biometricLockManager.unlockIfEnabled() }

      default:
        break
      }
    }

    .onOpenURL(perform: handleUrlOpen)
    .onChange(of: routeManager.pendingURL, initial: true) {
      if let url = routeManager.pendingURL {
        handleUrlOpen(url)
        routeManager.pendingURL = nil
      }
    }
  }
}

@main
struct swift_paperlessApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    WindowGroup {
      MainView()
        .environment(RouteManager.shared)
    }
  }
}
