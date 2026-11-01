//
//  swift_paperlessApp.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import AppShared
import AppViews
import Common
import DataModel
import Networking
import Persistence
import SwiftUI
import os

struct MainView: View {
  @State private var showLoginScreen = false

  @State private var storeReady = false
  /// The server `refreshConnection` is putting the store on. The document UI
  /// shows only once the store has arrived there, so an outgoing server's
  /// documents never meet the incoming server's connection mid-switch.
  @State private var requestedServerID: UUID?
  @State private var store: DocumentStore?
  @State private var initialDisplay = true
  @State private var showSettings = false

  // Process-wide, shared with every other window and the App Intents.
  private let stack: AppStack
  private var manager: ConnectionManager { stack.connectionManager }
  private var sessionRegistry: ServerSessionRegistry { stack.sessionRegistry }
  private var syncEngine: SyncEngine { stack.syncEngine }
  private var networkMonitor: NetworkMonitor { stack.networkMonitor }

  @State private var friendlyNameSubscription: Subscription?

  @StateObject private var errorController: ErrorController

  @Environment(\.scenePhase) var scenePhase

  @State private var releaseNotesModel = ReleaseNotesViewModel()

  /// A new user sees onboarding ahead of the login screen rather than release
  /// notes after it. Installs that already have a server skip it.
  @State private var showOnboarding: Bool

  @StateObject private var biometricLockManager: BiometricLockManager

  // Per-scene routing state. Owning this here (instead of a global
  // singleton) means each window in a multi-window setup has its own
  // pendingRoute, so listeners in one scene don't react to URLs that
  // landed in another.
  @State private var routeManager = RouteManager()

  init(stack: AppStack) {
    _ = AppSettings.shared
    // Route network byte counts into the persisted transfer meter.
    TransferStatistics.install()
    self.stack = stack
    _showOnboarding = State(
      initialValue: AppSettings.shared.lastAppVersion == nil
        && stack.connectionManager.connection == nil)
    let errorController = ErrorController()
    errorController.installConnectivityPolicy(networkMonitor: stack.networkMonitor)
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
          await refreshConnection()
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

  /// What a proactive pass on the *active* server should run right now — asked
  /// of `SyncPlan`, the same way the inactive-server sweep asks it, so the
  /// server on screen is planned by the same rule as the ones that aren't.
  /// The cheap phases are always in; `.fill` depends on the link and this
  /// server's own cellular opt-in (Low Data Mode always wins — see
  /// `SyncCondition`).
  ///
  /// The sweep resolves its servers' conditions itself, from its own live cost
  /// read — it needs nothing from here.
  private var activePhases: SyncPhases {
    SyncPlan.phases(
      isEntireLibrary: manager.activeOfflineBrowsingMode == .entireLibrary,
      condition: SyncCondition(
        cost: networkMonitor.cost, syncOverCellular: manager.activeSyncOverCellular))
  }

  /// Whether iOS launched the process for a background task, with no scene on
  /// screen. That task syncs every server itself, and the first `.active`
  /// runs the foreground pass, so the launch path leaves its network work to
  /// those.
  private var isInBackground: Bool {
    UIApplication.shared.applicationState == .background
  }

  /// Fire-and-forget the proactive *Entire library* fill (no-op when disabled,
  /// metered, or already covered). Used after the initial-launch sync; the
  /// scenePhase path chains it after `sync()` directly.
  private func kickLibraryFill(_ store: DocumentStore, force: Bool = false) {
    Task {
      await store.fillIfEnabled(phases: activePhases, force: force)
    }
  }

  /// Point the store at the active connection and show it.
  ///
  /// Activation reads the server's stored versions and builds its repository
  /// locally, so the documents appear from the cache straight away; the sync
  /// runs behind them.
  private func refreshConnection() async {
    Logger.api.info("Connection info changed, reloading!")
    guard let conn = manager.connection else {
      storeReady = false
      Logger.shared.trace("App does not have any active connection, show login screen")
      showLoginScreen = true
      return
    }

    Logger.api.info("Valid connection from connection manager: \(String(describing: conn))")
    guard let stored = manager.storedConnection else {
      Logger.api.error("Active connection has no stored connection record")
      storeReady = false
      showLoginScreen = true
      return
    }

    // The store activates onto the *same* session the SyncEngine sweeps this
    // server with, so the active and inactive paths share one repository rather
    // than racing two. A fresh store starts serverless (`NullRepository`) and is
    // only published once `activate` succeeds — otherwise a failed login would
    // leave a detached store installed.
    let isNewStore = store == nil
    let target = store ?? DocumentStore(registry: sessionRegistry)
    requestedServerID = stored.id

    do {
      try await target.activate(connection: stored)
    } catch {
      Logger.api.error("Could not build repository for active connection: \(error)")
      storeReady = false
      showLoginScreen = true
      return
    }

    if isNewStore {
      store = target
      observeFriendlyName(on: target)
    }

    storeReady = true
    showLoginScreen = false

    guard !isInBackground else {
      Logger.sync.info("Launched in the background: launch sync left to the first activation")
      return
    }
    Task {
      try? await target.sync()
      target.startTaskPolling()
      kickLibraryFill(target)
    }
  }

  private func observeFriendlyName(on store: DocumentStore) {
    // Forwards the server's PAPERLESS_APP_TITLE (settings.appTitle) to the
    // active connection. The nil-guard drops resets from store.clear() so
    // they don't wipe out a previously stored friendly name. setFriendlyName
    // is already idempotent, so no explicit dedup is needed.
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
        if manager.connection != nil, storeReady, let store,
          store.activeServerID == requestedServerID
        {
          // A server switch remounts the document UI: navigation, selection
          // and filters belong to the outgoing server. Keyed on the store's
          // server, which changes only once the repository has been swapped.
          DocumentView(showSettings: $showSettings)
            .id(store.activeServerID)
            .transition(.opacity)
            .environment(store)
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
        } else {
          // Until the first activation, which is local and near-instant once
          // the server's versions are stored.
          Color(uiColor: .systemBackground)
            .ignoresSafeArea()
        }
      }
    }
    .animation(.default, value: storeReady)
    .animation(.default, value: store?.activeServerID)

