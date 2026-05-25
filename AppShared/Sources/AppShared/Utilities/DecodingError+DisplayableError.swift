//
//  DecodingError+DisplayableError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 30.11.2024.
//

extension DecodingError: DisplayableError {
  public var message: String {
    String(localized: .localizable(.decodingError))
  }

  public var details: String? {
    makeDetails(nil)
  }

  public func makeDetails(_ type: String?) -> String? {
    let context: DecodingError.Context? =
      switch self {
      case .typeMismatch(_, let context),
        .valueNotFound(_, let context),
        .keyNotFound(_, let context),
        .dataCorrupted(let context):
        context
      default:
        nil
      }

    let msg = String(localized: .localizable(.decodingErrorDetail(type ?? "Unknown")))

    guard let context else {
      return msg
    }

    return "\(msg)\n\n\(context.debugDescription)"
  }
}
