//
//  AppConfigurationModel.swift
//  DataModel
//
//  Created by Claude on 09.07.25.
//

import Foundation
import MetaCodable

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct AppConfiguration: Sendable, Identifiable {
    public var id: UInt

    public var userArgs: String?
    public var barcodeTagMapping: String?
    public var outputType: String?
    public var pages: UInt?
    public var language: String?
    public var mode: String?
    public var skipArchiveFile: String?
    public var imageDpi: UInt?
    public var unpaperClean: String?
    public var deskew: Bool?
    public var rotatePages: Bool?
    public var rotatePagesThreshold: Double?
    public var maxImagePixels: UInt?
    public var colorConversionStrategy: String?
    public var appTitle: String?
    public var appLogo: String?
    public var barcodesEnabled: Bool?
    public var barcodeEnableTiffSupport: Bool?
    public var barcodeString: String?
    public var barcodeRetainSplitPages: Bool?
    public var barcodeEnableAsn: Bool?
    public var barcodeAsnPrefix: String?
    public var barcodeUpscale: Double?
    public var barcodeDpi: UInt?
    public var barcodeMaxPages: UInt?
    public var barcodeEnableTag: Bool?
}
