//
//  LoginViewV2.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.08.2024.
//

import Foundation
import os
import SwiftUI

private enum Stage: CaseIterable, Comparable {
    case connection
    case credentials

    var label: Text {
        switch self {
        case .connection:
            Text("1. ") + Text(.login(.stageConnection))
        case .credentials:
            Text("2. ") + Text(.login(.stageCredentials))
        }
    }
}

@MainActor
private struct DetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LoginViewModel.self) private var viewModel

    @Environment(IdentityManager.self) private var identityManager

    var body: some View {
        // Hack
        @Bindable var viewModel = viewModel

        NavigationStack {
            Form {
                SwiftUI.Section {
                    NavigationLink {
                        ExtraHeadersView(headers: $viewModel.extraHeaders)
                    } label: {
                        Label(
                            markdown: .login(.extraHeaders), systemImage: "list.bullet.rectangle.fill"
                        )
                    }
                    NavigationLink {
                        TLSListView(identityManager: identityManager)
                    } label: {
                        Label(localized: .settings(.identities), systemImage: "lock.fill")
                    }

                    LogRecordExportButton()
                }

                LoginViewSwitchView()
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

private struct BackgroundColorModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        #if canImport(UIKit)
            content
                .background(Color(uiColor: .systemGroupedBackground))
        #else
            content
        #endif
    }
}

private struct Section<Content: View, Footer: View, Header: View>: View {
    var content: () -> Content
    var header: (() -> Header)? = nil
    var footer: (() -> Footer)? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            header?()
                .foregroundStyle(.secondary)
                .font(.footnote)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            content()
                .padding(.horizontal)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .circular)
                        .fill(.background.tertiary)
                )

            footer?()
                .foregroundStyle(.secondary)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        }
        .padding()
    }
}

extension Section where Footer == EmptyView {
    init(@ViewBuilder content: @escaping () -> Content, header: @escaping () -> Header) {
        self.init(content: content, header: header, footer: nil)
    }

    init(@ViewBuilder content: @escaping () -> Content, footer _: () -> Void, header: @escaping () -> Header) {
        self.init(content: content, header: header, footer: nil)
    }
}

extension Section where Footer == EmptyView, Header == EmptyView {
    init(@ViewBuilder content: @escaping () -> Content) {
        self.init(content: content, header: nil, footer: nil)
    }

    init(@ViewBuilder content: @escaping () -> Content, footer _: () -> Void, header _: () -> Void) {
        self.init(content: content, header: nil, footer: nil)
    }
}