    .environmentObject(errorController)
    .environmentObject(biometricLockManager)
    .environment(networkMonitor)

    .fullScreenCover(isPresented: $showLoginScreen) {
      Group {
        if showOnboarding {
          WhatsNewDeckView(
            deck: .onboarding, finishLabel: String(localized: .login(.onboardingGetStarted))
          ) {
            // Moving on with the toggle off is a decision too, so nobody gets
            // asked again.
            if AppFeatures.enabled(.telemetry), AppSettings.shared.telemetryOptIn == nil {
              AppSettings.shared.telemetryOptIn = false
            }
            releaseNotesModel.showReleaseNotes = false
            withAnimation { showOnboarding = false }
          }
          .transition(.opacity)
        } else {
          LoginView(connectionManager: manager)
            .environmentObject(errorController)
        }
      }
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

    .fullScreenCover(
      isPresented: Binding(
        get: { releaseNotesModel.showReleaseNotes && !showOnboarding },
        set: { releaseNotesModel.showReleaseNotes = $0 })
    ) {
      ReleaseNotesCoverView(releaseNotesModel: $releaseNotesModel)
    }

    .sheet(isPresented: $showSettings) {
      if let store {
        SettingsView()
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
      await refreshConnection()
      initialDisplay = false

      // Begin observing the server table for newly-added servers, and warm every
      // inactive server's cache (the active server was just synced above).
      syncEngine.start()
      stack.runLaunchMaintenance()
      // A window emptied while the app was not running is filled again
      // without waiting for a sync.
      Task {
        await stack.suspension.performBackgroundWork {
          await stack.fileDownloader?.refillAllServers()
        }
      }
      if !isInBackground {
        Task {
          await syncEngine.syncInactiveServers()
        }
      }
    }

    .onEvent(from: manager.events) { event in
      switch event {
      case .connectionChange:
        Task {
          await refreshConnection()
          // The just-deactivated server is now inactive: sweep it (and the rest).
          await syncEngine.syncInactiveServers()
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
              await store.fillIfEnabled(phases: activePhases)
            }
          }
          // Warm the inactive servers alongside the active refresh.
          Task {
            await syncEngine.syncInactiveServers()
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
      database: stack.database
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
