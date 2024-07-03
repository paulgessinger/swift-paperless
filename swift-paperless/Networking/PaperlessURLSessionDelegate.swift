//
//  PaperlessURLSessionDelegate.swift
//  swift-paperless
//
//  Created by Nils Witt on 24.06.24.
//

import Foundation
import os

class PaperlessURLSessionDelegate: NSObject, URLSessionTaskDelegate {
    
    private var credential: URLCredential? = nil
    
    public func loadIdentityByName(name: String?){
        self.credential = nil
        if
            let pName = name,
            let identity = Keychain.readIdentity(name: pName){
            self.credential = URLCredential(identity: identity, certificates: nil, persistence: .none)
            return
        }else {
            Logger.shared.info("Error loading identity from keychain")
        }
    }
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate
        else {
            return (.performDefaultHandling, nil)
        }
        
        guard let cred = self.credential else {
            Logger.shared.info("Delegate without cert called")
            return (.performDefaultHandling, nil)
        }

        challenge.sender?.use(cred, for: challenge)
        return (.useCredential, cred)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate
        else {
            return (.performDefaultHandling, nil)
        }
        
        guard let cred = self.credential else {
            Logger.shared.info("DelegateTask without cert called")
            return (.performDefaultHandling, nil)
        }

        challenge.sender?.use(cred, for: challenge)
        return (.useCredential, cred)
    }
    
}
