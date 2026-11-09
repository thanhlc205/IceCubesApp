import Env
import Foundation
import Models
import NetworkClient
import Testing

@testable import Notifications

/// Every notification type except `type`, as `exclude_types[]` sends them.
private func allTypes(except type: String) -> Set<String> {
  Set([
    "follow", "follow_request", "mention", "reblog", "status", "favourite", "poll", "update",
    "quote", "quoted_update", "added_to_collection", "collection_update",
  ]).subtracting([type])
}

/// The data source runs against a real `MastodonClient` whose requests `StubServer` answers.
/// `.serialized` because the stub and the shared `CurrentInstance` are global.
@MainActor
@Suite(.serialized)
struct NotificationsListDataSourceTests {
  private let client = MastodonClient(server: "stub.example")
  private let dataSource = NotificationsListDataSource()

  init() {
    StubServer.install()
    StubServer.reset()
  }

  /// Sets the server version in the shared `CurrentInstance`, which the data source reads to
  /// choose between the grouped (Mastodon 4.3+) and ungrouped APIs. `nil` leaves the version
  /// unknown, as when fetching it fails.
  private func useServer(version: String?) async {
    if let version {
      StubServer.enqueue("/api/v2/instance", json: Fixture.instance(version: version))
    }
    let instance = CurrentInstance.shared
    instance.setClient(client: client)
    await instance.fetchCurrentInstance()
    #expect(instance.isGroupedNotificationsSupported == (version != nil))
  }

  private func load(
    _ type: Models.Notification.NotificationType? = nil, lockedAccountId: String? = nil
  ) async throws -> NotificationsListDataSource.FetchResult {
    try await dataSource.fetchNotifications(
      client: client, selectedType: type, lockedAccountId: lockedAccountId)
  }

  private func loadNextPage() async throws -> NotificationsListDataSource.FetchResult {
    try await dataSource.fetchNextPage(client: client, selectedType: nil, lockedAccountId: nil)
  }

  private func stream(
    _ json: String,
    _ type: Models.Notification.NotificationType? = nil,
    lockedAccountId: String? = nil
  ) async throws -> NotificationsListDataSource.StreamEventResult? {
    let event = StreamEventNotification(notification: try Fixture.decodeNotification(json))
    return await dataSource.handleStreamEvent(
      event: event, selectedType: type, lockedAccountId: lockedAccountId)
  }

  // MARK: - Before Mastodon 4.3: the app groups notifications itself

  @Test func groupsFavouritesOfOneStatusAndAllFollowsIntoSingleRows() async throws {
    await useServer(version: nil)
    StubServer.enqueue(
      "/api/v1/notifications",
      json: Fixture.list([
        Fixture.notification("6", "mention", minute: 6, account: "a3", status: "s2"),
        Fixture.notification("5", "favourite", minute: 5, account: "a2", status: "s1"),
        Fixture.notification("4", "follow", minute: 4, account: "a4"),
        Fixture.notification("3", "favourite", minute: 3, account: "a1", status: "s1"),
        Fixture.notification("2", "follow", minute: 2, account: "a5"),
        Fixture.notification("1", "mention", minute: 1, account: "a1", status: "s3"),
      ]))

    let result = try await load()

    #expect(result.notifications.map(\.type) == [.mention, .favourite, .follow, .mention])
    #expect(
      result.notifications.map { $0.accounts.map(\.id) }
        == [["a3"], ["a2", "a1"], ["a4", "a5"], ["a1"]])
    #expect(result.notifications.map(\.mostRecentNotificationId) == ["6", "5", "4", "1"])
    #expect(result.notifications[1].status?.id == "s1")
    #expect(result.nextPageState == .none)
    #expect(!result.containsFollowRequests)