extension Section where Header == EmptyView {
    init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: @escaping () -> Footer) {
        self.init(content: content, header: nil, footer: footer)
    }

    init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: @escaping () -> Footer, header _: () -> Void) {
        self.init(content: content, header: nil, footer: footer)
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

private typealias Scheme = LoginViewModel.Scheme

private struct UrlEntryView: View {
    @FocusState.Binding var focus: Bool

    @Environment(LoginViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        HStack(spacing: 1) {
            HStack(spacing: 3) {
                Label(localized: .login(.schemeSelectionLabel),
                      systemImage: "chevron.up.chevron.down")
                    .labelStyle(.iconOnly)
                    .font(.footnote)

                VStack {
                    if viewModel.scheme == .http {
                        Text(Scheme.http.label)
                            .transition(
                                .move(edge: .bottom)
                                    .combined(with: .opacity)
                            )
                    }
                    if viewModel.scheme == .https {
                        Text(Scheme.https.label)
                            .transition(
                                .move(edge: .top)
                                    .combined(with: .opacity)
                            )
                    }
                }
                .fontWeight(.medium)
                .animation(.spring(duration: 0.2, bounce: 0.5), value: viewModel.scheme)
            }
            .overlay {
                Menu {
                    ForEach([Scheme.https, Scheme.http], id: \.self) { value in
                        Button {
                            viewModel.scheme = value
                        } label: {
                            if viewModel.scheme == value {
                                Label(value.label, systemImage: "checkmark")
                            } else {
                                Text(value.label)
                            }
                        }
                        .disabled(viewModel.scheme == value)
                    }
                } label: { Color.clear }
            }
            .tint(.primary)

            TextField(String(localized: .login(.urlPlaceholder)), text: $viewModel.url)
                .padding(.vertical, 10)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focus)
                .submitLabel(.next)
            Spacer()
            switch viewModel.loginState {
            case .checking:
                ProgressView()
            case .valid:
                Label(localized: .login(.urlValid), systemImage:
                    "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Color.accentColor)
            case .error:
                Label(localized: .login(.urlError), systemImage:
                    "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.red)
            case .empty:
                EmptyView()
            }
        }
        .animation(.spring(duration: 0.2), value: viewModel.loginState)
        .animation(.spring(duration: 0.2), value: viewModel.scheme)
    }
}

private struct StageSelection: View {
    @Binding var stage: Stage

    @Namespace private var animation

    var body: some View {
        HStack {
            ForEach(Stage.allCases, id: \.self) { el in
                if el == stage {
                    el.label
                        .foregroundStyle(Color.accentColor)
                        .matchedGeometryEffect(id: el, in: animation)
                        .padding(.bottom, 3)
                        .background(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.accentColor)
                                .frame(height: 3)
                                .matchedGeometryEffect(id: "active", in: animation)
                        }
                } else {
                    el.label
                        .onTapGesture {
                            if el < stage {
                                stage = el
                            }
                        }
                        .matchedGeometryEffect(id: el, in: animation)
                }
            }
        }

        .animation(.spring(duration: 0.25, bounce: 0.25), value: stage)

        .padding(.vertical, 10)
        .padding(.horizontal)
        .background(
            Capsule()
                .fill(.thickMaterial)
                .stroke(.tertiary)
                .shadow(color: Color(white: 0.2, opacity: 0.1), radius: 10)
        )
    }
}

private struct CredentialsStageView: View {
    @Environment(LoginViewModel.self) private var viewModel

    @EnvironmentObject private var errorController: ErrorController

    var onSuccess: (StoredConnection) -> Void

    var loginEnabled: Bool {
        if viewModel.credentialState == .validating {
            return false
        }

        return switch viewModel.credentialMode {
        case .usernameAndPassword:
            !viewModel.username.isEmpty && !viewModel.password.isEmpty
        case .token:
            !viewModel.token.isEmpty
        case .none:
            true
        }
    }

    private func validate() {
        guard loginEnabled else { return }
        Logger.shared.info("Attempting to validate the credentials")
        Task {
            do {
                let stored = try await viewModel.validateCredentials()
                onSuccess(stored)
            } catch {
                Logger.shared.error("Got error validating credentials: \(error)")
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
            .frame(maxWidth: .infinity)
        }

        .modifier(BackgroundColorModifier())
        .scrollBounceBehavior(.basedOnSize)

        .onChange(of: viewModel.credentialMode) {
            viewModel.credentialState = .none
        }
    }
}

private struct ConnectionStageView: View {
    @Binding var stage: Stage

    @FocusState private var focus: Bool

    @Environment(LoginViewModel.self) private var viewModel
    @Environment(IdentityManager.self) private var identityManager

    @State private var showHttpWarning = false
    @State private var showApiWarning = false
    @State private var showError: LoginError?

    private let animation = Animation.spring(duration: 0.2)

    private func checkWarnings() {
        $showHttpWarning.animation(animation).wrappedValue = viewModel.scheme == .http && !viewModel.isLocalAddress
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
                            Picker("",
                                   selection: $viewModel.selectedIdentity)
                            {
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
                }
                .buttonStyle(.borderedProminent)

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
            case let .error(error):
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

@MainActor
struct LoginViewV2: LoginViewProtocol {
    @ObservedObject var connectionManager: ConnectionManager
    var initial: Bool = false

    @State private var viewModel = LoginViewModel()
    @State private var identityManager = IdentityManager()

    @Environment(\.dismiss) private var dismiss

    @State private var showDetails = false
    @State private var stage = Stage.connection
    @State private var showSuccessOverlay = false

    private func loginSucceeded(stored: StoredConnection) {
        Haptics.shared.notification(.success)

        showSuccessOverlay = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            if !initial {
                dismiss()
                try? await Task.sleep(for: .seconds(0.2))
            }
            connectionManager.login(stored)
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
            .toolbarBackground(.hidden, for: .navigationBar)

            .toolbar {
                if initial {
                    ToolbarItem(placement: .principal) {
                        LogoTitle()
                            .fixedSize()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showDetails = true
                    } label: {
                        Label(String(localized: .login(.moreToolbarButtonLabel)), systemImage: "ellipsis.circle")
                    }
                }
            }

            .safeAreaInset(edge: .top) {
                StageSelection(stage: $stage)
                    .padding(.top, 5)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom)
                    .background(.thinMaterial)
            }

            .if(!initial) { view in
                view
                    .navigationTitle(String(localized: .login(.additionalTitle)))

                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(String(localized: .localizable(.cancel))) {
                                dismiss()
                            }
                        }
                    }
            }
        }

        .sheet(isPresented: $showDetails) {
            DetailsView()
        }

        .successOverlay(isPresented: $showSuccessOverlay, duration: 2.0) {
            Text(.login(.success))
        }

        .environment(viewModel)
        .environment(identityManager)
    }
}

// - MARK: Previews

#Preview("Initial") {
    LoginViewV2(connectionManager: ConnectionManager())
}

#Preview("Additional") {
    LoginViewV2(connectionManager: ConnectionManager(), initial: false)
}

#Preview("Section") {
    ScrollView(.vertical) {
        Section {
            HStack {
                Text("GO IDENTITY!")
                Text("Right")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } header: {
            Text("head")
        } footer: {
            Text("yo")
        }
    }
    .modifier(BackgroundColorModifier())
}

#Preview("StageSwitch") {
    @Previewable @State var stage = Stage.connection

    return VStack {
        StageSelection(stage: $stage)
        Button("Connection") {
            stage = .connection
        }

        Button("Credentials") {
            stage = .credentials
        }
    }
}

#Preview("Credentials") {
    @Previewable @State var viewModel = LoginViewModel()

    return CredentialsStageView(onSuccess: { _ in })
        .modifier(BackgroundColorModifier())
        .environment(viewModel)
}
