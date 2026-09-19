//
//  SyncFailuresSection.swift
//  AppShared
//
//  The Offline & Sync screen's "Sync errors" section: which parts of the active
//  server's last sync failed, why, and when.
//
//  Separate from the per-view "Sync problems" list above it, which is fed from
//  `query_sync_error` and only covers saved views the *Entire library* fill
//  couldn't page. This one covers everything else — a server erroring on the
//  permissions fetch, a reconcile sweep, the element sync — and shows in both
//  offline-browsing modes (#663). What gets in is `SyncFailureClass`'s call;
//  being offline never does.
//

import Networking
import SwiftUI

struct SyncFailuresSection: View {
  let failures: [SyncFailureLedger.Entry]

  var body: some View {
    if !failures.isEmpty {
      Section {
        ForEach(failures) { failure in
          VStack(alignment: .leading, spacing: 2) {
            Text(Self.label(for: failure.site))
            Text(failure.message)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(3)
            HStack(spacing: 4) {
              // Live-updating, like the other timestamps on this screen.
              Text(failure.failedAt, style: .relative)
              if failure.consecutiveFailures > 1 {
                Text(verbatim: "·")
                Text(.settings(.offlineSyncFailureRepeated(failure.consecutiveFailures)))
              }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
          }
        }
      } header: {
        Label(
          String(localized: .settings(.offlineSyncFailuresHeader)),
          systemImage: "exclamationmark.triangle")
      } footer: {
        Text(.settings(.offlineSyncFailuresDescription))
      }
    }
  }

  private static func label(for site: SyncFailureSite) -> LocalizedStringResource {
    switch site {
    case .connection: .settings(.offlineSyncFailureSiteConnection)
    case .uiSettings: .settings(.offlineSyncFailureSiteUISettings)
    case .elements: .settings(.offlineSyncFailureSiteElements)
    case .deletions: .settings(.offlineSyncFailureSiteDeletions)
    case .changes: .settings(.offlineSyncFailureSiteChanges)
    case .membership: .settings(.offlineSyncFailureSiteMembership)
    case .reachability: .settings(.offlineSyncFailureSiteReachability)
    case .libraryFill: .settings(.offlineSyncFailureSiteLibraryFill)
    case .detailFill: .settings(.offlineSyncFailureSiteDetailFill)
    }
  }
}
