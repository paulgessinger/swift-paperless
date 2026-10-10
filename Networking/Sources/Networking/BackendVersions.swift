import Common

/// A server's API version (`X-Api-Version`) and backend version (`X-Version`),
/// as learned by a successful probe.
public struct BackendVersions: Equatable, Sendable {
  public var apiVersion: UInt
  public var backendVersion: Version

  public init(apiVersion: UInt, backendVersion: Version) {
    self.apiVersion = apiVersion
    self.backendVersion = backendVersion
  }
}
