//
//  DocumentChatView.swift
//  swift-paperless
//
//  Chat with your documents through paperless-ngx's AI chat
//  (`POST /api/documents/chat/`). Only offered when the server reports
//  `ai_enabled` in its UI settings.
//

import AppShared
import Common
import DataModel
import MarkdownUI
import Networking
import SwiftUI
import os

// MARK: - Model

@MainActor
@Observable
final class DocumentChatModel {
  enum Role {
    case user
    case assistant
  }

  struct Message: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    var content: String
    var references: [DocumentChatReference] = []
    var isStreaming = false
    /// Why the answer failed, if it did.
    var error: String?
  }

  /// When nil, questions go to every document the user can see.
  let documentId: UInt?

  private(set) var messages: [Message] = []
  var input = ""
  private(set) var isResponding = false
  /// Set once an answer has taken a while to start, like the web UI does.
  private(set) var isSlow = false

  @ObservationIgnored
  private var responseTask: Task<Void, Never>?

  static let slowResponseDelay: Duration = .seconds(8)

  init(documentId: UInt? = nil) {
    self.documentId = documentId
  }

  var canSend: Bool {
    !isResponding && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func send(repository: any Repository) {
    let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty, !isResponding else { return }

    input = ""
    messages.append(Message(role: .user, content: question))
    let answer = Message(role: .assistant, content: "", isStreaming: true)
    messages.append(answer)
    isResponding = true
    isSlow = false

    let answerID = answer.id
    let documentId = documentId

    responseTask = Task { [weak self] in
      let slowTimer = Task { [weak self] in
        guard (try? await Task.sleep(for: Self.slowResponseDelay)) != nil else { return }
        self?.isSlow = true
      }
      defer {
        slowTimer.cancel()
        self?.finish(answerID)
      }

      do {
        let stream = try await repository.documentChat(question: question, documentId: documentId)
        for try await raw in stream {
          let response = DocumentChatResponse(parsing: raw)
          if !response.content.isEmpty {
            slowTimer.cancel()
            self?.isSlow = false
          }
          self?.update(answerID) {
            $0.content = response.content
            $0.references = response.references
          }
        }
      } catch let error where error.isCancellationError {
        // Stopped by the user or the sheet closing: keep what arrived.
      } catch {
        Logger.shared.error("Document chat failed: \(error)")
        let detail = (error as? any DisplayableError)?.message
        self?.update(answerID) { $0.error = detail ?? String(localized: .app(.documentChatError)) }
      }
    }
  }

  /// Stops the answer being generated, keeping what has arrived so far.
  func stop() {
    responseTask?.cancel()
    responseTask = nil
  }

  func clear() {
    stop()
    messages = []
  }

  private func update(_ id: Message.ID, _ change: (inout Message) -> Void) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    change(&messages[index])
  }

  private func finish(_ id: Message.ID) {
    if let index = messages.firstIndex(where: { $0.id == id }) {
      messages[index].isStreaming = false
      // An answer stopped before anything arrived has nothing to show.
      if messages[index].content.isEmpty, messages[index].error == nil {
        messages.remove(at: index)
      }
    }
    isResponding = false
    isSlow = false
  }
}

// MARK: - View

struct DocumentChatView: View {
  @Environment(DocumentStore.self) private var store
  @Environment(NetworkMonitor.self) private var networkMonitor
  @Environment(\.dismiss) private var dismiss

  @State private var model: DocumentChatModel
  @FocusState private var inputFocused: Bool

  /// Called with the id of a source document the user tapped. The sheet
  /// dismisses itself first.
  private let onOpenDocument: (UInt) -> Void

  private static let bottomID = "bottom"

  init(documentId: UInt? = nil, onOpenDocument: @escaping (UInt) -> Void) {
    _model = State(initialValue: DocumentChatModel(documentId: documentId))
    self.onOpenDocument = onOpenDocument
  }

  private var isSingleDocument: Bool { model.documentId != nil }

  private var title: String {
    isSingleDocument
      ? String(localized: .app(.documentChatTitleSingleDocument))
      : String(localized: .app(.documentChatTitle))
  }

