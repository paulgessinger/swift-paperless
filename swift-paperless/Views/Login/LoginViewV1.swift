//
//  LoginViewV1.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 25.03.23.
//

import os
import SwiftUI

private struct DetailsView: View {
    @Binding var extraHeaders: [ConnectionManager.HeaderValue]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ExtraHeadersView(headers: $extraHeaders)
                } label: {
                    Label(String(localized: .login(.extraHeaders)), systemImage: "list.bullet.rectangle.fill")
                }
                NavigationLink {
                    TLSListView()
                } label: {
                    Label(localized: .settings(.identities), systemImage: "lock.fill")
                }

                LogRecordExportButton()
            }
            .navigationTitle(Text(.login(.detailsTitle)))
            .navigationBarTitleDisplayMode(.inline)

            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: .localizable(.done))) {
                        dismiss()
                    }
                }
            }
        }
    }
}

@MainActor
struct LoginViewV1: LoginViewProtocol {
    @ObservedObject var connectionManager: ConnectionManager
    var initial = true

    @EnvironmentObject private var errorController: ErrorController

    @Environment(\.dismiss) private var dismiss

    @StateObject private var url = DebounceObject(delay: 1)

    @State private var viewModel = LoginViewModel()

    @State private var apiInUrl = false

    @State private var showDetails: Bool = false
    @State private var showSuccessOverlay = false

    @State private var loginOngoing = false

    @State private var availableIdentityNames: [String] = []

    @State private var identityBasedAuth: Bool = false

    @State private var showIdentitySelection: Bool = false