    let request = try #require(StubServer.requests("/api/v1/notifications").first)
    #expect(request.value("limit") == "30")
    #expect(request.values("exclude_types[]").isEmpty)
    #expect(request.value("max_id") == nil)
    #expect(request.value("min_id") == nil)
  }

  @Test func filteringByOneTypeExcludesTheOthersAndListsEachFollowOnItsOwn() async throws {
    await useServer(version: nil)
    StubServer.enqueue(
      "/api/v1/notifications",
      json: Fixture.list([
        Fixture.notification("2", "follow", minute: 2, account: "a2"),
        Fixture.notification("1", "follow", minute: 1, account: "a1"),
      ]))

    let result = try await load(.follow)

    #expect(result.notifications.map(\.mostRecentNotificationId) == ["2", "1"])
    let request = try #require(StubServer.requests("/api/v1/notifications").first)
    #expect(Set(request.values("exclude_types[]")) == allTypes(except: "follow"))
  }

  @Test func dropsNotificationsWhoseStatusAFilterHides() async throws {
    await useServer(version: nil)
    StubServer.enqueue(
      "/api/v1/notifications",
      json: Fixture.list([
        Fixture.notification(
          "2", "mention", minute: 2, account: "a2", status: "s2", hiddenStatus: true),
        Fixture.notification("1", "favourite", minute: 1, account: "a1", status: "s1"),
      ]))

    let result = try await load()

    #expect(result.notifications.map(\.mostRecentNotificationId) == ["1"])
  }

  @Test func reportsAPendingFollowRequest() async throws {
    await useServer(version: nil)
    StubServer.enqueue(
      "/api/v1/notifications",
      json: Fixture.list([Fixture.notification("1", "follow_request", minute: 1, account: "a2")]))

    let result = try await load()

    #expect(result.containsFollowRequests)
    #expect(result.notifications.map(\.type) == [.follow_request])
  }

  @Test func offersAnotherPageAfterAFullPageOnly() async throws {
    await useServer(version: nil)
    StubServer.enqueue("/api/v1/notifications", json: Fixture.mentions(count: 30, newestId: 30))
    StubServer.enqueue("/api/v1/notifications", json: Fixture.mentions(count: 5, newestId: 5))
    StubServer.enqueue("/api/v1/notifications", json: "[]")

    let full = try await load()
    let short = try await NotificationsListDataSource().fetchNotifications(
      client: client, selectedType: nil, lockedAccountId: nil)
    let empty = try await NotificationsListDataSource().fetchNotifications(
      client: client, selectedType: nil, lockedAccountId: nil)

    #expect(full.notifications.count == 30)
    #expect(full.nextPageState == .hasNextPage)
    #expect(short.notifications.count == 5)
    #expect(short.nextPageState == .none)
    #expect(empty.notifications.isEmpty)
    #expect(empty.nextPageState == .none)
  }

  @Test func offersAnotherPageAfterAFullPageThatGroupedIntoFewerRows() async throws {
    await useServer(version: nil)
    let mentions = (3...30).reversed().map {
      Fixture.notification(String($0), "mention", minute: $0, account: "a1", status: "s\($0)")
    }
    StubServer.enqueue(
      "/api/v1/notifications",
      json: Fixture.list(
        mentions + [
          Fixture.notification("2", "favourite", minute: 2, account: "a2", status: "s1"),
          Fixture.notification("1", "favourite", minute: 1, account: "a3", status: "s1"),
        ]))

    let result = try await load()

    // The server sent a full page of 30, which grouped into 29 rows.
    #expect(result.notifications.count == 29)
    withKnownIssue("Paging counts grouped rows, not the notifications the server sent") {
      #expect(result.nextPageState == .hasNextPage)
    }
  }

  @Test func lockedToOneAccountItFiltersByAccountEvenOnAGroupingServer() async throws {
    await useServer(version: "4.3.0")
    StubServer.enqueue(
      "/api/v1/notifications",
      json: Fixture.list([
        Fixture.notification("2", "mention", minute: 2, account: "a7", status: "s2"),
        Fixture.notification("1", "mention", minute: 1, account: "a7", status: "s1"),
      ]))

    let result = try await load(lockedAccountId: "a7")

    #expect(result.notifications.map(\.mostRecentNotificationId) == ["2", "1"])
    let request = try #require(StubServer.requests("/api/v1/notifications").first)
    #expect(request.value("account_id") == "a7")
    #expect(StubServer.requests("/api/v2/notifications").isEmpty)
  }

  @Test func refreshAddsOnlyNotificationsThatAreNotListedYet() async throws {
    await useServer(version: nil)
    StubServer.enqueue("/api/v1/notifications", json: Fixture.mentions(count: 2, newestId: 2))
    StubServer.enqueue("/api/v1/notifications", json: Fixture.mentions(count: 3, newestId: 4))
    StubServer.enqueue("/api/v1/notifications", json: "[]")

    _ = try await load()
    let refreshed = try await load()

    #expect(refreshed.notifications.map(\.mostRecentNotificationId) == ["4", "3", "2", "1"])
    let requests = StubServer.requests("/api/v1/notifications")
    #expect(requests.map { $0.value("min_id") } == [nil, "2", "4"])
  }

  @Test func refreshStopsAfterTenPages() async throws {
    await useServer(version: nil)
    StubServer.enqueue("/api/v1/notifications", json: Fixture.mentions(count: 1, newestId: 1))
    for id in 2...12 {
      StubServer.enqueue("/api/v1/notifications", json: Fixture.mentions(count: 1, newestId: id))
    }

    _ = try await load()
    let refreshed = try await load()

    #expect(refreshed.notifications.count == 11)
    #expect(refreshed.notifications.first?.mostRecentNotificationId == "11")
  }

  @Test func nextPageAsksForOlderNotificationsAndAppendsThem() async throws {
    await useServer(version: nil)
    StubServer.enqueue("/api/v1/notifications", json: Fixture.mentions(count: 30, newestId: 100))
    StubServer.enqueue("/api/v1/notifications", json: Fixture.mentions(count: 30, newestId: 70))
    StubServer.enqueue("/api/v1/notifications", json: Fixture.mentions(count: 5, newestId: 40))

    let first = try await load()
    let second = try await loadNextPage()
    let third = try await loadNextPage()

    #expect(first.nextPageState == .hasNextPage)
    #expect(second.notifications.count == 60)
    #expect(second.notifications.last?.mostRecentNotificationId == "41")
    #expect(second.nextPageState == .hasNextPage)
    #expect(third.notifications.count == 65)
    #expect(third.nextPageState == .none)
    let requests = StubServer.requests("/api/v1/notifications")
    #expect(requests.map { $0.value("max_id") } == [nil, "71", "41"])
  }

  @Test func loadingMarksTheNewestNotificationAsRead() async throws {
    await useServer(version: nil)
    StubServer.enqueue("/api/v1/notifications", json: Fixture.mentions(count: 2, newestId: 302))

    _ = try await load()

    let marker = try await StubServer.waitForRequest("/api/v1/markers", method: "POST") {
      String(decoding: $0.body ?? Data(), as: UTF8.self).contains("302")
    }
    let body = try #require(marker?.body)
    let json = try JSONSerialization.jsonObject(with: body) as? [String: [String: String]]
    #expect(json == ["notifications": ["last_read_id": "302"]])
  }

  // MARK: - Mastodon 4.3 and later: the server groups notifications

  @Test func groupedLoadBuildsOneRowPerServerGroup() async throws {
    await useServer(version: "4.3.0")
    StubServer.enqueue(
      "/api/v2/notifications",
      json: Fixture.grouped(
        groups: [
          Fixture.group(
            "favourite-s1-1", "favourite", mostRecentId: 50, minute: 50,
            accounts: ["a2", "a1"], status: "s1"),
          Fixture.group(
            "ungrouped-40", "mention", mostRecentId: 40, minute: 40, accounts: ["a3"],
            status: "s2"),
          // The response leaves out this group's account, so there's no one to show.
          Fixture.group("follow-1", "follow", mostRecentId: 30, minute: 30, accounts: ["a9"]),
          // A type this app doesn't know.
          Fixture.group(
            "ungrouped-20", "admin.sign_up", mostRecentId: 20, minute: 20, accounts: ["a1"]),
        ],
        accounts: ["a1", "a2", "a3"],
        statuses: ["s1", "s2"]))

    let result = try await load()

    #expect(result.notifications.map(\.id) == ["favourite-s1-1", "ungrouped-40"])
    #expect(result.notifications.map(\.type) == [.favourite, .mention])
    #expect(result.notifications.map { $0.accounts.map(\.id) } == [["a2", "a1"], ["a3"]])
    #expect(result.notifications.map { $0.status?.id } == ["s1", "s2"])
    #expect(result.notifications.map(\.mostRecentNotificationId) == ["50", "40"])
    #expect(result.nextPageState == .hasNextPage)

    let request = try #require(StubServer.requests("/api/v2/notifications").first)
    #expect(request.values("grouped_types[]") == ["favourite", "follow", "reblog"])
    #expect(request.value("expand_accounts") == "full")
    #expect(request.values("types[]").isEmpty)
    #expect(request.values("exclude_types[]").isEmpty)
    #expect(StubServer.requests("/api/v1/notifications").isEmpty)
  }

  @Test func groupedLoadForOneTypeAsksForOnlyThatTypeUngrouped() async throws {
    await useServer(version: "4.3.0")
    StubServer.enqueue(
      "/api/v2/notifications",
      json: Fixture.grouped(
        groups: [
          Fixture.group(
            "ungrouped-40", "mention", mostRecentId: 40, minute: 40, accounts: ["a3"],
            status: "s2")
        ],
        accounts: ["a3"],
        statuses: ["s2"]))

    _ = try await load(.mention)

    let request = try #require(StubServer.requests("/api/v2/notifications").first)
    #expect(request.values("types[]") == ["mention"])
    #expect(Set(request.values("exclude_types[]")) == allTypes(except: "mention"))
    #expect(request.values("grouped_types[]").isEmpty)
  }

  @Test func groupedRefreshMovesAGroupWithNewActivityToTheTop() async throws {
    await useServer(version: "4.3.0")
    StubServer.enqueue(
      "/api/v2/notifications",
      json: Fixture.grouped(
        groups: [
          Fixture.group(
            "favourite-s1-1", "favourite", mostRecentId: 50, minute: 50, accounts: ["a1"],
            status: "s1"),
          Fixture.group(
            "ungrouped-40", "mention", mostRecentId: 40, minute: 40, accounts: ["a3"],
            status: "s2"),
        ],
        accounts: ["a1", "a3"],
        statuses: ["s1", "s2"]))
    StubServer.enqueue(
      "/api/v2/notifications",
      json: Fixture.grouped(
        groups: [
          Fixture.group(
            "favourite-s1-1", "favourite", mostRecentId: 60, minute: 60,
            accounts: ["a2", "a1"], status: "s1"),
          Fixture.group(
            "ungrouped-55", "mention", mostRecentId: 55, minute: 55, accounts: ["a4"],
            status: "s3"),
        ],
        accounts: ["a1", "a2", "a4"],
        statuses: ["s1", "s3"]))

    _ = try await load()
    let refreshed = try await load()

    #expect(
      refreshed.notifications.map(\.id) == ["favourite-s1-1", "ungrouped-55", "ungrouped-40"])
    #expect(refreshed.notifications[0].accounts.map(\.id) == ["a2", "a1"])
    #expect(refreshed.notifications[0].mostRecentNotificationId == "60")
    let requests = StubServer.requests("/api/v2/notifications")
    #expect(requests.map { $0.value("since_id") } == [nil, "50"])
  }

  @Test func groupedNextPageContinuesFromTheLastGroupUntilAnEmptyPage() async throws {
    await useServer(version: "4.3.0")
    StubServer.enqueue(
      "/api/v2/notifications",
      json: Fixture.grouped(
        groups: [
          Fixture.group(
            "ungrouped-50", "mention", mostRecentId: 50, minute: 50, accounts: ["a1"],
            status: "s1"),
          Fixture.group(
            "ungrouped-40", "mention", mostRecentId: 40, minute: 40, accounts: ["a1"],
            status: "s2"),
        ],
        accounts: ["a1"],
        statuses: ["s1", "s2"]))
    StubServer.enqueue(
      "/api/v2/notifications",
      json: Fixture.grouped(
        groups: [
          Fixture.group(
            "ungrouped-30", "mention", mostRecentId: 30, minute: 30, accounts: ["a1"],
            status: "s3")
        ],
        accounts: ["a1"],
        statuses: ["s3"]))
    StubServer.enqueue("/api/v2/notifications", json: Fixture.grouped(groups: [], accounts: []))

    _ = try await load()
    let second = try await loadNextPage()
    let third = try await loadNextPage()

    #expect(second.notifications.map(\.id) == ["ungrouped-50", "ungrouped-40", "ungrouped-30"])
    #expect(second.nextPageState == .hasNextPage)
    #expect(third.notifications.count == 3)
    #expect(third.nextPageState == .none)
    let requests = StubServer.requests("/api/v2/notifications")
    #expect(requests.map { $0.value("max_id") } == [nil, "40", "30"])
  }

  // MARK: - Streaming

  @Test func streamIgnoresEventsTheListDoesNotShow() async throws {
    await useServer(version: nil)
    StubServer.enqueue(
      "/api/v1/notifications",
      json: Fixture.list([
        Fixture.notification("1", "mention", minute: 1, account: "a1", status: "s1")
      ]))
    _ = try await load()
    let favourite = Fixture.notification("2", "favourite", minute: 2, account: "a2", status: "s1")
    let alreadyListed = Fixture.notification("1", "mention", minute: 1, account: "a1", status: "s1")

    #expect(try await stream(favourite, lockedAccountId: "a1") == nil)
    #expect(try await stream(favourite, .mention) == nil)
    #expect(try await stream(alreadyListed) == nil)
    #expect(
      await dataSource.handleStreamEvent(
        event: StreamEventDelete(status: "s1"), selectedType: nil, lockedAccountId: nil) == nil)
  }

  @Test func streamedFavouriteJoinsTheRowForTheSameStatus() async throws {
    await useServer(version: nil)
    StubServer.enqueue(
      "/api/v1/notifications",
      json: Fixture.list([
        Fixture.notification("3", "mention", minute: 3, account: "a3", status: "s1"),
        Fixture.notification("2", "favourite", minute: 2, account: "a4", status: "s2"),
        Fixture.notification("1", "favourite", minute: 1, account: "a1", status: "s1"),
      ]))
    _ = try await load()

    let result = try #require(
      try await stream(
        Fixture.notification("4", "favourite", minute: 4, account: "a2", status: "s1")))

    #expect(result.notifications.map(\.type) == [.favourite, .mention, .favourite])
    #expect(result.notifications.map { $0.status?.id } == ["s1", "s1", "s2"])
    #expect(result.notifications[0].accounts.map(\.id) == ["a2", "a1"])
    #expect(result.notifications[0].mostRecentNotificationId == "4")
    #expect(!result.containsFollowRequest)
  }

  @Test func streamedNotificationOnAHiddenStatusIsNotShown() async throws {
    await useServer(version: nil)
    StubServer.enqueue("/api/v1/notifications", json: Fixture.mentions(count: 1, newestId: 1))
    _ = try await load()

    let result = try #require(
      try await stream(
        Fixture.notification(
          "2", "mention", minute: 2, account: "a2", status: "s2", hiddenStatus: true)))

    #expect(result.notifications.map(\.mostRecentNotificationId) == ["1"])
  }

  @Test func streamedFollowRequestIsReported() async throws {
    await useServer(version: nil)
    StubServer.enqueue("/api/v1/notifications", json: Fixture.mentions(count: 1, newestId: 1))
    _ = try await load()

    let result = try #require(
      try await stream(Fixture.notification("2", "follow_request", minute: 2, account: "a5")))

    #expect(result.containsFollowRequest)
    #expect(result.notifications.map(\.type) == [.follow_request, .mention])
  }

  @Test func groupedStreamEventJoinsItsServerGroup() async throws {
    await useServer(version: "4.3.0")
    StubServer.enqueue(
      "/api/v2/notifications",
      json: Fixture.grouped(
        groups: [
          Fixture.group(
            "favourite-s1-1", "favourite", mostRecentId: 50, minute: 50, accounts: ["a1"],
            status: "s1")
        ],
        accounts: ["a1"],
        statuses: ["s1"]))
    _ = try await load()

    let result = try #require(
      try await stream(
        Fixture.notification(
          "60", "favourite", minute: 60, account: "a2", status: "s1",
          groupKey: "favourite-s1-1")))

    #expect(result.notifications.map(\.id) == ["favourite-s1-1"])
    #expect(result.notifications[0].accounts.map(\.id) == ["a2", "a1"])
    #expect(result.notifications[0].mostRecentNotificationId == "60")
  }
}
