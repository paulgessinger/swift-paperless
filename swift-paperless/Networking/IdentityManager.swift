//
//  IdentityManager.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.08.2024.
//

import Common
import Networking
import os
import SwiftUI

@Observable
class IdentityManager {
    var identities: [TLSIdentity]

    init() {
        do {
            identities = try Keychain.readAllIdentities().map { identity, name in
                TLSIdentity(name: name, identity: identity)
            }
        } catch {
            Logger.shared.error("Unable to load keychain identities")
            identities = []
        }
    }

    static func validate(certificate data: Data, password: String) -> Bool {
        do {
            let _ = try PKCS12(pkcs12Data: data, password: password)
            return true
        } catch {
            Logger.shared.error("PKCS12 invalid: \(error)")
        }
        return false
    }

    func save(certificate data: Data, password: String, name: String) throws {
        do {
            let pkc = try PKCS12(pkcs12Data: data, password: password)
            try Keychain.saveIdentity(identity: pkc.identity, name: name)
            identities.append(TLSIdentity(name: name, identity: pkc.identity))
        } catch {
            Logger.shared.error("Error loading/saving identity to the keychain: \(error)")
            throw error
        }
    }

    func delete(name: String) throws {
        try Keychain.deleteIdentity(name: name)
        identities = identities.filter { $0.name != name }
    }
}
