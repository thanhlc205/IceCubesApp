import Env
import Foundation
@testable import Ice_Cubes
import Models
import NetworkStubs
import Testing

extension AppTests {
  /// Pushes every `RouterDestination` through `withAppRouter()` and checks the screen it opens,
  /// by the request that screen sends or, for screens that load nothing, by its title.
  @MainActor
  struct RouterDestinationTests {
    init() {
      StubServer.install(everyHost: true)
      StubServer.reset()
    }

    @Test(arguments: Route.allCases)
    func destinationOpensItsScreen(_ route: Route) async throws {
      for (path, json) in route.responses {
        StubServer.enqueue(path, json: json)
      }
      let harness = try RouterHarness()
      defer { harness.close() }

      try harness.routerPath.navigate(to: route.destination())

      for expected in route.expected {
        switch expected {
        case let .request(path, query):
          let request = try #require(
            try await StubServer.waitForRequest(path), "Nothing asked for \(path)"
          )
          for (name, values) in query {
            #expect(request.values(name) == values, "\(path) \(name)")
          }
        case let .title(title):
          let opened = try await harness.waitUntil { harness.topTitle == title }
          #expect(opened, "Top screen is titled \(harness.topTitle ?? "nothing"), not \(title)")
        }
      }
    }

    @Test func everySampleStandsForItsOwnRoute() throws {
      for route in Route.allCases {
        #expect(try Route(for: route.destination()) == route)
      }
    }
  }
}

/// One sample of every `RouterDestination`. `init(for:)` has no `default`, so a new
/// destination doesn't compile until it gets a sample here. Each sample uses its own ids, so
/// a late request from one screen can't satisfy another's check.
enum Route: String, CaseIterable, Sendable {
  case accountDetail, accountDetailWithAccount, accountSettingsWithAccount, accountMediaGridView
  case statusDetail, statusDetailWithStatus, remoteStatusDetail, conversationDetail
  case hashTag, hashTagForAccount, list, collectionDetail, linkTimeline, quotes
  case followers, following, favoritedBy, rebloggedBy, accountsList
  case trendingTimeline, trendingLinks, tagsList
  case notificationsRequests, notificationForAccount
  case blockedAccounts, mutedAccounts, conversations, instanceInfo, metrics

  enum Expected {
    /// A request to `path` whose query has these values.
    case request(String, query: [String: [String]] = [:])
    /// For screens that load nothing.
    case title(String)
  }

  init(for destination: RouterDestination) {
    switch destination {
    case .accountDetail: self = .accountDetail
    case .accountDetailWithAccount: self = .accountDetailWithAccount
    case .accountSettingsWithAccount: self = .accountSettingsWithAccount
    case .accountMediaGridView: self = .accountMediaGridView
    case .statusDetail: self = .statusDetail
    case .statusDetailWithStatus: self = .statusDetailWithStatus
    case .remoteStatusDetail: self = .remoteStatusDetail
    case .conversationDetail: self = .conversationDetail
    case let .hashTag(_, account): self = account == nil ? .hashTag : .hashTagForAccount
    case .list: self = .list
    case .collectionDetail: self = .collectionDetail
    case .linkTimeline: self = .linkTimeline
    case .quotes: self = .quotes
    case .followers: self = .followers
    case .following: self = .following
    case .favoritedBy: self = .favoritedBy
    case .rebloggedBy: self = .rebloggedBy
    case .accountsList: self = .accountsList
    case .trendingTimeline: self = .trendingTimeline
    case .trendingLinks: self = .trendingLinks
    case .tagsList: self = .tagsList
    case .notificationsRequests: self = .notificationsRequests
    case .notificationForAccount: self = .notificationForAccount
    case .blockedAccounts: self = .blockedAccounts
    case .mutedAccounts: self = .mutedAccounts
    case .conversations: self = .conversations
    case .instanceInfo: self = .instanceInfo
    case .metrics: self = .metrics
    }
  }

  static let remoteStatusURL = URL(string: "https://remote.example/@someone/203")!
  static let linkURL = URL(string: "https://example.com/article")!

