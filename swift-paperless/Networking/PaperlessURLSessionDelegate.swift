//
//  PaperlessURLSessionDelegate.swift
//  swift-paperless
//
//  Created by Nils Witt on 24.06.24.
//

import Foundation
import os

final class PaperlessURLSessionDelegate: NSObject, URLSessionTaskDelegate {
    private let credential: URLCredential?

    init(identityName: String?) {
        if
            let pName = identityName,
            let identity = Keychain.readIdentity(name: pName)
        {
            credential = URLCredential(identity: identity, certificates: nil, persistence: .none)
        } else {
            Logger.shared.info("Error loading identity from keychain")
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
            Logger.shared.info("Delegate without cert called")
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
            Logger.shared.info("DelegateTask without cert called")
            return (.performDefaultHandling, nil)
        }

        challenge.sender?.use(cred, for: challenge)
        return (.useCredential, cred)
    }
}
