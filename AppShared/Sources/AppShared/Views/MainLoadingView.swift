//
//  MainLoadingView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.12.24.
//

import DataModel
import Persistence
import SwiftUI

public struct MainLoadingView: View {
  public let url: String?
  public let manager: ConnectionManager

  public let progressDelay: Duration
  public let failSafeDelay: Duration

  public init(
    url: String?, manager: ConnectionManager, progressDelay: Duration = .seconds(2),
    failSafeDelay: Duration = .seconds(15)
  ) {
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
      Text(.app(.loginFailSafe(url ?? "???")))
        .padding(.horizontal)
        .padding(.top, 50)

      ConnectionSelectionMenu(
        connectionManager: manager,
        animated: false
      )
      .padding()
      .background(
        RoundedRectangle(cornerRadius: 15, style: .continuous)
          .stroke(lineWidth: 0.33)
      )
      .padding()

      Button {
        showFailSafe = false
        manager.logout(animated: false)
      } label: {
        Label(
          String(localized: .app(.logout)),
          systemImage: "rectangle.portrait.and.arrow.right")
      }
      .foregroundColor(Color.red)
      .bold()
      .padding(.top)
    }
    .frame(maxWidth: .infinity)
  }

  public var body: some View {
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
  @Previewable @State var manager = ConnectionManager(
    database: try! Database.inMemory())

  MainLoadingView(
    url: manager.connection?.url.absoluteString,
    manager: manager,
    progressDelay: .seconds(0.5),
    failSafeDelay: .seconds(2)
  )

  .frame(maxHeight: .infinity)

  .overlay(alignment: .bottom) {
    Button("Add login") {
      manager.login(
        StoredConnection(
          url: URL(string: "https://example.com")!, extraHeaders: [],
          user: User(id: 1, isSuperUser: false, username: "preview")))
    }
  }
}
