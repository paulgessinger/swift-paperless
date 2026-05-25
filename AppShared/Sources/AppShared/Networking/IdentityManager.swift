//
//  IdentityManager.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.08.2024.
//

import Common
import Networking
import SwiftUI
import os

@Observable
public class IdentityManager {
  public var identities: [TLSIdentity]

  public init() {
    do {
      identities = try Keychain.readAllIdentities().map { identity, name in
        TLSIdentity(name: name, identity: identity)
      }
    } catch {
      Logger.shared.error("Unable to load keychain identities")
      identities = []
    }
  }

  public static func validate(certificate data: Data, password: String) -> Bool {
    do {
      let _ = try PKCS12(pkcs12Data: data, password: password)
      return true
    } catch {
      Logger.shared.error("PKCS12 invalid: \(error)")
    }
    return false
  }

  public func save(certificate data: Data, password: String, name: String) throws {
    do {
      let pkc = try PKCS12(pkcs12Data: data, password: password)
      try Keychain.saveIdentity(identity: pkc.identity, name: name)
      identities.append(TLSIdentity(name: name, identity: pkc.identity))
    } catch {
      Logger.shared.error("Error loading/saving identity to the keychain: \(error)")
      throw error
    }
  }

  public func delete(name: String) throws {
    try Keychain.deleteIdentity(name: name)
    identities = identities.filter { $0.name != name }
  }
}
