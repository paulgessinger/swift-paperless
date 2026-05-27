//
//  ReauthSheet.swift
//  swift-paperless
//
//  Scoped re-authentication sheet for an existing connection. Reuses the
//  existing `CredentialsStageView` and `LoginViewModel.validateCredentials()`
//  flow — the model creates a fresh `StoredConnection` with a new UUID, but
//  the Keychain write at `setToken(token)` happens at
//  `(service: url, account: username)`, which is the same key the existing
//  StoredConnection row reads from. So a successful re-auth on the same
//  identity overwrites the stale token in place and the row stays valid.
//
//  We then verify the identity (URL + username) and either clear the
//  needs-auth flag or surface a mismatch error.
//

import AppShared
import Common
import DataModel
import Networking
import SwiftUI
import os

@MainActor
struct ReauthSheet: View {
  let stored: StoredConnection

  @EnvironmentObject private var connectionManager: ConnectionManager
  @EnvironmentObject private var errorController: ErrorController
  @Environment(\.dismiss) private var dismiss

  @State private var viewModel = LoginViewModel()
  @State private var identityManager = IdentityManager()
  @State private var mismatchMessage: String?

  private func prepopulate() {
    // Strip scheme into viewModel.scheme; viewModel.url holds the host+path.
    let absolute = stored.url.absoluteString
    if absolute.hasPrefix("https://") {
      viewModel.scheme = .https
      viewModel.url = String(absolute.dropFirst("https://".count))
    } else if absolute.hasPrefix("http://") {
      viewModel.scheme = .http
      viewModel.url = String(absolute.dropFirst("http://".count))
    } else {
      viewModel.url = absolute
    }

    viewModel.username = stored.user.username
    viewModel.extraHeaders = stored.extraHeaders
    if let identityName = stored.identity {
      viewModel.selectedIdentity = identityManager.identities.first {
        $0.name == identityName
      }
    }

    // Kick the URL probe so the OIDC client (if any) is initialised before
    // the credentials stage shows the OIDC button.
    viewModel.onChangeUrl(immediate: true)
  }

  private func handleSuccess(_ newStored: StoredConnection) {
    // The new StoredConnection has a fresh UUID; we discard it. What matters
    // is that validateCredentials() wrote the new token to Keychain at
    // (service: url, account: username) — same key the original row reads
    // from. Now verify identity hasn't drifted.
    let originalURL = stored.url.absoluteString
    let newURL = newStored.url.absoluteString
    let usernameMatches = newStored.user.username == stored.user.username
    let urlMatches = newURL == originalURL

    if !usernameMatches || !urlMatches {
      Logger.api.warning(
        "Re-auth identity mismatch: url \(originalURL) -> \(newURL), username \(stored.user.username) -> \(newStored.user.username)"
      )
      mismatchMessage = String(localized: .app(.reauthIdentityMismatch))
      // Do not clear the needs-auth flag — the user must remove and re-add
      // the server explicitly to change identity.
      return
    }

    Logger.api.info(
      "Re-auth succeeded for connection \(stored.id, privacy: .private(mask: .hash))")
    connectionManager.clearNeedsAuth(for: stored.id)
    connectionManager.cancelReauthRequest()
    // Trigger a connection refresh so the app shell rebuilds ApiRepository
    // with the now-fresh token. The init-time header probe runs again with
    // valid auth, picking up backendVersion and the real apiVersion (rather
    // than whatever the iteration probe inferred from the bad-token session
    // — which is unauth-correct but missing backendVersion, so
    // supports(feature:) is conservatively false until this fires).
    connectionManager.setActiveConnection(id: stored.id, animated: false)
    dismiss()
  }

  var body: some View {
    NavigationStack {
      CredentialsStageView(onSuccess: handleSuccess) {
        ReauthPreamble(stored: stored, mismatchMessage: mismatchMessage)
      }
      .navigationTitle(Text(.app(.reauthSheetTitle)))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          CancelIconButton()
        }
      }
      .environment(viewModel)
      .environment(identityManager)
    }
    .task(id: stored.id) { prepopulate() }
  }
}

private struct ReauthPreamble: View {
  let stored: StoredConnection
  let mismatchMessage: String?

  var body: some View {
    CustomSection {
      VStack {
        if let mismatchMessage {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.red)
            Text(mismatchMessage)
              .font(.footnote)
            Spacer(minLength: 0)
          }
          .padding(.vertical, 8)
        }

        VStack(alignment: .leading, spacing: 6) {
          Text(.app(.reauthSheetSubtitle))
            .font(.footnote)
            .foregroundStyle(.secondary)
          Text(stored.label)
            .font(.footnote.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      .padding(.vertical)
    }
  }
}

// MARK: - Previews

#Preview("Reauth") {
  @Previewable @StateObject var connectionManager = ConnectionManager(previewMode: true)
  @Previewable @StateObject var errorController = ErrorController()

  let stored = StoredConnection(
    url: URL(string: "https://paperless.example.com")!,
    extraHeaders: [],
    user: User(id: 1, isSuperUser: false, username: "admin"),
    friendlyName: "Home Server"
  )

  ReauthSheet(stored: stored)
    .environmentObject(connectionManager)
    .environmentObject(errorController)
}
