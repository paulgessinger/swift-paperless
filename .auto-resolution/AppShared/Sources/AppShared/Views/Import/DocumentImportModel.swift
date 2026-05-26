//
//  DocumentImportModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 17.05.2024.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import os

@MainActor
public class DocumentImportModel: ObservableObject {
  public init() {}

  @Published
  public var importUrls: [URL] = []
  @Published
  public var totalUrls = 0

  public var remaining: Int {
    totalUrls - importUrls.count + 1
  }

  public func reset() {
    importUrls = []
    totalUrls = 0
  }

  public func next() -> URL? {
    importUrls.first
  }

  public func pop() {
    if importUrls.count > 1 {
      importUrls.removeFirst()
    }
    if importUrls.count == 1 {
      done = true
    }
  }

  @Published
  public private(set) var done: Bool = false

  // @TODO: Separate view model which does the copying on a background thread
  public func importFile(result: [URL], isSecurityScoped: Bool, errorController: ErrorController)
    async
  {
    Logger.shared.debug("Initiate import of \(result.count) URLs")
    do {
      var images: [UIImage] = []

      for selectedFile in result {
        if isSecurityScoped {
          if selectedFile.startAccessingSecurityScopedResource() {
            defer { selectedFile.stopAccessingSecurityScopedResource() }

            let temporaryDirectoryURL = URL(
              fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let normalizedFilename = selectedFile.lastPathComponent
              .precomposedStringWithCanonicalMapping
            let temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(
              normalizedFilename)

            if FileManager.default.fileExists(atPath: temporaryFileURL.path) {
              try FileManager.default.removeItem(at: temporaryFileURL)
            }

            // Try to find out what we got
            guard
              let typeID = try selectedFile.resourceValues(forKeys: [.typeIdentifierKey])
                .typeIdentifier, let supertypes = UTType(typeID)?.supertypes
            else {
              Logger.shared.error("Unable to get structured type info for imported file")
              errorController.push(message: String(localized: .app(.errorDefaultMessage)))
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
            errorController.push(message: String(localized: .app(.errorDefaultMessage)))
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

public struct DocumentModelWrapper: View {
  @ObservedObject public var importModel: DocumentImportModel
  public var callback: () -> Void
  public let title: String

  public init(importModel: DocumentImportModel, callback: @escaping () -> Void, title: String) {
    self._importModel = ObservedObject(wrappedValue: importModel)
    self.callback = callback
    self.title = title
  }

  public var body: some View {
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
