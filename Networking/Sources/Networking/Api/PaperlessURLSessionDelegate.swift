//
//  PaperlessURLSessionDelegate.swift
//  swift-paperless
//
//  Created by Nils Witt on 24.06.24.
//

import Common
import Foundation
import os

final class PaperlessURLSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let credential: URLCredential?

    init(identityName: String?) {
        if
            let pName = identityName,
            let identity = Keychain.readIdentity(name: pName)
        {
            credential = URLCredential(identity: identity, certificates: nil, persistence: .none)
        } else {
            Logger.networking.info("Did not get identities from keychain")
            credential = nil
        }
    }

    init(identity: TLSIdentity?) {
        if let identity {
            credential = URLCredential(identity: identity.identity, certificates: nil, persistence: .none)
        } else {
            credential = nil
        }
    }

    public func urlSession(_: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
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

    func urlSession(_: URLSession, task _: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
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
