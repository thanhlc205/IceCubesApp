@testable import Account
import Foundation
import Models
import NetworkClient
import Testing

/// Following when the request fails. The client points at `OfflineURLProtocol.host`, where every
/// request fails with a connection error, as it does offline.
@MainActor
struct FollowButtonViewModelTests {
  init() {
    OfflineURLProtocol.install()
  }

  @Test func failedFollowThrowsAndKeepsTheRelationship() async throws {
    let viewModel = try makeViewModel(relationship: #"{"id": "9", "following": false}"#)

    let error = await #expect(throws: URLError.self) {
      try await viewModel.toggleFollow()
    }
    #expect(error?.code == .notConnectedToInternet)

    #expect(viewModel.relationship.following == false)
  }

  @Test func failedUnfollowThrowsAndKeepsTheRelationship() async throws {
    let viewModel = try makeViewModel(relationship: #"{"id": "9", "following": true}"#)

    let error = await #expect(throws: URLError.self) {
      try await viewModel.toggleFollow()
    }
    #expect(error?.code == .notConnectedToInternet)

    #expect(viewModel.relationship.following == true)
  }

  @Test(arguments: [
    (#"{"id": "9"}"#, false),
    (#"{"id": "9", "following": true}"#, true),
    (#"{"id": "9", "requested": true}"#, true),
  ])
  func unfollowsWhenFollowingOrRequested(_ relationship: String, isUnfollowing: Bool) throws {
    let viewModel = try makeViewModel(relationship: relationship)

    #expect(viewModel.isUnfollowing == isUnfollowing)
  }

  private func makeViewModel(relationship json: String) throws -> FollowButtonViewModel {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try FollowButtonViewModel(
      client: MastodonClient(
        server: OfflineURLProtocol.host,
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
