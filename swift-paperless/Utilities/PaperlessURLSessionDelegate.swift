//
//  PaperlessURLSessionDelegate.swift
//  swift-paperless
//
//  Created by Nils Witt on 24.06.24.
//

import Foundation
class PaperlessURLSessionDelegate: NSObject, URLSessionDelegate {
    
    var identityName: String? = nil
    
    public func urlSession(_: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod
                == NSURLAuthenticationMethodClientCertificate
              
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        guard let identName = identityName else {
            print("Cert Req but not loaded")
            completionHandler(.performDefaultHandling, nil)
            return
        }
        print("Using \(identName)")
        if let identity = Keychain.readIdentity(name: identName){
            let credential = URLCredential(identity: identity, certificates: nil, persistence: .none)
            
            challenge.sender?.use(credential, for: challenge)
            completionHandler(.useCredential, credential)
            return
        }else {
            print("Error loading")
        }
        completionHandler(.performDefaultHandling, nil)
    }
    
}
