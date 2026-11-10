@testable import Account
@testable import Env
import Foundation
import Models
import NetworkClient
import Testing

/// Following when the request fails. The client points at this machine, where nothing serves
/// HTTPS, so every request fails at once with a connection error, as it does offline.
@MainActor
struct FollowButtonViewModelTests {
  let toastCenter = ToastCenter()

  @Test func failedFollowTellsTheUserAndThrows() async throws {
    let viewModel = try makeViewModel(relationship: #"{"id": "9", "following": false}"#)

    await #expect(throws: URLError.self) {
      try await viewModel.toggleFollow(toastCenter: toastCenter)
    }

    #expect(toastCenter.toast?.title == "account.follow.follow-failed")
    #expect(viewModel.relationship.following == false)
  }

  @Test func failedUnfollowTellsTheUserAndThrows() async throws {
    let viewModel = try makeViewModel(relationship: #"{"id": "9", "following": true}"#)

    await #expect(throws: URLError.self) {
      try await viewModel.toggleFollow(toastCenter: toastCenter)
    }

    #expect(toastCenter.toast?.title == "account.follow.unfollow-failed")
    #expect(viewModel.relationship.following == true)
  }

  @Test func failedCancelOfAFollowRequestSaysUnfollow() async throws {
    let viewModel = try makeViewModel(relationship: #"{"id": "9", "requested": true}"#)

    await #expect(throws: URLError.self) {
      try await viewModel.toggleFollow(toastCenter: toastCenter)
    }

    #expect(toastCenter.toast?.title == "account.follow.unfollow-failed")
  }

  private func makeViewModel(relationship json: String) throws -> FollowButtonViewModel {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try FollowButtonViewModel(
      client: MastodonClient(
        server: "127.0.0.1",
        oauthToken: OauthToken(
          accessToken: "token", tokenType: "Bearer", scope: "read write", createdAt: 0
        )
      ),
      accountId: "9",
      relationship: decoder.decode(Relationship.self, from: Data(json.utf8)),
      shouldDisplayNotify: false,
      relationshipUpdated: { _ in }
    )
  }
}
