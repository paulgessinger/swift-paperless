//
//  LoginViewV2.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.08.2024.
//

import Foundation
import os
import SwiftUI

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

@MainActor
struct LoginViewV2: LoginViewProtocol {
    @ObservedObject var connectionManager: ConnectionManager
    var initial: Bool = false

    @State private var viewModel = LoginViewModel()
    @State private var identityManager = IdentityManager()

    @Environment(\.dismiss) private var dismiss

    @State private var showDetails = false
    @State private var stage = LoginStage.connection
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

#Preview("StageSwitch") {
    @Previewable @State var stage = LoginStage.connection

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
