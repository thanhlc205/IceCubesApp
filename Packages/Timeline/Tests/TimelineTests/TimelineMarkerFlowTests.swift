import Foundation
import Models
import NetworkClient
import Testing

@testable import Timeline

actor ScriptedStatusFetcher: TimelineStatusFetching {
  private let pages: [String: [Status]]
  private let olderPage: [Status]
  private var failsNextPage = false

  init(pages: [String: [Status]], olderPage: [Status] = []) {
    self.pages = pages
    self.olderPage = olderPage
  }

  func failNextPages() {
    failsNextPage = true
  }

  func fetchFirstPage(client: MastodonClient?, timeline: TimelineFilter) async throws -> [Status] {
    pages[timeline.id] ?? []
  }

  func fetchNewPages(
    client: MastodonClient?, timeline: TimelineFilter, minId: String, maxPages: Int
  ) async throws -> [Status] {
    []
  }

  func fetchNextPage(
    client: MastodonClient?, timeline: TimelineFilter, lastId: String, offset: Int
  ) async throws -> [Status] {
    if failsNextPage { throw URLError(.notConnectedToInternet) }
    return olderPage
  }
}

actor RecordingMarkerFetcher: TimelineMarkerFetching {
  private(set) var remote: Marker.Content?
  private(set) var saved: [String] = []
  private(set) var markerRequests = 0
  private(set) var statusRequests: [String] = []
  private let statuses: [String: Status]
  /// How far the server's clock is ahead of this device's.
  private let serverClockOffset: TimeInterval
  private var writes = 0

  init(statuses: [Status] = [], serverClockOffset: TimeInterval = 0) {
    self.statuses = Dictionary(uniqueKeysWithValues: statuses.map { ($0.id, $0) })
    self.serverClockOffset = serverClockOffset
  }

  /// Simulates another device writing the Home marker `ahead` seconds from now, by default a
  /// moment after this one last scrolled.
  func writeFromAnotherDevice(lastReadId: String, ahead: TimeInterval = 1) throws {
    remote = try Self.makeContent(
      lastReadId: lastReadId, version: writes + 1,
      at: Date().addingTimeInterval(serverClockOffset + ahead))
    writes += 1
  }

  func fetchHomeMarker(client: MastodonClient) async throws -> Marker.Content? {
    markerRequests += 1
    return remote
  }

  func saveHomeMarker(client: MastodonClient, lastReadId: String) async throws -> Marker.Content? {
    saved.append(lastReadId)
    writes += 1
    remote = try Self.makeContent(
      lastReadId: lastReadId, version: writes, at: Date().addingTimeInterval(serverClockOffset))
    return remote
  }

  func fetchStatus(client: MastodonClient, id: String) async throws -> Status {
    statusRequests.append(id)
    guard let status = statuses[id] else { throw URLError(.fileDoesNotExist) }
    return status
  }

  private static func makeContent(lastReadId: String, version: Int, at date: Date) throws
    -> Marker.Content
  {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let json = """
      {"last_read_id": "\(lastReadId)", "version": \(version), \
      "updated_at": "\(formatter.string(from: date))"}
      """
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Marker.Content.self, from: Data(json.utf8))
  }
}

/// A post as the server returns it: newer posts have higher ids and later dates.
private func post(_ id: String) -> Status {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  let postedAt = Date().addingTimeInterval(-TimeInterval(1_000 - (Int(id) ?? 0)))
  let json = "\"\(formatter.string(from: postedAt))\""
  let createdAt = try? JSONDecoder().decode(ServerDate.self, from: Data(json.utf8))
  return makeStatus(id: id, hidden: false, createdAt: createdAt)
}

@MainActor
final class MarkerHarness {
  let markers: RecordingMarkerFetcher
  let statuses: ScriptedStatusFetcher
  let subject: TimelineViewModel
  let client = MastodonClient(
    server: "marker-test-\(UUID().uuidString.prefix(8)).example",
    oauthToken: OauthToken(accessToken: "token", tokenType: "Bearer", scope: "read write", createdAt: 1))
  private let cache = TimelineCache()
  private var visible: [Status] = []

