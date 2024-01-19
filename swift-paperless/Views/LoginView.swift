//
//  LoginView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 25.03.23.
//

import os
import SwiftUI

private struct Response: Decodable {
    var correspondents: URL
    var document_types: URL
    var logs: URL
    var mail_accounts: URL
    var mail_rules: URL
    var saved_views: URL
    var storage_paths: URL
    var tags: URL
    var tasks: URL
}

private struct TokenRequest: Encodable {
    var username: String
    var password: String
}

private struct TokenResponse: Decodable {
    var token: String
}

private struct DetailsView: View {
    @ObservedObject var connectionManager: ConnectionManager
    @State private var extraHeaders: [ConnectionManager.HeaderValue]
    @Environment(\.dismiss) private var dismiss

    init(connectionManager: ConnectionManager) {
        self.connectionManager = connectionManager
        _extraHeaders = State(initialValue: connectionManager.extraHeaders)
    }

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ExtraHeadersView(headers: $extraHeaders)
                } label: {
                    Text(.login.extraHeaders)
                }

                LogRecordExportButton()
            }
            .navigationTitle(Text(.login.detailsTitle))
            .navigationBarTitleDisplayMode(.inline)

            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                }
            }
        }

        .onChange(of: extraHeaders) { value in
            connectionManager.extraHeaders = value
        }
    }
}

struct LoginView: View {
    @ObservedObject var connectionManager: ConnectionManager

    @EnvironmentObject var errorController: ErrorController

    @StateObject private var url = DebounceObject(delay: 1)

    private enum UrlState {
        case empty
        case checking
        case valid
        case error(info: String)
    }

    @State private var urlState = UrlState.empty

    var urlStateValid: Bool {
        switch urlState {
        case .valid:
            return true
        default:
            return false
        }
    }

    private enum LoginError: DisplayableError, Equatable {
        case urlInvalid
        case invalidLogin

        var message: String {
            switch self {
            case .urlInvalid:
                return String(localized: .login.errorUrlInvalid)
            case .invalidLogin:
                return String(localized: .login.errorLoginInvalid)
            }
        }

        var details: String? {
            nil
        }
    }

    @State private var apiInUrl = false

    @State private var username: String = ""
    @State private var password: String = ""

    @State private var showDetails: Bool = false
    @State private var showSuccessOverlay = false

    private func checkUrl(string value: String) async {
        Logger.shared.notice("Checking backend URL \(value)")
        guard !value.isEmpty else {
            Logger.shared.notice("Value is empty")
            urlState = .empty
            return
        }

        guard let (_, apiUrl) = deriveUrl(string: value) else {
            Logger.shared.notice("Cannot convert to URL: \(value)")
            urlState = .error(info: String(localized: .login.errorCouldNotConvertURL(value)))
            return
        }

        var request = URLRequest(url: apiUrl)
        connectionManager.extraHeaders.apply(toRequest: &request)

        do {
            Logger.shared.notice("Checking valid-looking URL \(apiUrl)")
            urlState = .checking
            let (data, response) = try await URLSession.shared.data(for: request)

            if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode != 200 {
                Logger.shared.warning("Checking API status was not 200 but \(statusCode)")
                urlState = .error(info: String(localized: .login.errorInvalidResponse(value, statusCode)))
                return
            }

            let _ = try JSONDecoder().decode(Response.self, from: data)
            urlState = .valid
        } catch {
            Logger.shared.error("Checking API error: \(error)")
            urlState = .error(info: String(localized: .login.errorUrlInvalidOther(error.localizedDescription)))
            return
        }
    }

    private func login() async {
        Logger.shared.notice("Attempting login with url \(url.text)")

        do {
            let json = try JSONEncoder().encode(TokenRequest(username: username, password: password))

            guard let (baseUrl, tokenUrl) = deriveUrl(string: url.text, suffix: "token") else {
                Logger.shared.warning("Error making URL for logging in (url: \(url.text)")
                errorController.push(error: LoginError.urlInvalid)
                return
            }

            var request = URLRequest(url: tokenUrl)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = json
            connectionManager.extraHeaders.apply(toRequest: &request)

            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode

            if statusCode != 200 {
                Logger.shared.error("Token request response was not 200 but \(statusCode ?? -1), \(String(decoding: data, as: UTF8.self))")
                if statusCode == 400 {
                    errorController.push(error: LoginError.invalidLogin)
                }
                return
            }

            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

            Logger.shared.notice("Login successful")

            Haptics.shared.notification(.success)
            showSuccessOverlay = true
            try await Task.sleep(for: .seconds(2.3))

            try connectionManager.set(base: baseUrl, token: tokenResponse.token)
        } catch {
            Logger.shared.error("Error during login with url \(error)")
            errorController.push(error: error)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    Spacer()
                    LogoView()
                    Spacer()
                }
                .listRowInsets(EdgeInsets())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(Color.systemGroupedBackground)

                Section {
                    HStack {
                        TextField(String(localized: .login.urlPlaceholder), text: $url.text)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Spacer()
                        switch urlState {
                        case .checking:
                            ProgressView()
                        case .valid:
                            Label(String(localized: .login.urlValid), systemImage:
                                "checkmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundColor(.accentColor)
                        case .error:
                            Label(String(localized: .login.urlError), systemImage:
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
                                Text(.login.apiInUrlNotice)
                            }
                        }

                        if url.debouncedText.starts(with: "http://") {
                            HStack(alignment: .top) {
                                Image(systemName: "info.circle")
                                Text(.login.httpWarning)
                            }
                        }

                        if case let .error(info) = urlState {
                            HStack(alignment: .top) {
                                Image(systemName: "xmark")
                                    .offset(y: 2)
                                Text(info)
                            }
                            .foregroundColor(.red)
                        }
                    }
                    .transition(.opacity)
                }

                Section {
                    TextField(String(localized: .login.username), text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField(String(localized: .login.password), text: $password)
                } header: {
                    Text(.login.credentials)
                } footer: {
                    HStack(alignment: .top) {
                        Image(systemName: "info.circle")
                        Text(.login.passwordStorageNotice)
                    }
                }

                Section {
                    Button(action: {
                        Task {
                            await login()
                        }
                    }) {
                        HStack {
                            Spacer()
                            Text(.login.buttonLabel)
                            Spacer()
                        }
                    }
                    .disabled(!urlStateValid || username.isEmpty || password.isEmpty)
                }
            }

            .onChange(of: url.debouncedText) { value in
                Task {
                    await checkUrl(string: value)
                    withAnimation {
                        apiInUrl = value.contains("/api")
                    }
                }
            }

            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showDetails = true
                    } label: {
                        Label(String(localized: .login.moreToolbarButtonLabel), systemImage: "info.circle")
                    }
                }
            }

            .sheet(isPresented: $showDetails) {
                DetailsView(connectionManager: connectionManager)
            }

            .successOverlay(isPresented: $showSuccessOverlay, duration: 2.0) {
                Text(.login.success)
            }
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView(connectionManager: ConnectionManager())
    }
}

struct DetailsView_Previews: PreviewProvider {
    struct Container: View {
        @State var headers: [(String, String)] = [
            ("header1", "value1"),
            ("Header2", "other value"),
        ]

        var body: some View {
            DetailsView(connectionManager: ConnectionManager())
        }
    }

    static var previews: some View {
        Container()
    }
}