    private func login() async throws {
        Logger.shared.notice("Attempting login with url \(url.text)")

        if identityBasedAuth {
            return try await loginIdentityBased()
        }

        do {
            loginOngoing = true
            defer { loginOngoing = false }

            struct TokenRequest: Encodable {
                var username: String
                var password: String
            }

            let json = try JSONEncoder().encode(TokenRequest(username: viewModel.username,
                                                             password: viewModel.password))

            let baseUrl: URL
            let tokenUrl: URL
            do {
                (baseUrl, tokenUrl) = try deriveUrl(string: url.text, suffix: "token")
            } catch {
                Logger.shared.warning("Error making URL for logging in (url: \(url.text)) \(error)")
                viewModel.loginState = .error(.init(invalidUrl: error))
                throw LoginError(invalidUrl: error)
            }

            var request = URLRequest(url: tokenUrl)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = json
            viewModel.extraHeaders.apply(toRequest: &request)

            Logger.shared.info("Sending login request with headers: \(request.allHTTPHeaderFields ?? [:])")

            let session = URLSession(configuration: .default, delegate: PaperlessURLSessionDelegate(identityName: viewModel.selectedIdentity), delegateQueue: nil)
            let (data, response) = try await session.getData(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode

            if statusCode != 200 {
                Logger.shared.error("Token request response was not 200 but \(statusCode ?? -1, privacy: .public), \(String(decoding: data, as: UTF8.self))")
                if statusCode == 400 {
                    viewModel.loginState = .error(.invalidLogin)
                }
                throw LoginError.invalidLogin
            }

            struct TokenResponse: Decodable {
                var token: String
            }

            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

            Logger.shared.info("Login credentials are valid")

            let connection = Connection(url: baseUrl,
                                        token: tokenResponse.token,
                                        extraHeaders: viewModel.extraHeaders,
                                        identityName: viewModel.selectedIdentity)

            let repository = await ApiRepository(connection: connection)

            let currentUser = try await repository.currentUser()

            if currentUser.username != viewModel.username {
                Logger.api.warning("Username from login and logged in username not the same")
            }

            let stored = StoredConnection(url: baseUrl,
                                          extraHeaders: viewModel.extraHeaders,
                                          user: currentUser,
                                          identity: viewModel.selectedIdentity)
            try stored.setToken(connection.token)

            connectionManager.login(stored)
            Logger.api.info("Login successful")

            Haptics.shared.notification(.success)
            showSuccessOverlay = true
            try await Task.sleep(for: .seconds(2.3))

            if !initial {
                dismiss()
            }

        } catch RequestError.forbidden {
            Logger.shared.error("User logging in does not have permissions to get permissions")
            viewModel.loginState = .error(.insufficientPermissions)
            throw LoginError.insufficientPermissions
        } catch {
            Logger.shared.error("Error during login with url \(error)")
            viewModel.loginState = .error(.init(other: error))
            throw LoginError(other: error)
        }
    }

    private func loginIdentityBased() async throws {
        do {
            loginOngoing = true
            defer { loginOngoing = false }

            guard let (baseUrl, _) = try? deriveUrl(string: url.text, suffix: "token") else {
                Logger.shared.warning("Error making URL for logging in (url: \(url.text)")
                viewModel.loginState = .error(.invalidUrl(nil))
                throw LoginError.invalidUrl(nil)
            }

            Logger.shared.info("Trying to load data from api ")
            let connection = Connection(url: baseUrl, token: "",
                                        extraHeaders: viewModel.extraHeaders,
                                        identityName: viewModel.selectedIdentity)

            let repository = await ApiRepository(connection: connection)

            let currentUser = try await repository.currentUser()

            Logger.shared.info("Username: \(currentUser.username)")

            let stored = StoredConnection(url: baseUrl,
                                          extraHeaders: viewModel.extraHeaders,
                                          user: currentUser,
                                          identity: viewModel.selectedIdentity)
            try stored.setToken("")
            connectionManager.login(stored)
            Logger.api.info("Login successful")

            // Success point
            Haptics.shared.notification(.success)
            showSuccessOverlay = true

        } catch RequestError.forbidden {
            Logger.shared.error("User logging in does not have permissions to get permissions")
            viewModel.loginState = .error(.insufficientPermissions)
            throw LoginError.insufficientPermissions
        } catch {
            Logger.shared.error("Error during login with url \(error)")
            viewModel.loginState = .error(.init(other: error))
            throw LoginError(other: error)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(String(localized: .login(.urlPlaceholder)), text: $url.text)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Spacer()
                        switch viewModel.loginState {
                        case .checking:
                            ProgressView()
                        case .valid:
                            Label(String(localized: .login(.urlValid)), systemImage:
                                "checkmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundColor(.accentColor)
                        case .error:
                            Label(String(localized: .login(.urlError)), systemImage:
                                "xmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundColor(.red)
                        case .empty:
                            EmptyView()
                        }
                    }

                } footer: {
                    VStack(alignment: .leading) {
                        if apiInUrl {
                            HStack(alignment: .top) {
                                Image(systemName: "info.circle")
                                Text(.login(.apiInUrlNotice))
                            }
                        }

                        if url.debouncedText.starts(with: "http://"), !LoginViewModel.isLocalAddress(url.debouncedText) {
                            HStack(alignment: .top) {
                                Image(systemName: "info.circle")
                                Text(.login(.httpWarning))
                            }
                        }

                        if case let .error(error) = viewModel.loginState {
                            error.view
                        }
                    }
                    .transition(.opacity)
                }

                if showIdentitySelection {
                    Section {
                        Picker(String(localized: .settings(.activeIdentity)),
                               selection: $viewModel.selectedIdentity)
                        {
                            Text(String(localized: .localizable(.none))).tag(String?(nil))
                            ForEach(availableIdentityNames, id: \.self) {
                                Text($0).tag(Optional($0))
                            }
                        }
                        .onChange(of: viewModel.selectedIdentity) {
                            if viewModel.selectedIdentity == nil {
                                identityBasedAuth = false
                            }
                        }
                        if viewModel.selectedIdentity != nil {
                            Toggle(isOn: $identityBasedAuth) {
                                // @TODO: Translation
                                Text("Identity Only")
                            }
                        }
                    }
                }

                if !identityBasedAuth {
                    Section {
                        TextField(String(localized: .login(.username)), text: $viewModel.username)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        SecureField(String(localized: .login(.password)), text: $viewModel.password)
                    } header: {
                        Text(.login(.credentials))
                    } footer: {
                        HStack(alignment: .top) {
                            Image(systemName: "info.circle")
                            Text(.login(.passwordStorageNotice))
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: {
                    Task {
                        do {
                            try await login()
                        } catch {
                            errorController.push(error: error)
                        }
                    }
                }) {
                    HStack(spacing: 5) {
                        if loginOngoing {
                            ProgressView()
                        }
                        Text(.login(.buttonLabel))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)
                .disabled((!viewModel.loginStateValid || viewModel.username.isEmpty || viewModel.password.isEmpty) && (!identityBasedAuth || !viewModel.loginStateValid))
                .padding()
                .background(.thickMaterial)
                .ignoresSafeArea()
                .animation(.default, value: loginOngoing)
            }

            .onSubmit {
                Task {
                    do {
                        try await login()
                    } catch {
                        errorController.push(error: error)
                    }
                }
            }

            .safeAreaInset(edge: .top) {
                if initial {
                    HStack {
                        LogoView()
                            .font(.title)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, -45)
                }
            }

            .if(!initial) { view in
                view
                    .navigationTitle(String(localized: .login(.additionalTitle)))
                    .navigationBarTitleDisplayMode(.inline)

                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(String(localized: .localizable(.cancel))) {
                                dismiss()
                            }
                        }
                    }
            }

            .onChange(of: url.debouncedText) { _, value in
                Task {
                    await viewModel.checkUrl(string: value)
                    withAnimation {
                        apiInUrl = value.contains("/api")
                    }
                }
            }
            .onChange(of: viewModel.selectedIdentity) {
                Task {
                    await viewModel.checkUrl(string: url.debouncedText)
                }
            }

            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showDetails = true
                    } label: {
                        Label(String(localized: .login(.moreToolbarButtonLabel)), systemImage: "info.circle")
                    }
                }
            }

            .sheet(isPresented: $showDetails) {
                DetailsView(extraHeaders: $viewModel.extraHeaders)
            }

            .successOverlay(isPresented: $showSuccessOverlay, duration: 2.0) {
                Text(.login(.success))
            }
            .onAppear {
                let identities: [(SecIdentity, String)] = Keychain.readAllIdenties()
                availableIdentityNames.removeAll()
                identities.forEach { _, name in
                    availableIdentityNames.append(name)
                }
            }
            .onChange(of: showDetails) {
                let identities: [(SecIdentity, String)] = Keychain.readAllIdenties()
                availableIdentityNames.removeAll()
                identities.forEach { _, name in
                    availableIdentityNames.append(name)
                }
            }
            .onChange(of: availableIdentityNames) {
                showIdentitySelection = availableIdentityNames.count > 0
            }
        }
    }
}

#Preview("Initial") {
    LoginViewV1(connectionManager: ConnectionManager())
}

#Preview("Additional") {
    LoginViewV1(connectionManager: ConnectionManager(), initial: false)
}
