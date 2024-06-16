//
//  DocumentImportModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 17.05.2024.
//

import Foundation
import os
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
class DocumentImportModel: ObservableObject {
    @Published
    var importUrls: [URL] = []
    @Published
    var totalUrls = 0

    var remaining: Int {
        totalUrls - importUrls.count + 1
    }

    func reset() {
        importUrls = []
        totalUrls = 0
    }

    func next() -> URL? {
        importUrls.first
    }

    func pop() {
        if !importUrls.isEmpty {
            importUrls.removeFirst()
        }
    }

    // @TODO: Separate view model which does the copying on a background thread
    func importFile(result: [URL], isSecurityScoped: Bool, errorController: ErrorController) async {
        Logger.shared.debug("Initiate import of \(result.count) URLs")
        do {
            var images: [UIImage] = []

            for selectedFile in result {
                if isSecurityScoped {
                    if selectedFile.startAccessingSecurityScopedResource() {
                        defer { selectedFile.stopAccessingSecurityScopedResource() }

                        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                        let temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(selectedFile.lastPathComponent)

                        if FileManager.default.fileExists(atPath: temporaryFileURL.path) {
                            try FileManager.default.removeItem(at: temporaryFileURL)
                        }

                        // Try to find out what we got
                        guard let typeID = try selectedFile.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier, let supertypes = UTType(typeID)?.supertypes else {
                            Logger.shared.error("Unable to get structured type info for imported file")
                            errorController.push(message: String(localized: .localizable(.errorDefaultMessage)))
                            return
                        }

                        Logger.shared.debug("Have structured type info: \(supertypes)")
                        if supertypes.contains(.image) {
                            Logger.shared.debug("Have image")
                            let data = try Data(contentsOf: selectedFile)
                            if let image = UIImage(data: data) {
                                images.append(image)
                            } else {
                                Logger.shared.error("Could not load image from: \(selectedFile)")
                            }
                        } else {
                            Logger.shared.debug("Have PDF -> copy file ")
                            try FileManager.default.copyItem(at: selectedFile, to: temporaryFileURL)
                            importUrls.append(temporaryFileURL)
                            totalUrls += 1
                        }

                    } else {
                        Logger.shared.error("Document import: Access denied")
                        errorController.push(message: String(localized: .localizable(.errorDefaultMessage)))
                    }
                } else {
                    importUrls.append(selectedFile)
                    totalUrls += 1
                }
            }

            if !images.isEmpty {
                let pdf = try createPDFFrom(images: images)
                importUrls.append(pdf)
                totalUrls += 1
            }
        } catch {
            // Handle failure.
            Logger.shared.error("Unable to read file contents: \(error)")
            errorController.push(error: error)
        }
    }
}

struct DocumentModelWrapper: View {
    @ObservedObject var importModel: DocumentImportModel
    var callback: () -> Void
    let title: String

    var body: some View {
        if let url = importModel.next() {
            CreateDocumentView(
                sourceUrl: url,
                callback: callback,
                title: title
            )
            .id(url)
        } else {
            Text("😵")
                .font(.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}
