//
//  LoginView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 25.03.23.
//

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

    private func deriveUrl(string value: String, suffix: String = "") -> URL? {
        var value = value
        if !value.starts(with: "https://") {
            value = "https://" + value
        }

        if value.last != "/" {
            value += "/"
        }
        value += "api/"
        value += suffix

        guard let url = URL(string: value) else {
            return nil
        }

        return url
    }

    private func checkUrl(string value: String) async {
        guard !value.isEmpty else {
            print("Value is empty")
            urlState = .empty
            return
        }

        guard let url = deriveUrl(string: value) else {
            print("Cannot convert to url")
            urlState = .error
            return
        }

        let request = URLRequest(url: url)
        do {
            urlState = .checking
            let (data, response) = try await URLSession.shared.data(for: request)

            if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode != 200 {
                print("Checking API status was not 200 but \(statusCode)")
                urlState = .error
                return
            }

            let _ = try JSONDecoder().decode(Response.self, from: data)
            urlState = .valid
        } catch {
            print("Checking API error: \(error)")
            urlState = .error
            return
        }
    }

    private func login() async -> Bool {
        do {
            let json = try JSONEncoder().encode(TokenRequest(username: username, password: password))

            guard let url = deriveUrl(string: url.text, suffix: "token/") else {
                print("Error making URL for logging in")
                return false
            }

//            print(url)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = json

            let (data, response) = try await URLSession.shared.data(for: request)

            if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode != 200 {
                print("Token request response was not 200 but \(statusCode)")
                return false
            }

            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
//            print(tokenResponse.token)

            withAnimation { loginState = .valid }

            try await Task.sleep(for: .seconds(0.5))

            try connectionManager.set(Connection(host: self.url.text, token: tokenResponse.token))
            return true

        } catch {
            print(error)
        }
        return false
    }

    var body: some View {
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
                    TextField("Paperless URL", text: $url.text)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Spacer()
                    switch urlState {
                    case .checking:
                        ProgressView()
                    case .valid:
                        Label("Valid", systemImage:
                            "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundColor(.accentColor)
                    case .error:
                        Label("Error", systemImage:
                            "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundColor(.red)
                    case .empty:
                        EmptyView()
                    }
                }

                if apiInUrl {
                    HStack(alignment: .top) {
                        Image(systemName: "info.circle")
                        Text("Do not include the /api/ part of the URL")
                    }
                    .foregroundColor(.gray)
                    .padding()
                    .listRowInsets(EdgeInsets())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(Color.systemGroupedBackground)
                    .transition(.opacity)
                }
            }
            Section("Credentials") {
                TextField("Username", text: $username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $password)
            }
            HStack(alignment: .top) {
                Image(systemName: "info.circle")
                Text("Your password is used to login, and not stored on the device!")
            }
            .foregroundColor(.gray)
            .padding()
            .listRowInsets(EdgeInsets())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.systemGroupedBackground)

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
                        Text("Login")
                        if loginState == .valid {
                            Label("Valid", systemImage: "checkmark.circle.fill")
                                .labelStyle(.iconOnly)
                        } else if loginState == .error {
                            Label("Error", systemImage: "xmark.circle.fill")
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
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView(connectionManager: ConnectionManager())
    }
}
