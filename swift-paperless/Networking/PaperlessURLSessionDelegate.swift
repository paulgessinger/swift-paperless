//
//  PaperlessURLSessionDelegate.swift
//  swift-paperless
//
//  Created by Nils Witt on 24.06.24.
//

import Foundation
import os

class PaperlessURLSessionDelegate: NSObject, URLSessionDelegate {
    
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
    
    public func urlSession(_: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard 
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate
                
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        guard let cred = self.credential else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        challenge.sender?.use(cred, for: challenge)
        completionHandler(.useCredential, cred)
    }
    
}
