@testable import Env
import Foundation
import Models
import NetworkClient
import Testing

/// Favourite, boost and bookmark when the server takes the change. The client points at
/// `StubServer.host`, which answers with the post as the server now has it. The server's counts
/// differ from the controller's own guess, as they do when others act on the post too, so each
/// test shows the controller ends up with the server's answer.
@Suite(.serialized)
@MainActor
struct StatusDataControllerSuccessTests {
  let client = MastodonClient(
    server: StubServer.host,
    oauthToken: OauthToken(accessToken: "token", tokenType: "Bearer", scope: "read write", createdAt: 0)
  )

  init() {
    StubServer.install()
    StubServer.reset()
  }

  @Test func favouriteShowsTheServersCount() async throws {
    let controller = try controller(status(favourited: false, favourites: 5))
    StubServer.enqueue(
      "/api/v1/statuses/1/favourite", method: "POST",
      json: statusJSON(favourited: true, favourites: 9))

    try await controller.toggleFavorite(remoteStatus: nil)

    #expect(StubServer.requests == ["POST /api/v1/statuses/1/favourite"])
    #expect(controller.isFavorited == true)
    #expect(controller.favoritesCount == 9)
  }

  @Test func unfavouriteShowsTheServersCount() async throws {
    let controller = try controller(status(favourited: true, favourites: 5))
    StubServer.enqueue(
      "/api/v1/statuses/1/unfavourite", method: "POST",
      json: statusJSON(favourited: false, favourites: 2))

    try await controller.toggleFavorite(remoteStatus: nil)

    #expect(StubServer.requests == ["POST /api/v1/statuses/1/unfavourite"])
    #expect(controller.isFavorited == false)
    #expect(controller.favoritesCount == 2)
  }

  /// The server answers a boost with the new boost, which wraps the post it boosted.
  @Test func boostShowsTheBoostedPostsCount() async throws {
    let controller = try controller(status(reblogged: false, reblogs: 3))
    StubServer.enqueue(
      "/api/v1/statuses/1/reblog", method: "POST",
      json: statusJSON(
        id: "2", reblogged: true, reblogs: 0,
        reblog: statusJSON(reblogged: true, reblogs: 7)))

    try await controller.toggleReblog(remoteStatus: nil)

    #expect(StubServer.requests == ["POST /api/v1/statuses/1/reblog"])
    #expect(controller.isReblogged == true)
    #expect(controller.reblogsCount == 7)
  }

  @Test func unboostShowsTheServersCount() async throws {
    let controller = try controller(status(reblogged: true, reblogs: 3))
    StubServer.enqueue(
      "/api/v1/statuses/1/unreblog", method: "POST",
      json: statusJSON(reblogged: false, reblogs: 1))

    try await controller.toggleReblog(remoteStatus: nil)

    #expect(StubServer.requests == ["POST /api/v1/statuses/1/unreblog"])
    #expect(controller.isReblogged == false)
    #expect(controller.reblogsCount == 1)
  }

  @Test func bookmarkShowsTheBookmark() async throws {
    let controller = try controller(status(bookmarked: false))
    StubServer.enqueue(
      "/api/v1/statuses/1/bookmark", method: "POST", json: statusJSON(bookmarked: true))

    try await controller.toggleBookmark(remoteStatus: nil)

    #expect(StubServer.requests == ["POST /api/v1/statuses/1/bookmark"])
    #expect(controller.isBookmarked == true)
  }

  @Test func unbookmarkRemovesTheBookmark() async throws {
    let controller = try controller(status(bookmarked: true))
    StubServer.enqueue(
      "/api/v1/statuses/1/unbookmark", method: "POST", json: statusJSON(bookmarked: false))

    try await controller.toggleBookmark(remoteStatus: nil)

    #expect(StubServer.requests == ["POST /api/v1/statuses/1/unbookmark"])
    #expect(controller.isBookmarked == false)
  }

  /// A post from another server has its own ID on this one, and the request must use it.
  @Test func remotePostIsChangedByItsIDOnThisServer() async throws {
    let controller = try controller(status(favourited: false, favourites: 5))
    StubServer.enqueue(
      "/api/v1/statuses/77/favourite", method: "POST",
      json: statusJSON(id: "77", favourited: true, favourites: 6))

    try await controller.toggleFavorite(remoteStatus: "77")

    #expect(StubServer.requests == ["POST /api/v1/statuses/77/favourite"])
    #expect(controller.isFavorited == true)
    #expect(controller.favoritesCount == 6)
  }

  private func controller(_ status: Status) -> StatusDataController {
    StatusDataController(status: status, client: client)
  }
}

/// Favourite, boost and bookmark when the request fails. The client points at
/// `OfflineURLProtocol.host`, where every request fails with a connection error, as it does
/// offline.
@MainActor
struct StatusDataControllerFailureTests {
  let offlineClient = MastodonClient(
    server: OfflineURLProtocol.host,
    oauthToken: OauthToken(accessToken: "token", tokenType: "Bearer", scope: "read write", createdAt: 0)
  )

  init() {
    OfflineURLProtocol.install()
  }

