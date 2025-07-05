//
//  PKCS12.swift
//  swift-paperless
//
//  Created by Nils Witt on 24.06.24.
//

import Foundation
import os

enum PKCS12Error: Error {
  case wrongPassword
  case noItems
  case other(_: OSStatus)
  case noIdentity
}

class PKCS12 {
  let identity: SecIdentity

  public init(pkcs12Data: Data, password: String) throws {
    let importPasswordOption: NSDictionary = [kSecImportExportPassphrase as NSString: password]
    var items: CFArray?
    let secError: OSStatus = SecPKCS12Import(pkcs12Data as NSData, importPasswordOption, &items)
    guard secError == errSecSuccess else {
      if secError == errSecAuthFailed {
        throw PKCS12Error.wrongPassword
      }
      throw PKCS12Error.other(secError)
    }
    guard let theItemsCFArray = items else {
      throw PKCS12Error.noItems
    }
    let theItemsNSArray: NSArray = theItemsCFArray as NSArray
    guard let dictArray = theItemsNSArray as? [[String: AnyObject]]
    else {
      throw PKCS12Error.noItems
    }

    guard let identity: SecIdentity = dictArray.element(for: kSecImportItemIdentity) else {
      Logger.shared.error("PKCS12 did not contain an identity")
      throw PKCS12Error.noIdentity
    }

    self.identity = identity
  }
}

extension [[String: AnyObject]] {
  fileprivate func element<T>(for key: CFString) -> T? {
    for dictElement in self {
      if let value = dictElement[key as String] as? T {
        return value
      }
    }
    return nil
  }
}
