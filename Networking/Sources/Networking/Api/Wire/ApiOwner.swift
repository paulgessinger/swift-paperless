//
//  ApiOwner.swift
//  Networking
//

import DataModel

extension Owner {
  /// The `owner` to send when creating an object. `.unset` becomes `nil`, so
  /// the key is left out and paperless-ngx makes the requesting user the owner;
  /// an explicit `null` would create the object without an owner.
  var createValue: Owner? {
    if case .unset = self { return nil }
    return self
  }
}
