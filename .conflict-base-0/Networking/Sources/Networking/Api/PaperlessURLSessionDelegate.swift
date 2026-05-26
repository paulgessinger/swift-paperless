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

  public init(identityName: String?) {
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
    if let identity {
      credential = Self.makeCredential(identity: identity.identity)
    } else {
      credential = nil
    }
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
}
