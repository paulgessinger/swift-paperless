//
//  LoginView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.08.2024.
//

import AppShared
import AppViews
import DataModel
import Foundation
import Networking
import Persistence
import SwiftUI
import os

/// Screens reachable from the login screen's ⋯ menu.
private enum LoginDetail: Identifiable {
  case extraHeaders
  case identities
  case logs

  var id: Self { self }
}

@MainActor
private struct LoginDetailView: View {
  let detail: LoginDetail
  let connectionManager: ConnectionManager

  @Environment(LoginViewModel.self) private var viewModel
  @Environment(IdentityManager.self) private var identityManager

  var body: some View {
    @Bindable var viewModel = viewModel

    NavigationStack {
      Group {
        switch detail {
        case .extraHeaders:
          ExtraHeadersView(headers: $viewModel.extraHeaders)
        case .identities:
          TLSListView(identityManager: identityManager)
        case .logs:
          LogView(connectionManager: connectionManager)
        }
      }
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          CancelIconButton()
        }
      }
    }
  }
}

struct LoginFooterView<Content: View>: View {
  var systemImage: String
  var content: () -> Content

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Image(systemName: systemImage)
      VStack(alignment: .leading) {
        content()
      }
    }
    .font(.footnote)
  }
}

@MainActor
struct LoginView: View {
  var connectionManager: ConnectionManager
  var initial: Bool = true

  @State private var viewModel: LoginViewModel
  @State private var identityManager = IdentityManager()

  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var errorController: ErrorController

  @State private var detail: LoginDetail?
  @State private var stage: LoginStage
  @State private var showSuccessOverlay = false
  @State private var keyboardVisible: Bool

  init(
    connectionManager: ConnectionManager,
    initial: Bool = true,
    viewModel: LoginViewModel = LoginViewModel(),
    stage: LoginStage = .connection,
    keyboardVisible: Bool = false
  ) {
    self.connectionManager = connectionManager
    self.initial = initial
    _viewModel = State(initialValue: viewModel)
    _stage = State(initialValue: stage)
    _keyboardVisible = State(initialValue: keyboardVisible)
  }

  private func loginSucceeded(stored: StoredConnection) {
    Haptics.shared.notification(.success)

    showSuccessOverlay = true
    Task {
      try? await Task.sleep(for: .seconds(2))
      if !initial {
        dismiss()
        try? await Task.sleep(for: .seconds(0.2))
      }
      do {
        try connectionManager.login(stored)
      } catch {
        // The credentials were valid but the row didn't reach the DB. Say so
        // rather than dropping the user back to a login screen that looks
        // like it just ignored them.
        Logger.shared.error("Storing the logged-in connection failed: \(error)")
        errorController.push(error: error)
      }
    }
  }

  private var moreMenu: some View {
    Menu {
      Button {
        detail = .extraHeaders
      } label: {
        Label(markdown: .login(.extraHeaders), systemImage: "list.bullet.rectangle")
      }
      Button {
        detail = .identities
      } label: {
        Label(localized: .settings(.identities), systemImage: "lock")
      }
      Divider()
      Button {
        detail = .logs
      } label: {
        Label(localized: .settings(.logs), systemImage: "text.word.spacing")
      }
    } label: {
      Label(
        String(localized: .login(.moreToolbarButtonLabel)), systemImage: "ellipsis.circle")
    }
  }

  var body: some View {
    NavigationStack {
      VStack {
        switch stage {
        case .connection:
          ConnectionStageView(stage: $stage)
            .transition(.move(edge: .leading))
        case .credentials:
          CredentialsStageView(onSuccess: loginSucceeded)
            .transition(.move(edge: .trailing))
        }
      }
      .animation(.spring(duration: 0.3), value: stage)

      .navigationBarTitleDisplayMode(.inline)

      .toolbar {
        // With the keyboard up, the step selector moves into the navigation
        // bar so the form keeps the space above the keyboard.
        if keyboardVisible {
          ToolbarItem(placement: .principal) {
            StageSelection(stage: $stage, compact: true)
              .fixedSize()
          }
        } else if initial {
          ToolbarItem(placement: .principal) {
            LogoTitle()
              .fixedSize()
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          moreMenu
        }
      }

      .safeAreaInset(edge: .top) {
        if !keyboardVisible {
          StageSelection(stage: $stage)
            .padding(.top, 5)
            .frame(maxWidth: .infinity)
            .padding(.bottom)
            .transition(.opacity)
        }
      }
      .animation(.spring(duration: 0.25), value: keyboardVisible)
      .trackKeyboardState(isVisible: $keyboardVisible)

      .if(!initial) { view in
        view
          .navigationTitle(String(localized: .login(.additionalTitle)))

          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              CancelIconButton()
            }
          }
      }
    }

    .sheet(item: $detail) { detail in
      LoginDetailView(detail: detail, connectionManager: connectionManager)
    }

    .successOverlay(isPresented: $showSuccessOverlay, duration: 2.0) {
      Text(.login(.success))
    }

    .environment(viewModel)
    .environment(identityManager)
  }
}

// - MARK: Previews

