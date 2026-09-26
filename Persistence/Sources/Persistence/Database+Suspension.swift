import Foundation
import GRDB
import os

/// Database suspension: the app-side half of GRDB's `0xDEAD10CC` mitigation.
///
/// iOS kills a process that still holds a SQLite lock as it is suspended, and
/// a sync writing the caches is exactly what is in flight when the user
/// switches away. Suspending a connection rolls back its running statement and
/// refuses new write locks, so there is no lock left to be killed over. Reads
/// keep working — `DatabasePool` suspends only its writer.
///
/// Only a connection opened with `observesSuspensionNotifications` reacts,
/// which here is the production one alone.
///
/// - Note: GRDB marks the technique experimental; see its `DatabaseSharing`
///   guide.
extension Database {
  /// Suspend the writer, on `UIApplication.didEnterBackgroundNotification`.
  /// `AppDelegate` owns that wiring and says there why it is the notification.
  ///
  /// The writes this aborts surface as `CancellationError` — see
  /// ``wrappingAsync(_:_:)``.
  public static func suspend() {
    // Logged both sides: a missing pair is what tells "the observer never
    // fired" apart from "the writes were let through".
    Logger.persistence.notice("Suspending database")
    NotificationCenter.default.post(name: GRDB.Database.suspendNotification, object: nil)
  }

  /// Undo ``suspend()``, on `UIApplication.willEnterForegroundNotification`.
  /// Until it runs every write is refused.
  public static func resume() {
    Logger.persistence.notice("Resuming database")
    NotificationCenter.default.post(name: GRDB.Database.resumeNotification, object: nil)
  }
}
