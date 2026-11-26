//
//  CredentialsStageView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.02.25.
//

import AppShared
import AppViews
import AuthenticationServices
import Networking
import NukeUI
import SwiftUI
import os

private typealias Section = CustomSection

private enum CredentialField: Hashable {
  case username
  case password
  case token
  case otp
}

struct CredentialsStageView<Preamble: View>: View {
  @Environment(LoginViewModel.self) private var viewModel

  var onSuccess: (StoredConnection) -> Void
  @ViewBuilder var preamble: () -> Preamble
  /// Show the server being signed in to; off when the preamble names it already.
  private var showsServer: Bool

  @FocusState private var focus: CredentialField?

  init(
    onSuccess: @escaping (StoredConnection) -> Void,
    @ViewBuilder preamble: @escaping () -> Preamble
  ) {
    self.onSuccess = onSuccess
    self.preamble = preamble
    showsServer = false
  }

  fileprivate init(
    onSuccess: @escaping (StoredConnection) -> Void,
    showsServer: Bool,
    @ViewBuilder preamble: @escaping () -> Preamble
  ) {
    self.onSuccess = onSuccess
    self.preamble = preamble
    self.showsServer = showsServer
  }

  var loginEnabled: Bool {
    if viewModel.credentialState == .validating {
      return false
    }

    switch viewModel.credentialMode {
    case .usernameAndPassword:
      var valid = !viewModel.username.isEmpty && !viewModel.password.isEmpty
      if viewModel.otpEnabled {
        valid = valid && otpValid
      }
      return valid
    case .token:
      return !viewModel.token.isEmpty
    case .oidc:
      if viewModel.otpEnabled {
        // A second factor is pending; only allow submission once the code
        // looks valid.
        return otpValid
      }
      return true
    case .none:
      return true
    }
  }

  private func validate() {
    guard loginEnabled else { return }
    focus = nil
    Logger.shared.info("Attempting to validate the credentials")
    Task {
      // Getting nil here means we got an error, but the view model handles this internally
      if let stored = await viewModel.validateCredentials() {
        onSuccess(stored)
      } else {
        Logger.shared.error("Got error validating credentials")
      }
    }
  }

  /// Single sign-on is offered above the password fields when the server has it.
  private var offersSSO: Bool {
    viewModel.credentialMode == .usernameAndPassword && !viewModel.otpEnabled
      && !viewModel.oidcProviders.isEmpty
  }

  /// The OIDC provider buttons start that login themselves, except while a
  /// second factor is pending, where the regular button submits the code.
  private var showsLoginButton: Bool {
    viewModel.credentialMode != .oidc || viewModel.otpEnabled
  }

  @ViewBuilder
  private var button: some View {
    Button {
      validate()
    } label: {
      Group {
        switch viewModel.credentialState {
        case .validating:
          HStack {
            ProgressView()
            Text(.login(.buttonValidating))
          }
          .frame(maxWidth: .infinity, alignment: .center)
        default:
          Text(.login(.buttonLabel))
            .frame(maxWidth: .infinity, alignment: .center)
        }
      }
      .padding(.vertical, 10)
    }
    .id(viewModel.credentialMode)
    .apply {
      // Next to the SSO buttons, the password login is the secondary path.
      if offersSSO {
        $0.backport.glassButtonStyle(or: .bordered)
      } else {
        $0.backport.glassProminentButtonStyle(or: .borderedProminent)
      }
    }
    .disabled(!loginEnabled)
  }