/// Builds a login screen in a fixed state. Previews cannot show the software
/// keyboard, so `keyboard: true` forces the layout used while it is up.
@MainActor
private func loginPreview(
  stage: LoginStage = .connection,
  initial: Bool = true,
  keyboard: Bool = false,
  configure: (LoginViewModel) -> Void = { _ in }
) -> some View {
  let viewModel = LoginViewModel()
  configure(viewModel)
  return LoginView(
    connectionManager: ConnectionManager(database: try! Database.inMemory(), previewMode: true),
    initial: initial,
    viewModel: viewModel,
    stage: stage,
    keyboardVisible: keyboard
  )
  .environmentObject(ErrorController())
}

@MainActor
private func validServer(_ viewModel: LoginViewModel) {
  viewModel.scheme = .https
  viewModel.url = "paperless.example.com"
  viewModel.loginState = .valid
}

private let previewProviders = [
  OIDCProvider(
    id: "authentik", name: "Authentik", flows: ["provider_redirect", "provider_token"],
    clientId: "paperless", openidConfigurationUrl: nil)
]

#Preview("1 Connection · empty") {
  loginPreview()
}

#Preview("1 Connection · checking") {
  loginPreview { viewModel in
    viewModel.url = "paperless.example.com"
    viewModel.loginState = .checking
  }
}

#Preview("1 Connection · valid") {
  loginPreview(configure: validServer)
}

#Preview("1 Connection · HTTP warning") {
  loginPreview { viewModel in
    viewModel.scheme = .http
    viewModel.url = "paperless.example.com:8000"
    viewModel.loginState = .valid
  }
}

#Preview("1 Connection · error") {
  loginPreview { viewModel in
    viewModel.url = "paperless.example.com"
    viewModel.loginState = .error(.request(.unsupportedVersion(sentVersion: nil)))
  }
}

#Preview("1 Connection · keyboard") {
  loginPreview(keyboard: true) { viewModel in
    viewModel.url = "paperless.exam"
    viewModel.loginState = .checking
  }
}

#Preview("1 Connection · add server") {
  loginPreview(initial: false, configure: validServer)
}

#Preview("2 Credentials · password") {
  loginPreview(stage: .credentials) { viewModel in
    validServer(viewModel)
    viewModel.username = "paperless"
  }
}

#Preview("2 Credentials · password + SSO") {
  loginPreview(stage: .credentials) { viewModel in
    validServer(viewModel)
    viewModel.oidcProviders = previewProviders
  }
}

#Preview("2 Credentials · password + SSO, keyboard") {
  loginPreview(stage: .credentials, keyboard: true) { viewModel in
    validServer(viewModel)
    viewModel.oidcProviders = previewProviders
    viewModel.username = "paper"
  }
}

#Preview("2 Credentials · validating") {
  loginPreview(stage: .credentials) { viewModel in
    validServer(viewModel)
    viewModel.username = "paperless"
    viewModel.password = "password"
    viewModel.credentialState = .validating
  }
}

#Preview("2 Credentials · rejected") {
  loginPreview(stage: .credentials) { viewModel in
    validServer(viewModel)
    viewModel.username = "paperless"
    viewModel.password = "password"
    viewModel.credentialState = .error(.invalidLogin(detail: nil))
  }
}

#Preview("2 Credentials · 2FA code") {
  loginPreview(stage: .credentials) { viewModel in
    validServer(viewModel)
    viewModel.username = "paperless"
    viewModel.password = "password"
    viewModel.otpEnabled = true
  }
}

#Preview("2 Credentials · token") {
  loginPreview(stage: .credentials) { viewModel in
    validServer(viewModel)
    viewModel.credentialMode = .token
  }
}

#Preview("2 Credentials · token rejected") {
  loginPreview(stage: .credentials) { viewModel in
    validServer(viewModel)
    viewModel.credentialMode = .token
    viewModel.token = "0123456789abcdef"
    viewModel.credentialState = .error(.invalidToken)
  }
}

#Preview("2 Credentials · no credentials") {
  loginPreview(stage: .credentials) { viewModel in
    validServer(viewModel)
    viewModel.credentialMode = .none
  }
}

#Preview("2 Credentials · OpenID Connect") {
  loginPreview(stage: .credentials) { viewModel in
    validServer(viewModel)
    viewModel.credentialMode = .oidc
    viewModel.oidcProviders = previewProviders
  }
}

#Preview("2 Credentials · OpenID Connect unavailable") {
  loginPreview(stage: .credentials) { viewModel in
    validServer(viewModel)
    viewModel.credentialMode = .oidc
  }
}

#Preview("2 Credentials · OpenID Connect 2FA") {
  loginPreview(stage: .credentials) { viewModel in
    validServer(viewModel)
    viewModel.credentialMode = .oidc
    viewModel.oidcProviders = previewProviders
    viewModel.otpEnabled = true
  }
}

#Preview("2 Credentials · plain HTTP") {
  loginPreview(stage: .credentials) { viewModel in
    viewModel.scheme = .http
    viewModel.url = "192.168.1.20:8000"
    viewModel.loginState = .valid
  }
}
