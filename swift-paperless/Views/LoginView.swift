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
    @Binding var extraHeaders: [ConnectionManager.HeaderValue]
    @Binding var identityNames: [String]
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
                    TLSListView(identityNames: $identityNames)
                } label: {
                    Label(localized: .settings(.certificates), systemImage: "lock.fill")
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

struct LoginView: View {
    @ObservedObject var connectionManager: ConnectionManager
    var initial = true

    @EnvironmentObject private var errorController: ErrorController

    @Environment(\.dismiss) private var dismiss

    @StateObject private var url = DebounceObject(delay: 1)

    private enum UrlState {
        case empty
        case checking
        case valid
        case error(info: AttributedString)
    }

    @State private var urlState = UrlState.empty

    private var urlStateValid: Bool {
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
                return String(localized: .login(.errorUrlInvalid))
            case .invalidLogin:
                return String(localized: .login(.errorLoginInvalid))
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

    @State private var extraHeaders: [ConnectionManager.HeaderValue] = []

    @State private var loginOngoing = false
    
    @State private var selectedIdentity: String? = nil
    
    @State private var availableIdenityNames: [String] = []

    @State private var certBasedAuth: Bool = false

    private nonisolated
    static func isLocalNetworkDenied(_ error: NSError) -> Bool {
        Logger.shared.debug("Checking API NSError: \(error)")
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError else {
            return false
        }
        Logger.shared.debug("Checking API underlying NSError: \(underlying)")

        guard let reason = (underlying.userInfo["_NSURLErrorNWPathKey"] as? NSObject)?.value(forKey: "reason") as? Int else {
            return false
        }

        Logger.shared.debug("Unsatisfied reason code is: \(reason)")
        return reason == 29
    }

    private nonisolated
    static func isLocalAddress(_ url: String) -> Bool {
        guard let components = URLComponents(string: url), let host = components.host else {
            return false
        }

        guard let match = try? /(\d+)\.(\d+)\.(\d+)\.(\d+)/.wholeMatch(in: host) else {
            return false
        }

        let ip = (UInt(match.1)!, UInt(match.2)!, UInt(match.3)!, UInt(match.4)!)

        return (ip >= (10, 0, 0, 0) && ip <= (10, 255, 255, 255)) || (ip >= (172, 16, 0, 0) && ip <= (172, 31, 255, 255)) || (ip >= (192, 168, 0, 0) && ip <= (192, 168, 255, 255))
    }

    private func checkUrl(string value: String) async {
        Logger.shared.notice("Checking backend URL \(value)")
        guard !value.isEmpty else {
            Logger.shared.notice("Value is empty")
            urlState = .empty
            return
        }

        guard let (_, apiUrl) = deriveUrl(string: value) else {
            Logger.shared.notice("Cannot convert to URL: \(value)")
            urlState = .error(info: AttributedString(localized: .login(.errorCouldNotConvertURL(value))))
            return
        }

        var request = URLRequest(url: apiUrl)
        extraHeaders.apply(toRequest: &request)

        Logger.api.info("Headers for check request: \(request.allHTTPHeaderFields ?? [:])")

        do {
            Logger.shared.info("Checking valid-looking URL \(apiUrl)")
            urlState = .checking

            
            let delegate = PaperlessURLSessionDelegate()
            delegate.loadIdentityByName(name: selectedIdentity)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            
            let (data, response) = try await session.getData(for: request)

            if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode != 200 {
                Logger.shared.warning("Checking API status was not 200 but \(statusCode)")
                urlState = .error(info: AttributedString(localized: .login(.errorInvalidResponse(value, statusCode))))
                return
            }

            let _ = try JSONDecoder().decode(Response.self, from: data)
            urlState = .valid

        } catch let error as NSError where LoginView.isLocalNetworkDenied(error) {
            Logger.shared.error("Unable to connect to API: local network access denied")
            urlState = .error(info: AttributedString(localized:
                .login(.errorLocalNetworkDenied(DocumentationLinks.localNetworkDenied.absoluteString))))
        } catch {
            Logger.shared.error("Checking API error: \(error)")
            urlState = .error(info: AttributedString(localized: .login(.errorUrlInvalidOther(error.localizedDescription))))
            return
        }
    }

    private func login() async {
        Logger.shared.notice("Attempting login with url \(url.text)")

        do {
            loginOngoing = true
            defer { loginOngoing = false }
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
            extraHeaders.apply(toRequest: &request)

            Logger.shared.info("Sending login request with headers: \(request.allHTTPHeaderFields ?? [:])")
            
            let delegate = PaperlessURLSessionDelegate()
            delegate.loadIdentityByName(name: selectedIdentity)
            
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let (data, response) = try await session.getData(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            
            if statusCode != 200 {
                Logger.shared.error("Token request response was not 200 but \(statusCode ?? -1, privacy: .public), \(String(decoding: data, as: UTF8.self))")
                if statusCode == 400 {
                    errorController.push(error: LoginError.invalidLogin)
                }
                return
            }

            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

            Logger.shared.info("Login credentials are valid")

            Haptics.shared.notification(.success)
            showSuccessOverlay = true
            try await Task.sleep(for: .seconds(2.3))

            let connection = Connection(url: baseUrl, token: tokenResponse.token, extraHeaders: extraHeaders, identityName: selectedIdentity)

            let repository = ApiRepository(connection: connection)

            let currentUser = try await repository.currentUser()

            if currentUser.username != username {
                Logger.api.warning("Username from login and logged in username not the same")
            }

            let stored = StoredConnection(url: baseUrl, extraHeaders: extraHeaders, user: currentUser, identity: selectedIdentity)
            try stored.setToken(connection.token)

            try connectionManager.login(stored)
            Logger.api.info("Login successful")

            if !initial {
                dismiss()
            }

        } catch {
            Logger.shared.error("Error during login with url \(error)")
            errorController.push(error: error)
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
                        switch urlState {
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

                        if url.debouncedText.starts(with: "http://"), !LoginView.isLocalAddress(url.debouncedText) {
                            HStack(alignment: .top) {
                                Image(systemName: "info.circle")
                                Text(.login(.httpWarning))
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
                
                
                Section{
                    Picker(String(localized: .settings(.activeCertificate)), selection: $selectedIdentity) {
                        Text("None").tag(Optional<String>(nil))
                        ForEach(availableIdenityNames, id: \.self) {
                            Text($0).tag(Optional($0))
                        }
                    }
                    .onChange(of: selectedIdentity) {
                        certBasedAuth = false
                    }
                    .onAppear{
                        let idents: [(SecIdentity, String)] = Keychain.readAllIdenties()
                        
                        availableIdenityNames.removeAll()
                        idents.forEach{ identity, name in
                            availableIdenityNames.append(name)
                        }
                    }
                    if selectedIdentity != nil {
                        Toggle(isOn: $certBasedAuth) {
                                Text("Certificate Only")
                        }
                    }
                }

                if !certBasedAuth {
                    Section {
                        TextField(String(localized: .login(.username)), text: $username)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        SecureField(String(localized: .login(.password)), text: $password)
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
                        await login()
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
                .disabled(!urlStateValid || username.isEmpty || password.isEmpty)
                .padding()
                .background(.thickMaterial)
                .ignoresSafeArea()
                .animation(.default, value: loginOngoing)
            }

            .onSubmit {
                Task {
                    await login()
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
                    await checkUrl(string: value)
                    withAnimation {
                        apiInUrl = value.contains("/api")
                    }
                }
            }
            .onChange(of: selectedIdentity) {
                Task {
                    await checkUrl(string: url.debouncedText)
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
                DetailsView(extraHeaders: $extraHeaders, identityNames: $availableIdenityNames)
            }

            .successOverlay(isPresented: $showSuccessOverlay, duration: 2.0) {
                Text(.login(.success))
            }
        }
    }
}

#Preview("Initial") {
    LoginView(connectionManager: ConnectionManager())
}

#Preview("Additional") {
    LoginView(connectionManager: ConnectionManager(), initial: false)
}