  private var placeholder: String {
    isSingleDocument
      ? String(localized: .app(.documentChatPlaceholderSingleDocument))
      : String(localized: .app(.documentChatPlaceholder))
  }

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(model.messages) { message in
              DocumentChatMessageRow(
                message: message,
                isSlow: model.isSlow,
                onOpenDocument: open
              )
              .id(message.id)
            }
          }
          .padding()

          Color.clear
            .frame(height: 1)
            .id(Self.bottomID)
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay {
          if model.messages.isEmpty {
            emptyState
          }
        }
        .onChange(of: model.messages) {
          withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
          }
        }
      }
      .safeAreaInset(edge: .bottom) {
        inputBar
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: .app(.done))) {
            dismiss()
          }
        }

        if !model.messages.isEmpty {
          ToolbarItem(placement: .topBarLeading) {
            Button {
              model.clear()
              inputFocused = true
            } label: {
              Label(
                String(localized: .app(.documentChatClear)),
                systemImage: "arrow.counterclockwise")
            }
          }
        }
      }
    }
    .onAppear { inputFocused = true }
    .onDisappear { model.stop() }
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label(title, systemImage: "sparkles")
    } description: {
      Text(.app(.documentChatEmptyDescription))
    }
  }

  private var inputBar: some View {
    VStack(spacing: 8) {
      if !networkMonitor.isOnline {
        Label(String(localized: .app(.documentChatOffline)), systemImage: "wifi.slash")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      HStack(spacing: 8) {
        // Single line, so Return sends the question, as in the web UI.
        TextField(placeholder, text: $model.input)
          .focused($inputFocused)
          .submitLabel(.send)
          .onSubmit(send)
          .padding(.horizontal, 14)
          .padding(.vertical, 9)
          .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))

        if model.isResponding {
          Button {
            model.stop()
          } label: {
            Image(systemName: "stop.circle.fill")
              .font(.system(size: 32))
          }
          .accessibilityLabel(String(localized: .app(.documentChatStop)))
        } else {
          Button(action: send) {
            Image(systemName: "arrow.up.circle.fill")
              .font(.system(size: 32))
          }
          .disabled(!model.canSend || !networkMonitor.isOnline)
          .accessibilityLabel(String(localized: .app(.documentChatSend)))
        }
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.bar)
  }

  private func send() {
    guard networkMonitor.isOnline else { return }
    model.send(repository: store.repository)
  }

  private func open(_ documentID: UInt) {
    dismiss()
    onOpenDocument(documentID)
  }
}

// MARK: - Message row

private struct DocumentChatMessageRow: View {
  let message: DocumentChatModel.Message
  let isSlow: Bool
  let onOpenDocument: (UInt) -> Void

  var body: some View {
    switch message.role {
    case .user:
      HStack {
        Spacer(minLength: 48)
        Text(message.content)
          .textSelection(.enabled)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 18))
      }

    case .assistant:
      VStack(alignment: .leading, spacing: 10) {
        if message.isStreaming && message.content.isEmpty {
          HStack(spacing: 8) {
            ProgressView()
            Text(
              isSlow
                ? String(localized: .app(.documentChatStillThinking))
                : String(localized: .app(.documentChatThinking)))
          }
          .foregroundStyle(.secondary)
        } else if !message.content.isEmpty {
          Markdown(message.content)
            .textSelection(.enabled)
        }

        if let error = message.error {
          Label(error, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.orange)
        }

        if !message.isStreaming && !message.references.isEmpty {
          references
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var references: some View {
    VStack(alignment: .leading, spacing: 6) {
      Divider()
      Text(.app(.documentChatSources))
        .font(.caption)
        .foregroundStyle(.secondary)
      ForEach(message.references) { reference in
        Button {
          onOpenDocument(reference.id)
        } label: {
          Label(reference.title, systemImage: "doc.text")
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .font(.callout)
      }
    }
  }
}

// MARK: - Previews

#Preview("Chat") {
  @Previewable @State var store = DocumentStore.preview()
  @Previewable @State var networkMonitor = NetworkMonitor()

  DocumentChatView { _ in }
    .environment(store)
    .environment(networkMonitor)
}