  @Test func failedFavouriteThrowsAndLeavesThePostAsItWas() async throws {
    let controller = try controller(favourited: false, favourites: 5)

    let error = await #expect(throws: URLError.self) {
      try await controller.toggleFavorite(remoteStatus: nil)
    }
    #expect(error?.code == .notConnectedToInternet)

    #expect(controller.isFavorited == false)
    #expect(controller.favoritesCount == 5)
  }

  @Test func failedUnfavouriteThrowsAndLeavesThePostAsItWas() async throws {
    let controller = try controller(favourited: true, favourites: 5)

    let error = await #expect(throws: URLError.self) {
      try await controller.toggleFavorite(remoteStatus: nil)
    }
    #expect(error?.code == .notConnectedToInternet)

    #expect(controller.isFavorited == true)
    #expect(controller.favoritesCount == 5)
  }

  @Test func failedBoostThrowsAndLeavesThePostAsItWas() async throws {
    let controller = try controller(reblogged: false, reblogs: 3)

    let error = await #expect(throws: URLError.self) {
      try await controller.toggleReblog(remoteStatus: nil)
    }
    #expect(error?.code == .notConnectedToInternet)

    #expect(controller.isReblogged == false)
    #expect(controller.reblogsCount == 3)
  }

  @Test func failedUnboostThrowsAndLeavesThePostAsItWas() async throws {
    let controller = try controller(reblogged: true, reblogs: 3)

    let error = await #expect(throws: URLError.self) {
      try await controller.toggleReblog(remoteStatus: nil)
    }
    #expect(error?.code == .notConnectedToInternet)

    #expect(controller.isReblogged == true)
    #expect(controller.reblogsCount == 3)
  }

  @Test func failedBookmarkThrowsAndLeavesThePostAsItWas() async throws {
    let controller = try controller(bookmarked: false)

    let error = await #expect(throws: URLError.self) {
      try await controller.toggleBookmark(remoteStatus: nil)
    }
    #expect(error?.code == .notConnectedToInternet)

    #expect(controller.isBookmarked == false)
  }

  @Test func failedUnbookmarkThrowsAndLeavesThePostAsItWas() async throws {
    let controller = try controller(bookmarked: true)

    let error = await #expect(throws: URLError.self) {
      try await controller.toggleBookmark(remoteStatus: nil)
    }
    #expect(error?.code == .notConnectedToInternet)

    #expect(controller.isBookmarked == true)
  }

  @Test func signedOutDoesNothing() async throws {
    let signedOut = MastodonClient(server: OfflineURLProtocol.host)
    let controller = try StatusDataController(
      status: status(favourited: false, favourites: 5), client: signedOut
    )

    try await controller.toggleFavorite(remoteStatus: nil)

    #expect(controller.isFavorited == false)
    #expect(controller.favoritesCount == 5)
  }

  private func controller(
    favourited: Bool = false, favourites: Int = 0,
    reblogged: Bool = false, reblogs: Int = 0,
    bookmarked: Bool = false
  ) throws -> StatusDataController {
    try StatusDataController(
      status: status(
        favourited: favourited, favourites: favourites,
        reblogged: reblogged, reblogs: reblogs, bookmarked: bookmarked
      ),
      client: offlineClient
    )
  }
}

/// A post as its server sends it. `reblog` is the JSON of the boosted post, when this is a boost.
private func statusJSON(
  id: String = "1",
  favourited: Bool = false, favourites: Int = 0,
  reblogged: Bool = false, reblogs: Int = 0,
  bookmarked: Bool = false,
  reblog: String? = nil
) -> String {
  """
  {
    "id": "\(id)",
    "content": "<p>Hello</p>",
    "account": {
      "id": "a1", "username": "a1", "acct": "a1@example.com", "display_name": "A1",
      "note": "", "avatar": "https://example.com/a.png",
      "header": "https://example.com/h.png", "locked": false, "emojis": [],
      "fields": [], "created_at": "2026-01-01T00:00:00.000Z", "followers_count": 0,
      "following_count": 0, "statuses_count": 0, "bot": false
    },
    "created_at": "2026-06-01T00:00:00.000Z",
    "media_attachments": [], "mentions": [], "emojis": [], "tags": [],
    "replies_count": 0,
    "reblogs_count": \(reblogs),
    "favourites_count": \(favourites),
    "favourited": \(favourited),
    "reblogged": \(reblogged),
    "bookmarked": \(bookmarked),
    "reblog": \(reblog ?? "null"),
    "visibility": "public", "spoiler_text": "", "sensitive": false
  }
  """
}

private func status(
  favourited: Bool = false, favourites: Int = 0,
  reblogged: Bool = false, reblogs: Int = 0,
  bookmarked: Bool = false
) throws -> Status {
  let decoder = JSONDecoder()
  decoder.keyDecodingStrategy = .convertFromSnakeCase
  let json = statusJSON(
    favourited: favourited, favourites: favourites,
    reblogged: reblogged, reblogs: reblogs, bookmarked: bookmarked)
  return try decoder.decode(Status.self, from: Data(json.utf8))
}