  let home = [post("300"), post("299")]
  let local = [post("900"), post("899")]
  let otherDevice = post("250")
  let older = [post("249"), post("248")]

  init(serverClockOffset: TimeInterval = 0) {
    markers = RecordingMarkerFetcher(
      statuses: home + local + [otherDevice], serverClockOffset: serverClockOffset)
    statuses = ScriptedStatusFetcher(
      pages: [TimelineFilter.home.id: home, TimelineFilter.local.id: local], olderPage: older)
    subject = TimelineViewModel(statusFetcher: statuses, markerFetcher: markers)
    subject.client = client
  }

  /// Opens a timeline and scrolls so that `status` is the topmost visible post.
  func visit(_ timeline: TimelineFilter, scrolledTo status: Status) async {
    for status in visible { subject.statusDidDisappear(status: status) }
    subject.timeline = timeline
    await subject.timelineTask?.value
    subject.statusDidAppear(status: status)
    visible = [status]
    await eventually {
      await self.cache.getLatestSeenStatus(for: self.client, filter: timeline.id)?.first == status.id
    }
  }

  /// Puts `statuses` on screen without changing the timeline, as the list does after scrolling.
  func show(_ statuses: [Status]) async {
    for status in visible { subject.statusDidDisappear(status: status) }
    for status in statuses { subject.statusDidAppear(status: status) }
    visible = statuses
    await eventually {
      let seen = await self.cache.getLatestSeenStatus(for: self.client, filter: TimelineFilter.home.id)
      return Set(seen ?? []) == Set(statuses.map(\.id))
    }
  }

  func homeIds() async -> [String] {
    await subject.datasource.get().map(\.id)
  }

  /// Lets fire-and-forget tasks started by the view model finish.
  func settle() async {
    try? await Task.sleep(for: .milliseconds(300))
  }

  func eventually(_ condition: @escaping () async -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(3)
    while ContinuousClock.now < deadline {
      if await condition() { return }
      try? await Task.sleep(for: .milliseconds(20))
    }
  }
}

@MainActor
@Suite("Timeline marker flow")
struct TimelineMarkerFlowTests {
  @Test func leavingHomeSavesTheHomePositionNotTheNextTimelines() async {
    let harness = MarkerHarness()
    await harness.visit(.home, scrolledTo: harness.home[0])
    await harness.visit(.local, scrolledTo: harness.local[0])
    await harness.visit(.home, scrolledTo: harness.home[0])
    await harness.visit(.local, scrolledTo: harness.local[0])
    await harness.eventually { await !harness.markers.saved.isEmpty }
    await harness.settle()

    let saved = await harness.markers.saved
    #expect(Set(saved) == ["300"])
  }

  @Test func comingBackToHomeKeepsTheHomeList() async {
    let harness = MarkerHarness()
    await harness.visit(.home, scrolledTo: harness.home[0])
    await harness.visit(.local, scrolledTo: harness.local[0])
    await harness.visit(.home, scrolledTo: harness.home[0])
    await harness.visit(.local, scrolledTo: harness.local[0])
    await harness.settle()
    await harness.visit(.home, scrolledTo: harness.home[0])

    #expect(await harness.markers.statusRequests.isEmpty)
    #expect(await harness.homeIds().first == "300")
  }

  @Test func switchingTimelinesDoesNotSyncAgainInTheSameSession() async throws {
    let harness = MarkerHarness()
    await harness.visit(.home, scrolledTo: harness.home[0])
    try await harness.markers.writeFromAnotherDevice(lastReadId: "250")

    await harness.visit(.local, scrolledTo: harness.local[0])
    await harness.visit(.home, scrolledTo: harness.home[0])

    #expect(await harness.markers.markerRequests == 1)
    #expect(await harness.markers.statusRequests.isEmpty)
  }

