//
//  CredentialsStageView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.02.25.
//

import os
import SwiftUI

private typealias Section = CustomSection

struct CredentialsStageView: View {
    @Environment(LoginViewModel.self) private var viewModel

    @EnvironmentObject private var errorController: ErrorController

    var onSuccess: (StoredConnection) -> Void

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
        case .none:
            return true
        }
    }

    private func validate() {
        guard loginEnabled else { return }
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

    @ViewBuilder
    private var button: some View {
        Button {
            validate()
        } label: {
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
        .id(viewModel.credentialMode)
        .buttonStyle(.borderedProminent)
        .padding(.horizontal)
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
                    }
                }
                .foregroundColor(.red)
                .padding(.horizontal)
            default:
                LoginFooterView(systemImage: "xmark") {
                    error.presentation
                }
                .foregroundStyle(.red)
                .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private var otpValid: Bool {
        let ex = /^[0-9]*$/
        let isDigits: Bool = (try? ex.wholeMatch(in: viewModel.otp)) != nil
        return isDigits && viewModel.otp.count == 6
    }

    private func checkOtp(_ old: String, _ new: String) {
        let ex = /^[0-9]*$/
        let isDigits: Bool = (try? ex.wholeMatch(in: new)) != nil
        if (!isDigits && !new.isEmpty) || new.count > 6 {
            viewModel.otp = old
            return
        }
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        ScrollView(.vertical) {
            VStack {
                Section {
                    Menu {
                        ForEach(CredentialMode.allCases, id: \.self) { item in
                            Button {
                                viewModel.credentialMode = item
                            } label: {
                                if viewModel.credentialMode == item {
                                    Label(item.label, systemImage: "checkmark")
                                } else {
                                    Text(item.label)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Label(localized: .login(.schemeSelectionLabel),
                                  systemImage: "chevron.up.chevron.down")
                                .labelStyle(.iconOnly)
                                .font(.footnote)
                            Text(viewModel.credentialMode.label)
                                .fixedSize()
                        }
                    }
                } header: {
                    Text(.login(.credentialMode))
                } footer: {
                    VStack {
                        viewModel.credentialMode.description
                    }
                    .animation(.default, value: viewModel.credentialMode)
                }

                VStack {
                    switch viewModel.credentialMode {
                    case .usernameAndPassword:
                        Section {
                            VStack {
                                TextField(.login(.username), text: $viewModel.username)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .submitLabel(.go)
                                Divider()
                                SecureField(.login(.password), text: $viewModel.password)
                                    .submitLabel(.go)
                            }
                            .padding(.vertical, 10)

                            .onSubmit(of: .text) {
                                validate()
                            }

                        } header: {
                            Text(.login(.credentials))
                        } footer: {
                            LoginFooterView(systemImage: "info.circle") {
                                Text(.login(.passwordStorageNotice))
                            }
                        }

                        if viewModel.otpEnabled {
                            Section {
                                TextField(String("123456"), text: $viewModel.otp)
                                    .textContentType(.oneTimeCode)
                                    .keyboardType(.numberPad)
                                    .submitLabel(.go)
                                    .onChange(of: viewModel.otp) { old, new in checkOtp(old, new) }
                            } header: {
                                Text(.login(.otp))
                            } footer: {
                                LoginFooterView(systemImage: "numbers.rectangle") {
                                    Text(.login(.otpDescription))
                                }
                            }
                        }

                    case .token:
                        Section {
                            TextField(.login(.token), text: $viewModel.token)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .submitLabel(.go)

                                .onSubmit(of: .text) {
                                    validate()
                                }
                        }

                    case .none:
                        EmptyView()
                    }

                    VStack {
                        switch viewModel.credentialState {
                        case .valid:
                            EmptyView()
                        case let .error(error):
                            button
                            errorView(error)
                        default:
                            button
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.default, value: loginEnabled)
                }
                .animation(.default, value: viewModel.credentialMode)
            }
            .animation(.spring(duration: 0.3), value: viewModel.otpEnabled)
            .frame(maxWidth: .infinity)
        }

        .modifier(BackgroundColorModifier())
        .scrollBounceBehavior(.basedOnSize)

        .onChange(of: viewModel.credentialMode) {
            viewModel.credentialState = .none
        }
    }
}

#Preview("Credentials") {
    @Previewable @State var viewModel = LoginViewModel()

    return VStack {
        CredentialsStageView(onSuccess: { _ in })
            .modifier(BackgroundColorModifier())
            .environment(viewModel)

        Button("Toggle OTP") {
            viewModel.otpEnabled.toggle()
        }
    }
}
