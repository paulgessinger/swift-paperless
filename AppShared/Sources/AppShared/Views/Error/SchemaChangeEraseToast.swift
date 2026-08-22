//
//  SchemaChangeEraseToast.swift
//  AppShared
//
//  Surfaces `Database.didEraseForSchemaChangeAtLaunch` (DEBUG-only
//  `eraseDatabaseOnSchemaChange`, see `Migrations.migrator`) as a toast on
//  the launch it fires on, so a developer who jumped to a revision whose
//  migrator doesn't know about a migration the on-disk database already has
//  applied sees "this wasn't a bug, the local database just got reset" —
//  rather than a silently-emptied database and no explanation.
//
//  Must be installed inside a parent that called `.installToast(...)`.
//

import Persistence
import SwiftUI
import Toasts

public struct SchemaChangeEraseToastBridge: ViewModifier {
  // Passed in explicitly, same reason as `OfflineToastBridge.networkMonitor`:
  // `.appOverlays(...)` is applied as the outermost modifier on the app's
  // body, so an `@Environment` read here would look up the value at a
  // position *above* where it's set.
  let database: Database
  @Environment(\.presentToast) private var presentToast
  @State private var shown = false

  public init(database: Database) {
    self.database = database
  }

  public func body(content: Content) -> some View {
    content
      .task {
        guard !shown, database.didEraseForSchemaChangeAtLaunch else { return }
        shown = true
        // Debug-only diagnostic text, deliberately not localized (never seen
        // by a real user — `didEraseForSchemaChangeAtLaunch` is `false` in
        // Release, where `eraseDatabaseOnSchemaChange` is never enabled).
        presentToast(
          ToastValue(
            icon: Image(systemName: "ladybug.fill")
              .foregroundStyle(.orange),
            message:
              "DEBUG: local database schema changed since last launch — GRDB wiped and recreated it. Not a bug; reconnect your server(s).",
            duration: 10
          )
        )
      }
  }
}