  @Test func returningToTheForegroundFollowsAnotherDevice() async throws {
    let harness = MarkerHarness()
    await harness.visit(.home, scrolledTo: harness.home[0])
    try await harness.markers.writeFromAnotherDevice(lastReadId: "250")

    harness.subject.refreshTimeline()
    await harness.subject.timelineTask?.value

    #expect(await harness.markers.statusRequests == ["250"])
    // Newer posts are loaded above the position of the other device, which stays in the list.
    #expect(await harness.homeIds() == ["300", "299", "250", "249", "248"])
    #expect(harness.subject.scrollToId == "250")
    #expect(harness.subject.marker == nil)
  }

  @Test func theSameRemotePositionIsOnlyAppliedOnce() async throws {
    let harness = MarkerHarness()
    await harness.visit(.home, scrolledTo: harness.home[0])
    try await harness.markers.writeFromAnotherDevice(lastReadId: "250")

    harness.subject.refreshTimeline()
    await harness.subject.timelineTask?.value
    harness.subject.refreshTimeline()
    await harness.subject.timelineTask?.value

    #expect(await harness.markers.statusRequests == ["250"])
  }

  @Test func aFailedFetchDoesNotLeaveAStaleMarkerBehind() async throws {
    let harness = MarkerHarness()
    await harness.visit(.home, scrolledTo: harness.home[0])
    try await harness.markers.writeFromAnotherDevice(lastReadId: "250")
    await harness.statuses.failNextPages()

    harness.subject.refreshTimeline()
    await harness.subject.timelineTask?.value

    #expect(harness.subject.marker == nil)
    #expect(await harness.homeIds().first == "300")
  }

  @Test func applyingAnotherDevicesPositionDoesNotWriteADifferentOneBack() async throws {
    let harness = MarkerHarness()
    await harness.visit(.home, scrolledTo: harness.home[0])
    try await harness.markers.writeFromAnotherDevice(lastReadId: "250")

    harness.subject.refreshTimeline()
    await harness.subject.timelineTask?.value
    // The list scrolls to the applied post, with the newer post above it partly on screen too.
    await harness.show([harness.home[1], harness.otherDevice])
    harness.subject.saveMarker()
    await harness.settle()

    #expect(await harness.markers.saved.isEmpty)
  }

  @Test func scrollingOnAfterApplyingAnotherDevicesPositionSavesTheNewOne() async throws {
    let harness = MarkerHarness()
    await harness.visit(.home, scrolledTo: harness.home[0])
    try await harness.markers.writeFromAnotherDevice(lastReadId: "250")

    harness.subject.refreshTimeline()
    await harness.subject.timelineTask?.value
    await harness.show([harness.home[1], harness.otherDevice])
    await harness.show([harness.older[0]])
    harness.subject.saveMarker()
    await harness.eventually { await !harness.markers.saved.isEmpty }

    #expect(await harness.markers.saved == ["249"])
  }

  @Test func followsAnotherDeviceWhenThisDevicesClockRunsAhead() async throws {
    // The server's clock is ten minutes behind this device's, so its dates look old.
    let harness = MarkerHarness(serverClockOffset: -600)
    await harness.visit(.home, scrolledTo: harness.home[0])
    harness.subject.saveMarker()
    await harness.eventually { await !harness.markers.saved.isEmpty }
    await harness.settle()
    try await harness.markers.writeFromAnotherDevice(lastReadId: "250")

    harness.subject.refreshTimeline()
    await harness.subject.timelineTask?.value

    #expect(await harness.markers.statusRequests == ["250"])
  }

  @Test func keepsAPositionMovedAfterTheOtherDevicesWrite() async throws {
    let harness = MarkerHarness()
    await harness.visit(.home, scrolledTo: harness.home[0])
    harness.subject.saveMarker()
    await harness.eventually { await !harness.markers.saved.isEmpty }
    await harness.settle()
    try await harness.markers.writeFromAnotherDevice(lastReadId: "250", ahead: 0)
    await harness.settle()
    // The user keeps reading here after the other device wrote, and has not saved that yet.
    await harness.show([harness.home[1]])

    harness.subject.refreshTimeline()
    await harness.subject.timelineTask?.value

    #expect(await harness.markers.statusRequests.isEmpty)
  }
}
