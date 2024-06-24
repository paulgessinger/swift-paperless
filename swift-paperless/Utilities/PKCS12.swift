//
//  PKCS12.swift
//  swift-paperless
//
//  Created by Nils Witt on 24.06.24.
//

import Foundation


enum PKCS12Error: Error {
    case wrongPassword
    case other
}

class PKCS12 {
    let label: String?
    let keyID: NSData?
    let trust: SecTrust?
    let certChain: [SecTrust]?
    let identity: SecIdentity?

    
    public init(pkcs12Data: Data, password: String) throws {
        let importPasswordOption: NSDictionary = [kSecImportExportPassphrase as NSString: password]
        var items: CFArray?
        let secError: OSStatus = SecPKCS12Import(pkcs12Data as NSData, importPasswordOption, &items)
        guard secError == errSecSuccess else {
            if secError == errSecAuthFailed {
                throw PKCS12Error.wrongPassword
            }
            throw PKCS12Error.other
        }
        guard let theItemsCFArray = items else { fatalError() }
        let theItemsNSArray: NSArray = theItemsCFArray as NSArray
        guard let dictArray
            = theItemsNSArray as? [[String: AnyObject]]
        else {
            fatalError()
        }

        label = dictArray.element(for: kSecImportItemLabel)
        keyID = dictArray.element(for: kSecImportItemKeyID)
        trust = dictArray.element(for: kSecImportItemTrust)
        certChain = dictArray.element(for: kSecImportItemCertChain)
        identity = dictArray.element(for: kSecImportItemIdentity)
    }
}

extension Array where Element == [String: AnyObject] {
    func element<T>(for key: CFString) -> T? {
        for dictElement in self {
            if let value = dictElement[key as String] as? T {
                return value
            }
        }
        return nil
    }
}
