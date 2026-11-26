//
//  ConnectionStageView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.02.25.
//

import AppShared
import AppViews
import Networking
import SwiftUI

private typealias Section = CustomSection

struct ConnectionStageView: View {
  @Binding var stage: LoginStage

  @FocusState private var focus: Bool

  @Environment(LoginViewModel.self) private var viewModel
  @Environment(IdentityManager.self) private var identityManager

  @State private var showApiWarning = false

  private let animation = Animation.spring(duration: 0.2)

  private var showHttpWarning: Bool {
    viewModel.scheme == .http && !viewModel.url.isEmpty && !viewModel.isLocalAddress
  }

  private var error: LoginError? {
    if case .error(let error) = viewModel.loginState {
      return error
    }
    return nil
  }

  private func proceed() {
    guard viewModel.loginState == .valid else { return }
    focus = false
    stage = .credentials
  }

  var body: some View {
    @Bindable var viewModel = viewModel
    ScrollView(.vertical) {
      VStack {
        Section {
          UrlEntryView(focus: $focus)
        } footer: {
          VStack(alignment: .leading) {
            if showHttpWarning {
              LoginFooterView(systemImage: "exclamationmark.triangle.fill") {
                Text(.login(.httpWarning))
              }
              .foregroundStyle(.orange)
              .transition(.opacity)
            }

            if showApiWarning {
              LoginFooterView(systemImage: "info.circle") {
                Text(.login(.apiInUrlNotice))
              }
              .transition(.opacity)
            }

            if let error {
              LoginFooterView(systemImage: "xmark") {
                error.presentation
              }
              .foregroundStyle(.red)
              .transition(.opacity)
            }
          }
          .animation(animation, value: showHttpWarning)
          .animation(animation, value: viewModel.loginState)
        }

        if !identityManager.identities.isEmpty {
          Section {
            HStack {
              Text(.login(.identityTitle))
              Picker(
                "",
                selection: $viewModel.selectedIdentity
              ) {
                Text(String(localized: .app(.none))).tag(nil as TLSIdentity?)
                ForEach(identityManager.identities, id: \.self) {
                  Text($0.name)
                    .tag(Optional($0))
                }
              }
              .foregroundStyle(.primary)
              .frame(maxWidth: .infinity, alignment: .trailing)
            }
          } footer: {
            Text(.login(.identityDescription))
          }
        }
      }
    }
    .scrollDismissesKeyboard(.interactively)

    // Pinned to the bottom so it rides on top of the keyboard instead of
    // scrolling underneath it.
    .safeAreaInset(edge: .bottom) {
      Button {
        proceed()
      } label: {
        Text(.login(.continueButtonLabel))
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, 10)
      }
      .backport.glassProminentButtonStyle(or: .borderedProminent)
      .disabled(viewModel.loginState != .valid)
      .padding(.horizontal)
      .padding(.vertical, 8)
    }

    .modifier(BackgroundColorModifier())
    .scrollBounceBehavior(.basedOnSize)

    .onChange(of: viewModel.url) { viewModel.onChangeUrl() }
    .onChange(of: viewModel.selectedIdentity) { viewModel.onChangeUrl(immediate: true) }
    // The probe and the OIDC client both carry the extra headers, so re-run them.
    .onChange(of: viewModel.extraHeaders) { viewModel.onChangeUrl() }

    .onChange(of: viewModel.scheme) {
      Haptics.shared.impact(style: .soft)
      viewModel.onChangeUrl(immediate: true)
    }

    .onChange(of: viewModel.loginState) {
      switch viewModel.loginState {
      case .error:
        Haptics.shared.notification(.warning)
      case .valid:
        Haptics.shared.notification(.success)
      default:
        break
      }
    }

    .onSubmit(of: .text) {
      proceed()
    }
  }
}