  @ViewBuilder
  private func errorView(_ error: LoginError) -> some View {
    VStack {
      switch error {
      case .invalidToken:
        LoginFooterView(systemImage: "xmark") {
          switch viewModel.credentialMode {
          case .token:
            Text(.login(.errorTokenInvalid))
          case .usernameAndPassword:
            Text(.login(.errorTokenInvalidUsernamePassword))
          case .none:
            Text(.login(.errorNoCredentialsUnauthorized))
          case .oidc:
            Text(.login(.oidcError))
          }
        }
        .foregroundColor(.red)
      default:
        LoginFooterView(systemImage: "xmark") {
          error.presentation
        }
        .foregroundStyle(.red)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 32)
  }

  private var otpValid: Bool {
    OTPCode.isWellFormed(viewModel.otp)
  }

  private var server: some View {
    let secure = viewModel.scheme == .https
    return HStack(spacing: 4) {
      Image(systemName: secure ? "lock.fill" : "lock.open.fill")
        .foregroundStyle(secure ? Color.accentColor : .orange)
      Text(viewModel.url)
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .font(.footnote)
    .foregroundStyle(.secondary)
    .padding(.horizontal)
  }

  private var otherOptions: some View {
    Menu {
      ForEach(CredentialMode.allCases, id: \.self) { item in
        Button {
          viewModel.selectCredentialMode(item)
        } label: {
          if viewModel.credentialMode == item {
            Label(item.label, systemImage: "checkmark")
          } else {
            Text(item.label)
          }
        }
      }
    } label: {
      HStack(spacing: 4) {
        Text(.login(.otherSignInOptions))
        Image(systemName: "chevron.up.chevron.down")
          .font(.footnote)
      }
      .padding(.horizontal, 6)
    }
    .backport.glassButtonStyle(or: .bordered)
    .tint(.primary)
  }

  @ViewBuilder
  private var passwordSection: some View {
    @Bindable var viewModel = viewModel
    Section {
      VStack {
        TextField(.login(.username), text: $viewModel.username)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .textContentType(.username)
          .focused($focus, equals: .username)
          .submitLabel(.next)
          .onSubmit { focus = .password }
        Divider()
        SecureField(.login(.password), text: $viewModel.password)
          .textContentType(.password)
          .focused($focus, equals: .password)
          .submitLabel(.go)
          .onSubmit { validate() }
      }
      .padding(.vertical, 10)
    } header: {
      if offersSSO {
        Text(.login(.localAccount))
      } else {
        Text(.login(.credentials))
      }
    } footer: {
      LoginFooterView(systemImage: "info.circle") {
        Text(.login(.passwordStorageNotice))
      }
    }
  }

  @ViewBuilder
  private var tokenSection: some View {
    @Bindable var viewModel = viewModel
    Section {
      HStack {
        TextField(.login(.token), text: $viewModel.token)
          .font(.body.monospaced())
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .focused($focus, equals: .token)
          .submitLabel(.go)
          .onSubmit { validate() }
        PasteButton(payloadType: String.self) { strings in
          if let token = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines) {
            viewModel.token = token
          }
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.capsule)
      }
      .padding(.vertical, 6)
    } header: {
      Text(.login(.token))
    } footer: {
      LoginFooterView(systemImage: "info.circle") {
        CredentialMode.token.description
      }
    }
  }

  var body: some View {
    @Bindable var viewModel = viewModel
    ScrollView(.vertical) {
      VStack(spacing: 16) {
        preamble()

        if showsServer {
          server
        }

        VStack(spacing: 16) {
          switch viewModel.credentialMode {
          case .usernameAndPassword:
            if offersSSO {
              OIDCView(prominent: true, onSuccess: onSuccess)
            }

            passwordSection

            if viewModel.otpEnabled {
              OtpSection(code: $viewModel.otp, focus: $focus, onSubmit: validate)
            }

          case .token:
            tokenSection

          case .oidc:
            if viewModel.otpEnabled {
              // A second factor (TOTP) is pending from the OIDC login; the
              // provider buttons are replaced by the code input until the
              // code is confirmed.
              OtpSection(code: $viewModel.otp, focus: $focus, onSubmit: validate)
            } else {
              OIDCView(prominent: true, onSuccess: onSuccess)
            }

          case .none:
            LoginFooterView(systemImage: "info.circle") {
              CredentialMode.none.description
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
          }

          if case .error(let error) = viewModel.credentialState {
            errorView(error)
              .transition(.opacity)
          }

          otherOptions
            .padding(.top, 8)
        }
        .animation(.default, value: viewModel.credentialMode)
        .animation(.default, value: viewModel.credentialState)
      }
      .animation(.spring(duration: 0.3), value: viewModel.otpEnabled)
      .frame(maxWidth: .infinity)
      .padding(.bottom)
    }
    .scrollDismissesKeyboard(.interactively)

    // Pinned to the bottom so it rides on top of the keyboard instead of
    // scrolling underneath it.
    .keyboardBottomBar {
      if showsLoginButton {
        button
          .padding(.horizontal)
          .padding(.vertical, 8)
      }
    }

    .modifier(BackgroundColorModifier())
    .scrollBounceBehavior(.basedOnSize)
  }
}

extension CredentialsStageView where Preamble == EmptyView {
  init(onSuccess: @escaping (StoredConnection) -> Void) {
    self.init(onSuccess: onSuccess, showsServer: true, preamble: { EmptyView() })
  }
}

/// Validation shared by the credential-login and OIDC second-factor flows.
/// TOTP codes are 6 digits; allauth recovery codes are 8 digits.
private enum OTPCode {
  static func isWellFormed(_ code: String) -> Bool {
    let isDigits = (try? /^[0-9]*$/.wholeMatch(in: code)) != nil
    return isDigits && (code.count == 6 || code.count == 8)
  }

  /// Returns `new` if it is plausible OTP input (digits, at most 8), otherwise
  /// the previous value, so the text field only ever holds usable input.
  static func sanitized(_ new: String, fallback old: String) -> String {
    let isDigits = (try? /^[0-9]*$/.wholeMatch(in: new)) != nil
    if (!isDigits && !new.isEmpty) || new.count > 8 {
      return old
    }
    return new
  }
}

private struct OtpSection: View {
  @Binding var code: String
  var focus: FocusState<CredentialField?>.Binding
  var onSubmit: () -> Void

  var body: some View {
    Section {
      TextField(String("123456"), text: $code)
        .textContentType(.oneTimeCode)
        .keyboardType(.numberPad)
        .focused(focus, equals: .otp)
        .submitLabel(.go)
        .onChange(of: code) { old, new in
          code = OTPCode.sanitized(new, fallback: old)
        }
        .onSubmit(of: .text) { onSubmit() }
    } header: {
      Text(.login(.otp))
    } footer: {
      LoginFooterView(systemImage: "numbers.rectangle") {
        Text(.login(.otpDescription))
      }
    }
    .onAppear { focus.wrappedValue = .otp }
  }
}

private struct OIDCView: View {
  @Environment(LoginViewModel.self) private var viewModel
  @Environment(\.webAuthenticationSession) private var auth

  var prominent: Bool
  var onSuccess: (StoredConnection) -> Void

  private func validate(provider: OIDCProvider) {
    Logger.shared.info("Attempting to validate the credentials")
    // The OIDC flow runs under its own mode; a cancelled browser sheet returns
    // to the mode the user started from.
    let previousMode = viewModel.credentialMode
    viewModel.credentialMode = .oidc
    Task {
      if let stored = await viewModel.validateCredentials(auth: auth, provider: provider) {
        onSuccess(stored)
      } else {
        Logger.shared.info("Did not receive credentials (may be error)")
        if viewModel.credentialState == .none, !viewModel.otpEnabled {
          viewModel.credentialMode = previousMode
        }
      }
    }
  }

  private struct Favicon: View {
    @Environment(LoginViewModel.self) private var viewModel

    var provider: OIDCProvider

    @State private var url: URL? = nil

    private var placeholder: some View {
      Image(systemName: "person.crop.circle")
        .resizable()
        .frame(width: 24, height: 24)
    }

    var body: some View {
      Group {
        LazyImage(url: url, transaction: Transaction(animation: .default)) { phase in
          if let image = phase.image {
            image
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(width: 24, height: 24)
          } else {
            placeholder
          }
        }
        .pipeline(viewModel.imagePipeline)
      }
      .task {
        url = await provider.iconURL
      }
    }
  }

  var body: some View {
    VStack {
      if !viewModel.oidcProviders.isEmpty {
        ForEach(viewModel.oidcProviders) { provider in
          Button {
            validate(provider: provider)
          } label: {
            HStack {
              Favicon(provider: provider)
              Text(.login(.oidcLoginUsing(provider.name)))
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .center)
          }
          .apply {
            if prominent {
              $0.backport.glassProminentButtonStyle(or: .borderedProminent)
            } else {
              $0.backport.glassButtonStyle(or: .bordered)
            }
          }
          .padding(.horizontal)
        }
      } else {
        Section {
          ContentUnavailableView(
            .login(.oidcUnavailableTitle),
            systemImage: "person.fill.xmark",
            description: Text(
              .login(.oidcUnavailableDescription(DocumentationLinks.oidc.absoluteString))))
        }
      }
    }
  }
}

#Preview("Credentials") {
  @Previewable @State var viewModel = LoginViewModel()

  CredentialsStageView(onSuccess: { _ in })
    .environment(viewModel)
    .onAppear {
      viewModel.url = "http://localhost:8000"
      viewModel.username = "admin"
    }
}
