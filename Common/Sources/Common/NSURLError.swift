//
//  NSURLError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 15.12.2024.
//

// Taken from NSURLError.h
public enum NSURLError: Int {
    public enum Category {
        case ssl
        case fileio
        case other
    }

    case unknown = -1
    case cancelled = -999
    case badURL = -1000
    case timedOut = -1001
    case unsupportedURL = -1002
    case cannotFindHost = -1003
    case cannotConnectToHost = -1004
    case networkConnectionLost = -1005
    case dnsLookupFailed = -1006
    case httpTooManyRedirects = -1007
    case resourceUnavailable = -1008
    case notConnectedToInternet = -1009
    case redirectToNonExistentLocation = -1010
    case badServerResponse = -1011
    case userCancelledAuthentication = -1012
    case userAuthenticationRequired = -1013
    case zeroByteResource = -1014
    case cannotDecodeRawData = -1015
    case cannotDecodeContentData = -1016
    case cannotParseResponse = -1017

    @available(macOS 10.11, iOS 9.0, watchOS 2.0, tvOS 9.0, *)
    case appTransportSecurityRequiresSecureConnection = -1022
    case fileDoesNotExist = -1100
    case fileIsDirectory = -1101
    case noPermissionsToReadFile = -1102
    @available(macOS 10.5, iOS 2.0, watchOS 2.0, tvOS 9.0, *)
    case dataLengthExceedsMaximum = -1103
    @available(macOS 10.12.4, iOS 10.3, watchOS 3.2, tvOS 10.2, *)
    case fileOutsideSafeArea = -1104

    // SSL errors
    case secureConnectionFailed = -1200
    case serverCertificateHasBadDate = -1201
    case serverCertificateUntrusted = -1202
    case serverCertificateHasUnknownRoot = -1203
    case serverCertificateNotYetValid = -1204
    case clientCertificateRejected = -1205
    case clientCertificateRequired = -1206
    case cannotLoadFromNetwork = -2000

    // Download and file I/O errors
    case cannotCreateFile = -3000
    case cannotOpenFile = -3001
    case cannotCloseFile = -3002
    case cannotWriteToFile = -3003
    case cannotRemoveFile = -3004
    case cannotMoveFile = -3005
    case downloadDecodingFailedMidStream = -3006
    case downloadDecodingFailedToComplete = -3007

    @available(macOS 10.7, iOS 3.0, watchOS 2.0, tvOS 9.0, *)
    case internationalRoamingOff = -1018
    @available(macOS 10.7, iOS 3.0, watchOS 2.0, tvOS 9.0, *)
    case callIsActive = -1019
    @available(macOS 10.7, iOS 3.0, watchOS 2.0, tvOS 9.0, *)
    case dataNotAllowed = -1020
    @available(macOS 10.7, iOS 3.0, watchOS 2.0, tvOS 9.0, *)
    case requestBodyStreamExhausted = -1021

    @available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
    case backgroundSessionRequiresSharedContainer = -995
    @available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
    case backgroundSessionInUseByAnotherProcess = -996
    @available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
    case backgroundSessionWasDisconnected = -997

    public var category: Category {
        switch self {
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired,
             .cannotLoadFromNetwork:
            .ssl

        case .cannotCreateFile,
             .cannotOpenFile,
             .cannotCloseFile,
             .cannotWriteToFile,
             .cannotRemoveFile,
             .cannotMoveFile,
             .downloadDecodingFailedMidStream,
             .downloadDecodingFailedToComplete:
            .fileio

        default:
            .other
        }
    }

    public static func value(_ value: Int, inCategory category: Category) -> Bool {
        guard let value = NSURLError(rawValue: value) else { return false }
        return value.category == category
    }
}
