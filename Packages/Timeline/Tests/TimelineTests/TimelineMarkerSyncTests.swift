import Foundation
import Testing

@testable import Timeline

@Suite struct TimelineMarkerSyncTests {
  private let now = Date()

  @Test func ignoresRemoteMarkerWithSameId() {
    #expect(
      !TimelineMarkerSync.shouldApply(
        remoteLastReadId: "10", remoteUpdatedAt: now,
        localLastReadId: "10", localSeenAt: now.addingTimeInterval(-60)))
  }

  @Test func appliesRemoteMarkerWhenNoLocalPosition() {
    #expect(
      TimelineMarkerSync.shouldApply(
        remoteLastReadId: "10", remoteUpdatedAt: now,
        localLastReadId: nil, localSeenAt: nil))
  }

  @Test func appliesRemoteMarkerWhenNewerThanLocalPosition() {
    #expect(
      TimelineMarkerSync.shouldApply(
        remoteLastReadId: "10", remoteUpdatedAt: now,
        localLastReadId: "20", localSeenAt: now.addingTimeInterval(-60)))
  }

  @Test func ignoresAMarkerThisDeviceAlreadyWroteOrApplied() {
    #expect(
      !TimelineMarkerSync.shouldApply(
        remoteLastReadId: "10", remoteUpdatedAt: now,
        localLastReadId: nil, localSeenAt: nil, lastSyncedAt: now))
    #expect(
      TimelineMarkerSync.shouldApply(
        remoteLastReadId: "10", remoteUpdatedAt: now.addingTimeInterval(60),
        localLastReadId: nil, localSeenAt: nil, lastSyncedAt: now))
  }

  @Test func followsTheRemoteMarkerWithoutComparingClocksWhenNothingMovedHere() {
    // The remote marker only looks older than the last local change because this device's clock
    // runs ahead of the server's.
    #expect(
      TimelineMarkerSync.shouldApply(
        remoteLastReadId: "10", remoteUpdatedAt: now.addingTimeInterval(-600),
        localLastReadId: "20", localSeenAt: now,
        lastSyncedAt: now.addingTimeInterval(-900), movedSinceSync: false))
  }

  @Test func comparesClocksWhenThePositionMovedAfterTheLastSync() {
    #expect(
      !TimelineMarkerSync.shouldApply(
        remoteLastReadId: "10", remoteUpdatedAt: now.addingTimeInterval(-60),
        localLastReadId: "20", localSeenAt: now,
        lastSyncedAt: now.addingTimeInterval(-900), movedSinceSync: true))
  }

  @Test func keepsLocalPositionWhenItIsNewerThanRemoteMarker() {
    #expect(
      !TimelineMarkerSync.shouldApply(
        remoteLastReadId: "10", remoteUpdatedAt: now.addingTimeInterval(-60),
        localLastReadId: "20", localSeenAt: now))
  }
}
