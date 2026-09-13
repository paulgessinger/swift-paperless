//
//  PaperlessURLSessionDelegate.swift
//  swift-paperless
//
//  Created by Nils Witt on 24.06.24.
//

import Common
import Foundation
import os

public final class PaperlessURLSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
  private let credential: URLCredential?

  /// Receives the wire bytes of every task on a session this delegate is the
  /// *session* delegate of, once its metrics land. `nil` records nothing.
  ///
  /// Only set this on a delegate owned by a session whose traffic belongs to a
  /// single meter category (the image pipeline). A request that passes its own
  /// per-task delegate implementing the metrics callback — every API request
  /// does — takes precedence and never reaches this one.
  private let onTransfer: (@Sendable (_ sent: Int64, _ received: Int64) -> Void)?

  private init(
    credential: URLCredential?,
    onTransfer: (@Sendable (_ sent: Int64, _ received: Int64) -> Void)?
  ) {
    self.credential = credential
    self.onTransfer = onTransfer
  }

  public init(identityName: String?) {
    onTransfer = nil
    if let pName = identityName,
      let identity = Keychain.readIdentity(name: pName)
    {
      Logger.networking.info(
        "URLSessionDelegate initializing with identity: \(pName, privacy: .public)")
      credential = Self.makeCredential(identity: identity)
    } else {
      Logger.networking.info("URLSessionDelegate initializing without identity")
      credential = nil
    }
  }

  public init(identity: TLSIdentity?) {
    onTransfer = nil
    if let identity {
      credential = Self.makeCredential(identity: identity.identity)
    } else {
      credential = nil
    }
  }

  /// A delegate answering the same client-certificate challenges as this one,
  /// that additionally reports each task's wire bytes to `onTransfer`. Reuses
  /// the credential rather than reading the identity from the keychain again.
  public func recordingTransfers(
    _ onTransfer: @escaping @Sendable (_ sent: Int64, _ received: Int64) -> Void
  ) -> PaperlessURLSessionDelegate {
    PaperlessURLSessionDelegate(credential: credential, onTransfer: onTransfer)
  }

  private static func makeCredential(identity: SecIdentity) -> URLCredential {
    var leafCertificate: SecCertificate?
    let status = SecIdentityCopyCertificate(identity, &leafCertificate)

    if status == errSecSuccess, let cert = leafCertificate {
      // Include the leaf certificate so TLS client-auth always sends a non-empty certificate list.
      return URLCredential(identity: identity, certificates: [cert], persistence: .none)
    }

    Logger.networking.warning(
      "Failed to extract leaf certificate from identity (\(status, privacy: .public)); using identity without certificates"
    )
    return URLCredential(identity: identity, certificates: nil, persistence: .none)
  }

  public func urlSession(_: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (
    URLSession.AuthChallengeDisposition, URLCredential?
  ) {
    guard
      challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate
    else {
      return (.performDefaultHandling, nil)
    }

    guard let cred = credential else {
      Logger.networking.info("Delegate without cert called")
      return (.performDefaultHandling, nil)
    }

    challenge.sender?.use(cred, for: challenge)
    return (.useCredential, cred)
  }

  public func urlSession(
    _: URLSession, task _: URLSessionTask, didReceive challenge: URLAuthenticationChallenge
  ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
    guard
      challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate
    else {
      return (.performDefaultHandling, nil)
    }

    guard let cred = credential else {
      Logger.networking.info("DelegateTask without cert called")
      return (.performDefaultHandling, nil)
    }

    challenge.sender?.use(cred, for: challenge)
    return (.useCredential, cred)
  }

  public func urlSession(
    _: URLSession, task _: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics
  ) {
    let bytes = metrics.transferredBytes
    record(sent: bytes.sent, received: bytes.received)
  }

  /// Test seam: `URLSessionTaskMetrics` has no usable initializer, so the
  /// Foundation callback above can't be driven from a test. Everything past the
  /// summation goes through here.
  func record(sent: Int64, received: Int64) {
    onTransfer?(sent, received)
  }
}
