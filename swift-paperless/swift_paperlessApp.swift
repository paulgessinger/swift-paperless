//
//  swift_paperlessApp.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import AppShared
import Combine
import Common
import DataModel
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

  @State private var friendlyNameSubscription: AnyCancellable?

  @StateObject private var errorController: ErrorController

  @State private var networkMonitor = NetworkMonitor()

  @Environment(\.scenePhase) var scenePhase

  @ObservedObject private var appSettings = AppSettings.shared

  @State private var releaseNotesModel = ReleaseNotesViewModel()

  @StateObject private var biometricLockManager: BiometricLockManager

  // Per-scene routing state. Owning this here (instead of a global
  // singleton) means each window in a multi-window setup has its own
  // pendingRoute, so listeners in one scene don't react to URLs that
  // landed in another.
  @State private var routeManager = RouteManager()

  init() {
    _ = AppSettings.shared
    let errorController = ErrorController()
    let networkMonitor = NetworkMonitor()
    // Suppress the noise that the connection-status banner already covers:
    // every 401 (the banner offers re-auth), and connectivity-class errors
    // while the device is offline (the banner says so). Server-unreachable
    // errors while online still surface — that's a real per-server problem.
    errorController.shouldSuppress = { [weak networkMonitor] error in
      if let req = error as? RequestError, case .unauthorized = req {
        return true
      }
      let offline = networkMonitor?.isOnline == false
      guard offline else { return false }
      if let url = error as? URLError {
        switch url.code {
        case .notConnectedToInternet, .networkConnectionLost,
          .dataNotAllowed, .timedOut:
          return true
        default: break
        }
      }
      if let ns = error as NSError?, ns.domain == NSURLErrorDomain {
        switch ns.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
          NSURLErrorDataNotAllowed, NSURLErrorTimedOut:
          return true
        default: break
        }
      }
      return false
    }
    _errorController = StateObject(wrappedValue: errorController)
    _networkMonitor = State(initialValue: networkMonitor)
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
      let api = await ApiRepository(connection: conn, mode: Bundle.main.appConfiguration.mode)
      let repository = NeedsAuthRepository(
        wrapping: api, serverID: conn.serverID, connectionManager: manager)
      if let store {
        await sleep(.seconds(0.1))
        store.eventPublisher.send(.repositoryWillChange)
        await sleep(.seconds(0.3))
        store.set(repository: repository)
        storeReady = true
        try? await store.fetchAll()
        store.startTaskPolling()
        await sleep(.seconds(0.3))
        showLoadingScreen = false
      } else {
        let newStore = DocumentStore(repository: repository)
        store = newStore
        observeFriendlyName(on: newStore)
        storeReady = true
        try? await newStore.fetchAll()
        newStore.startTaskPolling()
        showLoadingScreen = false
      }
      showLoginScreen = false
    } else {
      storeReady = false
      Logger.shared.trace("App does not have any active connection, show login screen")
      showLoginScreen = true
      showLoadingScreen = false
    }
  }

  private func observeFriendlyName(on store: DocumentStore) {
    // Forwards the server's PAPERLESS_APP_TITLE (settings.appTitle) to the
    // active connection. compactMap drops nil values so resets from
    // store.clear() don't wipe out a previously stored friendly name.
    friendlyNameSubscription =
      store.$settings
      .compactMap(\.appTitle)
      .removeDuplicates()
      .sink { [manager] title in
        manager.setFriendlyName(title)
      }
  }

  private func setupQuickActions() {
    let inboxAction = UIApplicationShortcutItem(
      type: "com.paulgessinger.swift-paperless.ActionScan",
      localizedTitle: String(localized: .app(.scanDocument)),
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
            .environmentObject(store!)
            .environmentObject(manager)
            .safeAreaInset(edge: .bottom, spacing: 0) {
              NeedsAuthBanner()
                .environmentObject(manager)
                .environment(networkMonitor)
            }
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
    .environment(networkMonitor)

    .fullScreenCover(isPresented: $showLoginScreen) {
      LoginView(connectionManager: manager)
        .environmentObject(errorController)
        .interactiveDismissDisabled()
    }

    .sheet(
      isPresented: Binding(
        get: { manager.reauthRequested != nil },
        set: { presented in
          if !presented { manager.cancelReauthRequest() }
        })
    ) {
      if let id = manager.reauthRequested,
        let stored = manager.connections[id]
      {
        ReauthSheet(stored: stored)
          .environmentObject(manager)
          .environmentObject(errorController)
          .environment(networkMonitor)
      }
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

      guard initialDisplay else {
        return
      }

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
    .environment(routeManager)
    .appOverlays(
      errorController: errorController,
      networkMonitor: networkMonitor
    )
  }
}

@main
struct swift_paperlessApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    WindowGroup {
      MainView()
    }
  }
}
