//
//  swift_paperlessApp.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import AppShared
import Common
import DataModel
import Networking
import Persistence
import SwiftUI
import os

struct MainView: View {
  @State private var showLoginScreen = false

  @State private var storeReady = false
  @State private var showLoadingScreen = false
  @State private var store: DocumentStore?
  @State private var initialDisplay = true
  @State private var showSettings = false

  @State private var manager: ConnectionManager

  // Keeps every *inactive* server's offline cache warm. The active
  // server stays on the DocumentStore path; the engine skips it.
  @State private var syncEngine: SyncEngine

  // Shared GRDB database, threaded into each connection's CachingRepository.
  private let database: Database

  @State private var friendlyNameSubscription: Subscription?

  @StateObject private var errorController: ErrorController

  @State private var networkMonitor = NetworkMonitor()

  @Environment(\.scenePhase) var scenePhase

  @State private var releaseNotesModel = ReleaseNotesViewModel()

  @StateObject private var biometricLockManager: BiometricLockManager

  // Per-scene routing state. Owning this here (instead of a global
  // singleton) means each window in a multi-window setup has its own
  // pendingRoute, so listeners in one scene don't react to URLs that
  // landed in another.
  @State private var routeManager = RouteManager()

  init(database: Database) {
    _ = AppSettings.shared
    // Route network byte counts into the persisted transfer meter.
    TransferStatistics.install()
    self.database = database
    let manager = ConnectionManager(database: database)
    _manager = State(wrappedValue: manager)
    let errorController = ErrorController()
    let networkMonitor = NetworkMonitor()
    // Raw path cost, read live so the engine's observation-driven initial
    // sync gates on the current link — same source `isUnmetered` below reads,
    // combined per-server via `SyncCondition` rather than folded here.
    _syncEngine = State(
      wrappedValue: SyncEngine(
        database: database,
        manager: manager,
        pathCost: { [weak networkMonitor] in
          guard let networkMonitor else { return (isExpensive: true, isConstrained: true) }
          return (networkMonitor.isExpensive, networkMonitor.isConstrained)
        }))
    errorController.suppressBannerCoveredErrors(networkMonitor: networkMonitor)
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

  /// The gate for the *active* server's heavy proactive fill (cheap reconcile
  /// sweeps run regardless). Wi‑Fi‑ish by default, unless the active server has
  /// been opted in to cellular; Low Data Mode always wins. See `SyncCondition`.
  /// The inactive-server sweep resolves this per-server itself — pass it raw
  /// path cost (`networkMonitor.isExpensive`/`.isConstrained`), not this.
  private var isUnmetered: Bool {
    SyncCondition(
      isExpensive: networkMonitor.isExpensive, isConstrained: networkMonitor.isConstrained,
      syncOverCellular: manager.activeSyncOverCellular
    ).allowsProactiveSync
  }

  /// Fire-and-forget the proactive *Entire library* fill (no-op when disabled,
  /// metered, or already covered). Used after the initial-launch sync; the
  /// scenePhase path chains it after `sync()` directly.
  private func kickLibraryFill(_ store: DocumentStore, force: Bool = false) {
    Task {
      await store.runProactiveFill(unmetered: isUnmetered, force: force)
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
      guard let stored = manager.storedConnection else {
        Logger.api.error("Active connection has no stored connection record")
        storeReady = false
        showLoginScreen = true
        showLoadingScreen = false
        return
      }

      // The store assembles the active server's stack itself (identical to the
      // per-server stacks the SyncEngine builds for inactive servers), so both the
      // reuse and the first-launch path go through one entry point. A fresh store
      // starts on `NullRepository` and is only published once `activate` succeeds —
      // otherwise a failed login would leave a detached store installed.
      let isNewStore = store == nil
      let target = store ?? DocumentStore(repository: NullRepository())

      if !isNewStore {
        await sleep(.seconds(0.1))
        target.events.emit(.repositoryWillChange)
        await sleep(.seconds(0.3))
      }

      do {
        try await target.activate(connection: stored, database: database, manager: manager)
      } catch {
        Logger.api.error("Could not build repository for active connection: \(error)")
        storeReady = false
        showLoginScreen = true
        showLoadingScreen = false
        return
      }

      if isNewStore {
        store = target
        observeFriendlyName(on: target)
      }

      storeReady = true
      // Register (or refresh) the UI graph with the background-sync coordinator
      // *before* kicking the store's own sync: registration cancels-and-awaits
      // any in-flight headless background run, so two CachingRepository
      // instances never execute against the same server.
      await BackgroundSyncCoordinator.shared.register(
        database: database, manager: manager, syncEngine: syncEngine, store: target)
      try? await target.sync()
      target.startTaskPolling()
      kickLibraryFill(target)
      if !isNewStore {
        await sleep(.seconds(0.3))
      }
      showLoadingScreen = false
      showLoginScreen = false
    } else {
      storeReady = false
      Logger.shared.trace("App does not have any active connection, show login screen")
      // Still hand the graph over (store: nil): background runs can keep the
      // configured-but-inactive servers warm while the user is logged out.
      await BackgroundSyncCoordinator.shared.register(
        database: database, manager: manager, syncEngine: syncEngine, store: nil)
      showLoginScreen = true
      showLoadingScreen = false
    }
  }

  private func observeFriendlyName(on store: DocumentStore) {
    // Forwards the server's PAPERLESS_APP_TITLE (settings.appTitle) to the
    // active connection. The nil-guard drops resets from store.clear() so
    // they don't wipe out a previously stored friendly name. setFriendlyName
    // is already idempotent, so no explicit dedup is needed.
    //
    // Held as a `Subscription` rather than a bare `Task` so it cancels when
    // this view's `@State` storage is freed, the way the `AnyCancellable` it
    // replaced did.
    friendlyNameSubscription?.cancel()
    friendlyNameSubscription = Subscription(
      Task { @MainActor [manager] in
        while !Task.isCancelled {
          let (stream, continuation) = AsyncStream<Void>.makeStream()
          withObservationTracking {
            _ = store.settings.appTitle
          } onChange: {
            continuation.yield()
            continuation.finish()
          }
          if let title = store.settings.appTitle {
            manager.setFriendlyName(title)
          }
          for await _ in stream { break }
        }
      })
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
            .environment(store!)
            .environment(manager)
            .safeAreaInset(edge: .bottom, spacing: 0) {
              NeedsAuthBanner()
                .environment(manager)
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

    // Only one sheet can be presented from a given view at a time. When the
    // settings sheet is up, the re-auth request it raises is presented by
    // SettingsView instead — otherwise the request would be dropped and the
    // re-auth button there would look dead.
    .sheet(
      isPresented: Binding(
        get: { manager.reauthRequested != nil && !showSettings },
        set: { presented in
          if !presented { manager.cancelReauthRequest() }
        })
    ) {
      if let id = manager.reauthRequested,
        let stored = manager.connections[id]
      {
        ReauthSheet(stored: stored)
          .environment(manager)
          .environmentObject(errorController)
          .environment(networkMonitor)
      }
    }

    .fullScreenCover(isPresented: $releaseNotesModel.showReleaseNotes) {
      ReleaseNotesCoverView(releaseNotesModel: $releaseNotesModel)
    }

    .sheet(isPresented: $showSettings) {
      if let store {
        SettingsView(database: database)
          .environment(manager)
          .environment(store)
          .environment(networkMonitor)
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

      // Begin observing the server table for newly-added servers, and warm every
      // inactive server's cache (the active server was just synced above).
      syncEngine.start()
      Task {
        await syncEngine.syncInactiveServers(
          isExpensive: networkMonitor.isExpensive, isConstrained: networkMonitor.isConstrained)
      }
    }

    .onEvent(from: manager.events) { event in
      switch event {
      case .connectionChange(let animated):
        Task {
          await refreshConnection(animated: animated)
          // The just-deactivated server is now inactive: sweep it (and the rest).
          await syncEngine.syncInactiveServers(
            isExpensive: networkMonitor.isExpensive, isConstrained: networkMonitor.isConstrained)
        }
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
        TransferStatistics.shared.persist()
        BackgroundTaskManager.scheduleAll()

      case .active:
        store?.startTaskPolling()

        Logger.shared.notice("App becomes active")

        // Cache-first: foreground refresh syncs the element cache silently, then
        // (when "Entire library" is on) tops up the proactive fill — a no-op once
        // the coverage marker is fresh. The initial launch sync is handled by
        // refreshConnection.
        if !initialDisplay {
          if let store {
            Task {
              try? await store.sync()
              await store.runProactiveFill(unmetered: isUnmetered)
            }
          }
          // Warm the inactive servers alongside the active refresh.
          Task {
            await syncEngine.syncInactiveServers(
              isExpensive: networkMonitor.isExpensive, isConstrained: networkMonitor.isConstrained)
          }
        }

        Task { await biometricLockManager.unlockIfEnabled() }

      default:
        break
      }
    }

    .onOpenURL(perform: handleUrlOpen)
    .environment(routeManager)
    .appOverlays(
      errorController: errorController,
      networkMonitor: networkMonitor,
      database: database
    )
  }
}

@main
struct swift_paperlessApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @State private var bootstrap = DatabaseBootstrap()

  var body: some Scene {
    WindowGroup {
      DatabaseBootstrapView(bootstrap: bootstrap)
    }
  }
}