  func destination() throws -> RouterDestination {
    switch self {
    case .accountDetail:
      .accountDetail(id: "101")
    case .accountDetailWithAccount:
      try .accountDetailWithAccount(account: Fixture.decode(Fixture.account("102")))
    case .accountSettingsWithAccount:
      try .accountSettingsWithAccount(
        account: Fixture.decode(Fixture.account("103")),
        appAccount: AppAccount(server: StubServer.host, accountName: "user103@stub.example")
      )
    case .accountMediaGridView:
      try .accountMediaGridView(
        account: Fixture.decode(Fixture.account("104")), initialMediaStatuses: []
      )
    case .statusDetail:
      .statusDetail(id: "201")
    case .statusDetailWithStatus:
      try .statusDetailWithStatus(status: Fixture.decode(Fixture.status("202")))
    case .remoteStatusDetail:
      .remoteStatusDetail(url: Self.remoteStatusURL)
    case .conversationDetail:
      try .conversationDetail(conversation: Fixture.decode(Fixture.conversation(lastStatus: "205")))
    case .hashTag:
      .hashTag(tag: "swifttesting", account: nil)
    case .hashTagForAccount:
      .hashTag(tag: "swiftui", account: "105")
    case .list:
      try .list(list: Fixture.decode(Fixture.list("301")))
    case .collectionDetail:
      try .collectionDetail(collection: Fixture.decode(Fixture.collection("302")))
    case .linkTimeline:
      .linkTimeline(url: Self.linkURL, title: "An article")
    case .quotes:
      .quotes(id: "208")
    case .followers:
      .followers(id: "106")
    case .following:
      .following(id: "107")
    case .favoritedBy:
      .favoritedBy(id: "206")
    case .rebloggedBy:
      .rebloggedBy(id: "207")
    case .accountsList:
      try .accountsList(accounts: [
        Fixture.decode(Fixture.account("108")), Fixture.decode(Fixture.account("109")),
      ])
    case .trendingTimeline:
      .trendingTimeline
    case .trendingLinks:
      .trendingLinks(cards: [])
    case .tagsList:
      try .tagsList(tags: [Fixture.decode(Fixture.tag("swift"))])
    case .notificationsRequests:
      .notificationsRequests
    case .notificationForAccount:
      .notificationForAccount(accountId: "110")
    case .blockedAccounts:
      .blockedAccounts
    case .mutedAccounts:
      .mutedAccounts
    case .conversations:
      .conversations
    case .instanceInfo:
      try .instanceInfo(instance: Fixture.decode(Fixture.instance))
    case .metrics:
      .metrics
    }
  }

  /// Responses a screen needs before it sends the request that identifies it.
  var responses: [(path: String, json: String)] {
    switch self {
    case .followers: [("/api/v1/accounts/106", Fixture.account("106"))]
    case .following: [("/api/v1/accounts/107", Fixture.account("107"))]
    // Without a found status, the screen opens the link outside the app.
    case .remoteStatusDetail: [("/api/v2/search", Fixture.search(findingStatus: "204"))]
    default: []
    }
  }

  var expected: [Expected] {
    switch self {
    case .accountDetail:
      [.request("/api/v1/accounts/101")]
    case .accountDetailWithAccount:
      [.request("/api/v1/accounts/102")]
    case .accountSettingsWithAccount:
      [.title("User 103")]
    case .accountMediaGridView:
      [.request("/api/v1/accounts/104/statuses", query: ["only_media": ["true"]])]
    case .statusDetail:
      [.request("/api/v1/statuses/201/context")]
    case .statusDetailWithStatus:
      [.request("/api/v1/statuses/202/context")]
    case .remoteStatusDetail:
      [
        .request(
          "/api/v2/search",
          query: ["q": [Self.remoteStatusURL.absoluteString], "resolve": ["true"]]
        ),
        .request("/api/v1/statuses/204/context"),
      ]
    case .conversationDetail:
      [.request("/api/v1/statuses/205/context")]
    case .hashTag:
      [.request("/api/v1/timelines/tag/swifttesting")]
    case .hashTagForAccount:
      [.request("/api/v1/accounts/105/statuses", query: ["tagged": ["swiftui"]])]
    case .list:
      [.request("/api/v1/timelines/list/301")]
    case .collectionDetail:
      [.request("/api/v1/collections/302")]
    case .linkTimeline:
      [.request("/api/v1/timelines/link", query: ["url": [Self.linkURL.absoluteString]])]
    case .quotes:
      [.request("/api/v1/statuses/208/quotes")]
    case .followers:
      [.request("/api/v1/accounts/106/followers")]
    case .following:
      [.request("/api/v1/accounts/107/following")]
    case .favoritedBy:
      [.request("/api/v1/statuses/206/favourited_by")]
    case .rebloggedBy:
      [.request("/api/v1/statuses/207/reblogged_by")]
    case .accountsList:
      [.request("/api/v1/accounts/relationships", query: ["id[]": ["108", "109"]])]
    case .trendingTimeline:
      [.request("/api/v1/trends/statuses")]
    case .trendingLinks:
      [.request("/api/v1/trends/links")]
    case .tagsList:
      [.title(String(localized: "explore.section.trending.tags"))]
    case .notificationsRequests:
      [.request("/api/v1/notifications/requests")]
    case .notificationForAccount:
      [.request("/api/v1/notifications", query: ["account_id": ["110"]])]
    case .blockedAccounts:
      [.request("/api/v1/blocks")]
    case .mutedAccounts:
      [.request("/api/v1/mutes")]
    case .conversations:
      [.request("/api/v1/conversations")]
    case .instanceInfo:
      [.title(String(localized: "instance.info.navigation-title"))]
    // Metrics loads only for a signed-in current account, which the test host doesn't have.
    case .metrics:
      [.title(String(localized: "Metrics"))]
    }
  }
}
