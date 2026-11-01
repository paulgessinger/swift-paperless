//
//  UploadDefaults.swift
//  AppShared
//
//  The tags preselected when uploading to one server, shared by the upload
//  form and the Preferences screen.
//

import DataModel
import Foundation
import Persistence
import os

@MainActor
@Observable
public final class UploadDefaults {
  public let serverID: UUID

  /// Setting this writes the new selection through to the database.
  public var tags: [UInt] {
    didSet {
      if tags != oldValue { save() }
    }
  }

  @ObservationIgnored private let database: Database

  /// The latest write. Each one waits for the one before it, so the last
  /// selection is what stays.
  @ObservationIgnored private(set) var saveTask: Task<Void, Never>?

  private init(database: Database, serverID: UUID, tags: [UInt]) {
    self.database = database
    self.serverID = serverID
    self.tags = tags
  }

  /// `nil` if they can't be read, so a failed read can't be saved over them.
  static func load(database: Database, serverID: UUID) async -> UploadDefaults? {
    do {
      let tags = try await database.defaultUploadTags(serverID: serverID)
      return UploadDefaults(database: database, serverID: serverID, tags: tags)
    } catch {
      Logger.shared.error("Could not load default upload tags: \(error)")
      return nil
    }
  }

  private func save() {
    saveTask = Task { [saveTask, database, serverID, tags] in
      await saveTask?.value
      do {
        try await database.setDefaultUploadTags(tags, serverID: serverID)
      } catch {
        Logger.shared.error("Could not save default upload tags: \(error)")
      }
    }
  }

  /// `ids` without the tags missing from `known`, which would fail an upload: a
  /// default tag can be deleted after it was picked. Unchanged while no tags
  /// are loaded, when there is nothing to tell them apart with.
  public static func existingTags(_ ids: [UInt], in known: [UInt: Tag]) -> [UInt] {
    guard !known.isEmpty else { return ids }
    return ids.filter { known[$0] != nil }
  }
}
