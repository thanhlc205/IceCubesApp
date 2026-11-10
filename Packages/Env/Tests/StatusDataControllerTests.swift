@testable import Env
import Foundation
import Models
import NetworkClient
import Testing

/// Favourite, boost and bookmark when the request fails. The client points at this machine,
/// where nothing serves HTTPS, so every request fails at once with a connection error, as it
/// does offline.
@MainActor
struct StatusDataControllerFailureTests {
  let offlineClient = MastodonClient(
    server: "127.0.0.1",
    oauthToken: OauthToken(accessToken: "token", tokenType: "Bearer", scope: "read write", createdAt: 0)
  )

  @Test func failedFavouriteThrowsAndLeavesThePostAsItWas() async throws {
    let controller = try controller(favourited: false, favourites: 5)

    await #expect(throws: URLError.self) {
      try await controller.toggleFavorite(remoteStatus: nil)
    }

    #expect(controller.isFavorited == false)
    #expect(controller.favoritesCount == 5)
  }

  @Test func failedUnfavouriteThrowsAndLeavesThePostAsItWas() async throws {
    let controller = try controller(favourited: true, favourites: 5)

    await #expect(throws: URLError.self) {
      try await controller.toggleFavorite(remoteStatus: nil)
    }

    #expect(controller.isFavorited == true)
    #expect(controller.favoritesCount == 5)
  }

  @Test func failedBoostThrowsAndLeavesThePostAsItWas() async throws {
    let controller = try controller(reblogged: false, reblogs: 3)

    await #expect(throws: URLError.self) {
      try await controller.toggleReblog(remoteStatus: nil)
    }

    #expect(controller.isReblogged == false)
    #expect(controller.reblogsCount == 3)
  }

  @Test func failedUnboostThrowsAndLeavesThePostAsItWas() async throws {
    let controller = try controller(reblogged: true, reblogs: 3)

    await #expect(throws: URLError.self) {
      try await controller.toggleReblog(remoteStatus: nil)
    }

    #expect(controller.isReblogged == true)
    #expect(controller.reblogsCount == 3)
  }

  @Test func failedBookmarkThrowsAndLeavesThePostAsItWas() async throws {
    let controller = try controller(bookmarked: false)

    await #expect(throws: URLError.self) {
      try await controller.toggleBookmark(remoteStatus: nil)
    }

    #expect(controller.isBookmarked == false)
  }

  @Test func failedUnbookmarkThrowsAndLeavesThePostAsItWas() async throws {
    let controller = try controller(bookmarked: true)

    await #expect(throws: URLError.self) {
      try await controller.toggleBookmark(remoteStatus: nil)
    }

    #expect(controller.isBookmarked == true)
  }

  @Test func signedOutDoesNothing() async throws {
    let signedOut = MastodonClient(server: "127.0.0.1")
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

  private func status(
    favourited: Bool, favourites: Int,
    reblogged: Bool = false, reblogs: Int = 0,
    bookmarked: Bool = false
  ) throws -> Status {
    let json = """
    {
      "id": "1",
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
      "visibility": "public", "spoiler_text": "", "sensitive": false
    }
    """
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Status.self, from: Data(json.utf8))
  }
}

/// What the failure toast says for each kind of error.
@MainActor
struct ToastCenterFailureTests {
  let toastCenter = ToastCenter()

  @Test func serverErrorShowsTheServersExplanation() throws {
    let error = try JSONDecoder().decode(
      ServerError.self, from: Data(#"{"error": "Validation failed"}"#.utf8)
    )

    toastCenter.showFailure(title: "Couldn't boost", error: error)

    #expect(toastCenter.toast?.title == "Couldn't boost")
    #expect(toastCenter.toast?.message == "Validation failed")
  }

  @Test func connectionErrorShowsTheSystemDescription() {
    let error = URLError(.notConnectedToInternet)

    toastCenter.showFailure(title: "Couldn't boost", error: error)

    #expect(toastCenter.toast?.message == error.localizedDescription)
  }

  @Test func otherErrorsShowNoMessage() {
    struct InternalError: Error {}

    toastCenter.showFailure(title: "Couldn't boost", error: InternalError())

    #expect(toastCenter.toast?.title == "Couldn't boost")
    #expect(toastCenter.toast?.message == nil)
  }

  @Test(arguments: [CancellationError() as any Error, URLError(.cancelled)])
  func cancelledRequestShowsNothing(_ error: any Error) {
    toastCenter.showFailure(title: "Couldn't boost", error: error)

    #expect(toastCenter.toast == nil)
  }
}
