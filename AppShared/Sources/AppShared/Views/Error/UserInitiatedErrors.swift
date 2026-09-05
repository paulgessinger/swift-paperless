//
//  UserInitiatedErrors.swift
//  AppShared
//
//  Entry points for failures the *user* asked for. `push(error:)` alone can't
//  serve them: its suppression policy (`ErrorSuppression.swift`) keys only on
//  the error class, so it can't tell who asked or what was at risk. Three
//  tiers, keyed on both:
//
//  1. Background / automatic failure — stays silent. Keep using
//     `push(error:)`; the suppression policy is exactly right for it.
//  2. User-initiated *read* (a pull-to-refresh, a "Sync now") —
//     `push(readError:)`. Nothing was lost and the cached content is still on
//     screen, so an error is the wrong shape; while offline this re-shows the
//     offline indicator instead of saying nothing at all.
//  3. User-initiated *mutation* (a save, an edit, a delete) —
//     `push(mutationError:)`. Always surfaces, offline included.
//
//  Tier 3 is the one that has to bypass suppression. Write-through is
//  pessimistic — `CachingRepository.update(document:)` has no offline
//  fallback, and there is no outbox and no later sync that picks the change
//  up — so a rejected write is *gone*. Silence is then indistinguishable from
//  "pending", and the user walks away believing their edit is queued.
//

import Foundation
import Networking
import os

/// A user-initiated write that failed because the device is offline.
///
/// The message deliberately carries the *outcome*, not just the cause: "you're
/// offline" invites the inference "it'll sync later", which is wrong here.
/// Given no offline mutations are planned, that wording is permanent rather
/// than interim.
struct OfflineMutationFailure: DisplayableError {
  let underlying: any Error

  var message: String { String(localized: .app(.errorNotSavedOffline)) }
  var details: String? { underlying.localizedDescription }
}

extension ErrorController {
  /// Tier 3: surface the failure of a user-initiated **mutation**.
  ///
  /// Never consults `shouldSuppress` — the surfaces that policy defers to say
  /// nothing about a write having been dropped, and the offline toast it names
  /// only fires on the *transition* offline, not for the rest of the session.
  public func push(mutationError error: any Error) {
    if isOffline?() == true, Self.isConnectivityError(error) {
      Logger.shared.error("User-initiated mutation rejected while offline: \(error)")
      present(OfflineMutationFailure(underlying: error))
      return
    }
    present(displayable(for: error, message: nil))
  }

  /// Tier 2: surface the failure of a user-initiated **read**.
  ///
  /// While offline this re-shows the offline indicator rather than an error:
  /// nothing was lost, cached content is still on screen, and the user did ask
  /// for *something* to happen, so silence is wrong too. Everything else keeps
  /// the normal policy — a server that is unreachable while the device is
  /// online is still a real error worth a banner.
  public func push(readError error: any Error) {
    if isOffline?() == true, Self.isConnectivityError(error) {
      Logger.shared.debug("User-initiated read blocked while offline: \(error)")
      offlineNoticeSubject.send()
      return
    }
    push(error: error)
  }
}
