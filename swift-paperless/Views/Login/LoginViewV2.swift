//
//  LoginViewV2.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.08.2024.
//

import Foundation
import SwiftUI

@MainActor
private struct DetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LoginViewModel.self) private var viewModel

    var body: some View {
        // Hack
        @Bindable var viewModel = viewModel

        NavigationStack {
            List {
                NavigationLink {
                    ExtraHeadersView(headers: $viewModel.extraHeaders)
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

private struct Section<Content: View, Footer: View>: View {
    var content: () -> Content
    var footer: (() -> Footer)? = nil

    var body: some View {
        VStack(spacing: 4) {
            content()
                .padding(.horizontal)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .circular)
                        .fill(
                            Color.secondarySystemGroupedBackground)
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
    init(@ViewBuilder content: @escaping () -> Content) {
        self.init(content: content, footer: nil)
    }

    init(@ViewBuilder content: @escaping () -> Content, footer _: () -> Void) {
        self.init(content: content, footer: nil)
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

@MainActor
struct LoginViewV2: LoginViewProtocol {
    @ObservedObject var connectionManager: ConnectionManager
    let initial: Bool

    init(connectionManager: ConnectionManager, initial: Bool = true) {
        self.connectionManager = connectionManager
        self.initial = initial
    }

    @State private var viewModel = LoginViewModel()

    @Environment(\.dismiss) private var dismiss

    @State private var showDetails = false

    @State private var showHttpWarning = false
    @State private var showApiWarning = false
    @State private var showError: LoginError?

    private let animation = Animation.spring(duration: 0.2)

    private func checkWarnings() {
        $showHttpWarning.animation(animation).wrappedValue = viewModel.scheme == .http && !viewModel.isLocalAddress
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack {
                    if initial {
                        HStack {
                            LogoView()
                                .font(.title)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }

                    Section {
                        UrlEntryView()
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
                                error.view
                                    .transition(.opacity)
                            }
                        }
                    }

                    Section {
                        Text("Another")
                    }
                }
            }

            .background(Color.systemGroupedBackground)

            .scrollBounceBehavior(.basedOnSize)
            .navigationBarTitleDisplayMode(.inline)

            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showDetails = true
                    } label: {
                        Label(String(localized: .login(.moreToolbarButtonLabel)), systemImage: "info.circle")
                    }
                }
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

        .onChange(of: viewModel.url) { viewModel.onChangeUrl() }

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

        .environment(viewModel)
    }
}

// - MARK: Previews

#Preview("Initial") {
    LoginViewV2(connectionManager: ConnectionManager())
}

#Preview("Additional") {
    LoginViewV2(connectionManager: ConnectionManager(), initial: false)
}
