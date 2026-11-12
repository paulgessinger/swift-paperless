//
//  TelemetryClassification.swift
//  AppShared
//
//  Maps app events onto the closed telemetry vocabulary.
//

import Common
import DataModel
import Foundation
import Networking

extension TelemetryError {
  /// The setup-problem class of a request or URL loading error, or `nil` for
  /// anything else, cancellation, and the device being offline.
  public init?(classifying error: any Error) {
    if error.isCancellationError { return nil }

    if let request = error as? RequestError {
      self.init(classifying: request)
      return
    }

    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
      guard let request = RequestError(from: nsError, path: .unknown) else { return nil }
      self.init(classifying: request)
      return
    }

    return nil
  }

  public init?(classifying error: RequestError) {
    switch error {
    case .certificate:
      self = .tls
    case .unauthorized, .forbidden:
      self = .auth
    case .unsupportedVersion:
      self = .backendTooOld
    case .connectivity(let code, let kind, _):
      switch kind {
      case .offline: return nil
      case .serverNotResponding where code == .timedOut: self = .timeout
      case .hostNotFound, .serverNotResponding, .connectionLost: self = .unreachable
      }
    case .invalidRequest, .invalidResponse, .unexpectedStatusCode, .localNetworkDenied, .other:
      self = .other
    }
  }
}

extension TelemetryFeature {
  /// The features a change of the document list's filter counts as: applying
  /// a saved view, starting a search, or changing a filter rule. Re-sorting
  /// and refining an already running search count as nothing.
  public static func filterChanges(from old: FilterState, to new: FilterState) -> [Self] {
    if let savedView = new.savedView, savedView != old.savedView {
      return [.savedView]
    }

    var features: [Self] = []
    if old.searchText.isEmpty, !new.searchText.isEmpty {
      features.append(.search)
    }
    if rules(of: old) != rules(of: new) {
      features.append(.filter)
    }
    return features
  }

  /// `state` without the search, sort and saved-view selection.
  private static func rules(of state: FilterState) -> FilterState {
    var rules = state
    rules.searchText = ""
    rules.searchMode = .title
    rules.sorting = nil
    rules.savedView = nil
    return rules
  }
}
