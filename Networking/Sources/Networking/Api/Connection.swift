import Foundation
import os

public struct Connection: Equatable, Sendable {
    public struct HeaderValue: Codable, Equatable, Sendable {
        // @TODO: (multi-server) Replace with direct field
        private var _id: UUID?
        public var key: String
        public var value: String

        public var id: UUID {
            get { _id ?? UUID() }
            set { _id = newValue }
        }

        enum CodingKeys: String, CodingKey {
            case _id = "id"
            case key, value
        }

        public init(key: String, value: String) {
            _id = UUID()
            self.key = key
            self.value = value
        }
    }

    public let url: URL
    public let token: String?
    public let extraHeaders: [HeaderValue]
    public let identity: String?

    public init(url: URL, token: String? = nil, extraHeaders: [HeaderValue] = [], identityName: String?) {
        self.url = url
        self.token = token
        self.extraHeaders = extraHeaders
        identity = identityName
    }

    public var scheme: String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            Logger.networking.error("Unable to decompose connection URL for scheme, returning https")
            return "https"
        }
        guard let scheme = components.scheme else {
            Logger.networking.error("Connection URL does not have scheme, returning https")
            return "https"
        }

        return scheme
    }
}

public extension [Connection.HeaderValue] {
    func apply(toRequest req: inout URLRequest) {
        for kv in self {
            if kv.key.contains(" ") || kv.key.isEmpty { continue }
            req.setValue(kv.value, forHTTPHeaderField: kv.key)
        }
    }
}
