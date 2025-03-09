import Foundation
import os

public struct TLSIdentity: Identifiable, Equatable, Hashable {
    public var name: String
    public var identity: SecIdentity

    public var id: String { name }
}
