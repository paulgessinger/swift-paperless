//
//  ShareLinkView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.01.26.
//

import Common
import DataModel
import Networking
import SwiftUI
import os

extension DataModel.ShareLink.FileVersion {
  var localizedName: String {
    let res: LocalizedStringResource =
      switch self {
      case .original: .shareLink(.originalLabel)
      case .archive: .shareLink(.archiveLabel)
      }

    return String(localized: res)
  }
}

struct ShareLinkView: View {
  let document: Document

  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController
  @EnvironmentObject private var connectionManager: ConnectionManager

  @ScaledMetric(relativeTo: .body) var fontSize = 14

  @State private var shareLinks: [DataModel.ShareLink] = []
  @State private var showCreate = false

  private func shareLinkUrl(for shareLink: DataModel.ShareLink) -> URL {

    if let connection = connectionManager.connection {
      return Endpoint.publicUrl(forShareLink: shareLink).url(url: connection.url)!
    }

    return URL(string: "blubb")!
  }

  private func delete(at offsets: IndexSet) {
    for (i, link) in shareLinks.enumerated() {
      guard offsets.contains(i) else { continue }
      Task {
        do {
          try await store.repository.delete(shareLink: link)
        } catch {
          Logger.shared.error("Error deleting share link: \(error)")
          errorController.push(error: error)
        }
      }
    }
    shareLinks.remove(atOffsets: offsets)
  }

  private func load() async {
    do {
      shareLinks = try await store.repository.shareLinks(documentId: document.id)
    } catch {
      Logger.shared.error("Error getting share links for document: \(document.id): \(error)")
      errorController.push(error: error)
    }
  }

  @ViewBuilder
  private func row(_ shareLink: DataModel.ShareLink) -> some View {
    let url = shareLinkUrl(for: shareLink)
    HStack {

      VStack(alignment: .leading, spacing: 5) {
        Text(url.absoluteString)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .lineLimit(1)

        HStack {
          Text(shareLink.fileVersion.localizedName)

          if let expiration = shareLink.expiration {

            let days = Calendar.current.dateComponents([.day], from: .now, to: expiration).day ?? 0
            Text(.shareLink(.expiresInDays(days.magnitude)))
          }
        }
        .font(.system(size: fontSize, design: .default))
        .foregroundStyle(.secondary)
      }
      SwiftUI.ShareLink(item: url)
        .labelStyle(.iconOnly)
        .font(.title)
        .padding(.leading, 10)
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        if shareLinks.isEmpty {
          ContentUnavailableView(.shareLink(.noShareLinksTitle), systemImage: "link")
        } else {
          ForEach(shareLinks) { row($0) }
            .onDelete(perform: delete)
        }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          CancelIconButton()
        }

        ToolbarItem {
          Button(.localizable(.add), systemImage: "plus") {
            showCreate = true
          }
        }
      }

      .animation(.spring, value: shareLinks)

      .refreshable {
        await Task {
          await load()
        }.value
      }

      .navigationTitle(.shareLink(.title))
      .navigationBarTitleDisplayMode(.inline)

      .errorOverlay(errorController: errorController)
    }

    .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) {
      CreateShareLinkView(document: document)
    }

    .task {
      await load()
    }
  }
}

extension DataModel.ShareLink.FileVersion {
  fileprivate var toggle: Bool {
    get {
      self == .archive
    }
    set {
      self = newValue ? .archive : .original
    }
  }
}

private struct CreateShareLinkView: View {
  @EnvironmentObject private var errorController: ErrorController
  @EnvironmentObject private var store: DocumentStore

  @Environment(\.dismiss) private var dismiss

  @State private var shareLink: ProtoShareLink

  @State private var expirationValues: [(UInt, Date)]
  private let timeZone = TimeZone(secondsFromGMT: 0)!

  init(document: Document) {
    _shareLink = State(initialValue: ProtoShareLink(document: document.id))
    let now = Date.now
    expirationValues = [1, 7, 30].map {
      ($0.magnitude, Calendar.current.date(byAdding: .day, value: $0, to: now)!)
    }

    _expirationValues = State(initialValue: expirationValues)
  }

  private func save() {
    Task {
      do {
        Logger.shared.info(
          "Creating new share link for document \(shareLink.document) with expiration date \(String(describing: shareLink.expiration))"
        )

        _ = try await store.repository.create(shareLink: shareLink)

        dismiss()
      } catch {
        Logger.shared.error("Failed to create share link: \(error)")
        errorController.push(error: error)
      }
    }
  }

  private func expirationDate(for days: UInt) -> Date? {
    Calendar.current.date(byAdding: .day, value: Int(days), to: .now)
  }

  var body: some View {
    NavigationStack {
      Form {
        LabeledContent {
          Picker(.shareLink(.expirationLabel), selection: $shareLink.expiration) {
            Text(.shareLink(.createExpirationNever))
              .tag(nil as Date?)

            ForEach(expirationValues, id: \.0) { (days, date) in
              Text(.shareLink(.createExpirationDays(days)))
                .tag(date as Date?)
            }
          }
          .pickerStyle(.segmented)
        } label: {
          Text(.shareLink(.expirationLabel))
        }

        Toggle(.shareLink(.fileVersionLabel), isOn: $shareLink.fileVersion.toggle)
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          CancelIconButton()
        }

        ToolbarItem(placement: .confirmationAction) {
          SaveButton(action: save)
        }
      }

      .navigationTitle(.shareLink(.createTitle))
      .navigationBarTitleDisplayMode(.inline)
      .errorOverlay(errorController: errorController)
    }
  }

}

#Preview {
  @Previewable
  @StateObject var store = DocumentStore(repository: TransientRepository())

  @Previewable
  @StateObject var errorController = ErrorController()

  @Previewable
  @StateObject var connectionManager = ConnectionManager()

  @Previewable @State var document: Document? = nil

  VStack {
    if let document {
      ShareLinkView(document: document)
    }
  }
  .environmentObject(store)
  .environmentObject(errorController)
  .environmentObject(connectionManager)
  .task {
    do {
      let protoDoc = ProtoDocument(
        title: "Invoice",
        asn: nil,
        documentType: nil,
        correspondent: nil,
        tags: [],
        created: .now,
        storagePath: nil
      )
      try await store.repository.create(
        document: protoDoc, file: URL(string: "file:///abc.pdf")!, filename: "abc.pdf"
      )

      let allDocuments = try store.repository.documents(filter: .default)
      document = try await allDocuments.fetch(limit: 10000).first

      _ = try await store.repository.create(shareLink: ProtoShareLink(document: document!.id))

      for i in 1..<4 {
        _ = try await store.repository.create(
          shareLink: ProtoShareLink(
            document: document!.id,
            expiration: Calendar.current.date(byAdding: .day, value: i, to: .now)
          ))
      }

      let connection = StoredConnection(
        url: #URL("https://example-iama-very-long-url-that-will-break.com"),
        extraHeaders: [],
        user: User(id: 1, isSuperUser: true, username: "admin")
      )

      connectionManager.login(connection)
    } catch {
      print("Error: \(error)")
    }
  }
}
