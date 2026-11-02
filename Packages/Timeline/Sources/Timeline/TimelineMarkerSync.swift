import Foundation

nonisolated enum TimelineMarkerSync {
  /// Decides whether a marker stored on the server should replace this device's position.
  /// Timestamps break the tie, not status IDs, as ID ordering is not guaranteed across servers.
  static func shouldApply(
    remoteLastReadId: String,
    remoteUpdatedAt: Date,
    localLastReadId: String?,
    localSeenAt: Date?,
    lastSyncedAt: Date? = nil
  ) -> Bool {
    guard remoteLastReadId != localLastReadId else { return false }
    // `lastSyncedAt` is the server date of the marker this device last wrote or applied: nothing
    // newer was written by another device since, so there is nothing to follow.
    if let lastSyncedAt, remoteUpdatedAt <= lastSyncedAt { return false }
    guard localLastReadId != nil, let localSeenAt else { return true }
    return remoteUpdatedAt > localSeenAt
  }
}
