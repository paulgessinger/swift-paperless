//
//  DecodingError+DisplayableError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 30.11.2024.
//

extension DecodingError: DisplayableError {
    var message: String {
        String(localized: .localizable(.decodingError))
    }

    var details: String? {
        makeDetails(nil)
    }

    func makeDetails(_ type: String?) -> String? {
        let context: DecodingError.Context? = switch self {
        case let .typeMismatch(_, context),
             let .valueNotFound(_, context),
             let .keyNotFound(_, context),
             let .dataCorrupted(context):
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
