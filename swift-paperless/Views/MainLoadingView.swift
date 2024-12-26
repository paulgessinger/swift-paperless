//
//  MainLoadingView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.12.24.
//

import DataModel
import SwiftUI

struct MainLoadingView: View {
    let url: String?
    let manager: ConnectionManager

    let progressDelay: Duration
    let failSafeDelay: Duration

    init(url: String?, manager: ConnectionManager, progressDelay: Duration = .seconds(2), failSafeDelay: Duration = .seconds(15)) {
        self.url = url
        self.manager = manager
        self.progressDelay = progressDelay
        self.failSafeDelay = failSafeDelay
    }

    @State private var showProgress = false
    @State private var showFailSafe = false

    @ViewBuilder
    private var failSafeView: some View {
        VStack {
            Text(.localizable(.loginFailSafe(url ?? "???")))
                .padding(.horizontal)
                .padding(.top, 50)

            ConnectionSelectionMenu(connectionManager: manager,
                                    animated: false)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(lineWidth: 0.33)
                )
                .padding()

            Button {
                showFailSafe = false
                manager.logout()
            } label: {
                Label(String(localized: .localizable(.logout)), systemImage: "rectangle.portrait.and.arrow.right")
            }
            .foregroundColor(Color.red)
            .bold()
            .padding(.top)
        }
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        VStack {
            LogoView()

            if showProgress, !showFailSafe {
                ProgressView()
                    .controlSize(.large)
            }

            VStack {
                if showFailSafe {
                    ViewThatFits(in: .vertical) {
                        failSafeView

                        ScrollView(.vertical) {
                            failSafeView
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                }
            }
        }

        .animation(.spring, value: showProgress)
        .animation(.spring, value: showFailSafe)

        .task {
            try? await Task.sleep(for: progressDelay)
            showProgress = true
            try? await Task.sleep(for: failSafeDelay)
            showFailSafe = true
        }
    }
}

#Preview {
    @Previewable @StateObject var manager = ConnectionManager()

    MainLoadingView(url: manager.connection?.url.absoluteString,
                    manager: manager,
                    progressDelay: .seconds(0.5),
                    failSafeDelay: .seconds(2))

        .frame(maxHeight: .infinity)

        .overlay(alignment: .bottom) {
            Button("Add login") {
                manager.login(StoredConnection(url: URL(string: "https://example.com")!, extraHeaders: [], user: User(id: 1, isSuperUser: false, username: "preview")))
            }
        }
}
