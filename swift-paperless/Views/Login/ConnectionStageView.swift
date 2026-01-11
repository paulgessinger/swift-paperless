//
//  ConnectionStageView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.02.25.
//

import Networking
import SwiftUI

private typealias Section = CustomSection

struct ConnectionStageView: View {
  @Binding var stage: LoginStage

  @FocusState private var focus: Bool

  @Environment(LoginViewModel.self) private var viewModel
  @Environment(IdentityManager.self) private var identityManager

  @State private var showHttpWarning = false
  @State private var showApiWarning = false
  @State private var showError: LoginError?

  private let animation = Animation.spring(duration: 0.2)

  private func checkWarnings() {
    $showHttpWarning.animation(animation).wrappedValue =
      viewModel.scheme == .http && !viewModel.isLocalAddress
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
              LoginFooterView(systemImage: "info.circle") {
                Text(.login(.httpWarning))
              }
              .transition(.opacity)
            }

            if showApiWarning {
              LoginFooterView(systemImage: "info.circle") {
                Text(.login(.apiInUrlNotice))
              }
              .transition(.opacity)
            }

            if let error = showError {
              LoginFooterView(systemImage: "xmark") {
                error.presentation
              }
              .foregroundStyle(.red)
              .transition(.opacity)
            }
          }
        }

        if !identityManager.identities.isEmpty {
          Section {
            HStack {
              Text(.login(.identityTitle))
              Picker(
                "",
                selection: $viewModel.selectedIdentity
              ) {
                Text(String(localized: .localizable(.none))).tag(nil as TLSIdentity?)
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

        Button {
          focus = false
          stage = .credentials
        } label: {
          Text(.login(.continueButtonLabel))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 10)
        }
        .backport.glassProminentButtonStyle(or: .borderedProminent)

        .padding()
        .disabled(viewModel.loginState != .valid)
      }
    }

    .modifier(BackgroundColorModifier())
    .scrollBounceBehavior(.basedOnSize)

    .onChange(of: viewModel.url) { viewModel.onChangeUrl() }
    .onChange(of: viewModel.selectedIdentity) { viewModel.onChangeUrl(immediate: true) }

    .onChange(of: viewModel.scheme) {
      Haptics.shared.impact(style: .soft)
      checkWarnings()
      viewModel.onChangeUrl(immediate: true)
    }

    .onChange(of: viewModel.url) { checkWarnings() }
    .onChange(of: viewModel.loginState) {
      let binding = $showError.animation(animation)
      switch viewModel.loginState {
      case .error(let error):
        Haptics.shared.notification(.warning)
        binding.wrappedValue = error
      case .checking:
        break
      case .valid:
        Haptics.shared.notification(.success)
        fallthrough
      default:
        binding.wrappedValue = nil
      }
    }

    .onSubmit(of: .text) {
      if viewModel.loginState == .valid {
        focus = false
        stage = .credentials
      }
    }
  }
}
