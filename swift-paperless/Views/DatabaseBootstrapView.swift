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

  private var title: String {
    String(localized: .app(.databaseBootstrapFailureTitle))
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
      Button(String(localized: .app(.databaseBootstrapFailureRetry)), action: onRetry)
        .buttonStyle(.borderedProminent)
    }
    .padding()
  }
}
