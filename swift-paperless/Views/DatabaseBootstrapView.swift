//
//  DatabaseBootstrapView.swift
//  swift-paperless
//

import AppShared
import Persistence
import SwiftUI
import os

/// Owns the at-launch ``Database`` construction. Sole producer; ``MainView``
/// only sees a ready database after the bootstrap succeeds. On failure the
/// app shows the hard-fail UI instead, with a "Try Again" affordance that
/// re-runs the bootstrap.
@MainActor
@Observable
final class DatabaseBootstrap {
  enum Outcome {
    case ready(Database)
    case failed(any Error)
  }

  private(set) var outcome: Outcome

  init() {
    outcome = Self.attempt()
  }

  func retry() {
    Logger.shared.notice("Retrying database bootstrap")
    outcome = Self.attempt()
  }

  private static func attempt() -> Outcome {
    do {
      return .ready(try Database())
    } catch {
      Logger.shared.fault("Database bootstrap failed: \(error)")
      return .failed(error)
    }
  }
}

struct DatabaseBootstrapView: View {
  @Bindable var bootstrap: DatabaseBootstrap

  var body: some View {
    switch bootstrap.outcome {
    case .ready(let database):
      MainView(database: database)
    case .failed(let error):
      DatabaseFailureView(error: error) { bootstrap.retry() }
    }
  }
}

/// Full-screen UI when ``DatabaseBootstrap`` cannot open the on-disk database.
struct DatabaseFailureView: View {
  let error: any Error
  let onRetry: () -> Void

  @State private var showLogs = false
  @State private var showWipeConfirmation = false
  @State private var wipeError: String?

  private var title: String {
    String(localized: .persistence(.databaseBootstrapFailureTitle))
  }

  private var detail: String {
    if let displayable = error as? any DisplayableError,
      let details = displayable.details
    {
      return details
    }
    if let localized = error as? any LocalizedError {
      if let reason = localized.failureReason, let description = localized.errorDescription {
        return "\(description) \(reason)"
      }
      return localized.errorDescription ?? error.localizedDescription
    }
    return error.localizedDescription
  }

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "externaldrive.badge.exclamationmark")
        .font(.system(size: 56))
        .foregroundStyle(.orange)
      Text(title)
        .font(.title2)
        .multilineTextAlignment(.center)
      Text(detail)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
        .textSelection(.enabled)

      VStack(spacing: 16) {
        Button(action: onRetry) {
          Text(.persistence(.databaseBootstrapFailureRetry))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        Button {
          showLogs = true
        } label: {
          Label(
            String(localized: .persistence(.databaseBootstrapFailureViewLogs)),
            systemImage: "text.word.spacing"
          )
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)

        Button(role: .destructive) {
          showWipeConfirmation = true
        } label: {
          Label(
            String(localized: .persistence(.databaseBootstrapFailureWipe)),
            systemImage: "trash"
          )
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.red)
        .confirmationDialog(
          String(localized: .persistence(.databaseBootstrapFailureWipeConfirmTitle)),
          isPresented: $showWipeConfirmation,
          titleVisibility: .visible
        ) {
          Button(
            String(localized: .persistence(.databaseBootstrapFailureWipeConfirmAction)),
            role: .destructive
          ) {
            wipeDatabase()
          }
          Button(String(localized: .app(.cancel)), role: .cancel) {}
        } message: {
          Text(.persistence(.databaseBootstrapFailureWipeConfirmMessage))
        }
      }
      .padding(.horizontal, 24)
      .padding(.top, 8)

      if let wipeError {
        Text(wipeError)
          .font(.caption)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
          .padding(.horizontal)
      }
    }
    .padding()
    .sheet(isPresented: $showLogs) {
      NavigationStack {
        LogView()
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button(role: .cancel) {
                showLogs = false
              } label: {
                Label(String(localized: .app(.cancel)), systemImage: "xmark")
              }
              .labelStyle(.iconOnly)
            }
          }
      }
    }
  }

  private func wipeDatabase() {
    do {
      try Database.wipe()
      wipeError = nil
      onRetry()
    } catch {
      Logger.shared.error("Wipe database failed: \(error)")
      wipeError =
        "\(String(localized: .persistence(.databaseBootstrapFailureWipeFailed))) \(error.localizedDescription)"
    }
  }
}
