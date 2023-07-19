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
        self._extraHeaders = State(initialValue: connectionManager.extraHeaders)
    }

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ExtraHeadersView(headers: $extraHeaders)
                } label: {
                    Text(LocalizedStrings.Login.extraHeaders)
                }
            }
            .navigationTitle(LocalizedStrings.Login.detailsTitle)
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

    @StateObject private var url = DebounceObject(delay: 1)

    private enum UrlState {
        case empty
        case checking
        case valid
        case error
    }

    @State private var urlState = UrlState.empty

    private enum LoginState {
        case none
        case valid
        case error
    }

    @State private var loginState = LoginState.none

    @State private var apiInUrl = false

    @State private var username: String = ""
    @State private var password: String = ""

    @State private var showDetails: Bool = false

    private func deriveUrl(string value: String, suffix: String = "") -> (base: URL, resolved: URL)? {
        let url: URL?

        let pattern = /https?:\/\/(.*)/

        if (try? pattern.wholeMatch(in: value)) != nil {
            url = URL(string: value)
        } else {
            url = URL(string: "https://\(value)")
        }

        guard let url = url else {
            Logger.shared.debug("Derived url \(value) was invalid")
            return nil
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            Logger.shared.debug("Unable to parse url into components")
            return nil
        }
        let base = url

        components.path = "/api/" + suffix

        guard let url = components.url else {
            Logger.shared.debug("Unable to convert components back to url \(components)")
            return nil
        }

        Logger.shared.trace("Derive url: \(value) + \(suffix) -> \(url)")

        return (base, url)
    }

    private func checkUrl(string value: String) async {
        Logger.shared.debug("Checking backend URL \(value)")
        guard !value.isEmpty else {
            Logger.shared.trace("Value is empty")
            urlState = .empty
            return
        }

        guard let (_, apiUrl) = deriveUrl(string: value) else {
            Logger.shared.trace("Cannot convert to url")
            urlState = .error
            return
        }

        var request = URLRequest(url: apiUrl)
        connectionManager.extraHeaders.apply(toRequest: &request)

        do {
            urlState = .checking
            let (data, response) = try await URLSession.shared.data(for: request)

            if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode != 200 {
                Logger.shared.debug("Checking API status was not 200 but \(statusCode)")
                urlState = .error
                return
            }

            let _ = try JSONDecoder().decode(Response.self, from: data)
            urlState = .valid
        } catch {
            Logger.shared.debug("Checking API error: \(error)")
            urlState = .error
            return
        }
    }

    private func login() async -> Bool {
        Logger.shared.trace("Attempting login with url \(url.text)")

        do {
            let json = try JSONEncoder().encode(TokenRequest(username: username, password: password))

            guard let (baseUrl, tokenUrl) = deriveUrl(string: url.text, suffix: "token/") else {
                Logger.shared.debug("Error making URL for logging in")
                return false
            }

//            print(url)

            var request = URLRequest(url: tokenUrl)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = json
            connectionManager.extraHeaders.apply(toRequest: &request)

            let (data, response) = try await URLSession.shared.data(for: request)

            if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode != 200 {
                Logger.shared.debug("Token request response was not 200 but \(statusCode)")
                return false
            }

            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

            Logger.shared.trace("Login successful")

            withAnimation { loginState = .valid }

            try await Task.sleep(for: .seconds(0.5))

            // @TODO Change scheme!
            try connectionManager.set(host: baseUrl, token: tokenResponse.token)
            return true

        } catch {
            Logger.shared.error("\(error)")
        }
        return false
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
                        TextField(LocalizedStrings.Login.PaperlessUrl.placeholder, text: $url.text)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Spacer()
                        switch urlState {
                        case .checking:
                            ProgressView()
                        case .valid:
                            Label(LocalizedStrings.Login.PaperlessUrl.valid, systemImage:
                                "checkmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundColor(.accentColor)
                        case .error:
                            Label(LocalizedStrings.Login.PaperlessUrl.error, systemImage:
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
                                Text(LocalizedStrings.Login.apiInUrlNotice)
                            }
                        }

                        if url.debouncedText.starts(with: "http://") {
                            HStack(alignment: .top) {
                                Image(systemName: "info.circle")
                                Text(LocalizedStrings.Login.httpWarning)
                            }
                        }
                    }
                    .transition(.opacity)
                }

                Section {
                    TextField(LocalizedStrings.Login.username, text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField(LocalizedStrings.Login.password, text: $password)
                } header: {
                    Text(LocalizedStrings.Login.credentials)
                } footer: {
                    HStack(alignment: .top) {
                        Image(systemName: "info.circle")
                        Text(LocalizedStrings.Login.passwordStorageNotice)
                    }
                }

                Section {
                    Button(action: {
                        Task {
                            if await login() {
                                withAnimation { loginState = .valid }
                            } else {
                                withAnimation { loginState = .error }
                            }
                        }
                    }) {
                        HStack {
                            Spacer()
                            Text(LocalizedStrings.Login.LoginButton.label)
                            if loginState == .valid {
                                Label(LocalizedStrings.Login.LoginButton.valid, systemImage: "checkmark.circle.fill")
                                    .labelStyle(.iconOnly)
                            } else if loginState == .error {
                                Label(LocalizedStrings.Login.LoginButton.error, systemImage: "xmark.circle.fill")
                                    .labelStyle(.iconOnly)
                            }
                            Spacer()
                        }
                        .foregroundColor({
                            switch loginState {
                            case .valid:
                                return Color.accentColor
                            case .error:
                                return Color.red
                            case .none:
                                return Color.primary
                            }
                        }())
                    }
                    .disabled(urlState != .valid || username.isEmpty || password.isEmpty)
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
            .onChange(of: username) { _ in withAnimation { loginState = .none }}
            .onChange(of: password) { _ in withAnimation { loginState = .none }}

            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showDetails = true
                    } label: {
                        Label(LocalizedStrings.Login.moreToolbarButtonLabel, systemImage: "info.circle")
                    }
                }
            }

            .sheet(isPresented: $showDetails) {
                DetailsView(connectionManager: connectionManager)
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
            ("Header2", "other value")
        ]

        var body: some View {
            DetailsView(connectionManager: ConnectionManager())
        }
    }

    static var previews: some View {
        Container()
    }
}
