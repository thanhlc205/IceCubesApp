@testable import Account
import Foundation
import Models
import NetworkClient
import Testing

/// Following when the server takes the change. The client points at `StubServer.host`, which
/// answers with the relationship as the server now has it.
@Suite(.serialized)
@MainActor
struct FollowButtonViewModelSuccessTests {
  init() {
    StubServer.install()
    StubServer.reset()
  }

  @Test func followShowsAndReportsTheNewRelationship() async throws {
    var updates: [Relationship] = []
    let viewModel = try makeViewModel(
      server: StubServer.host, relationship: #"{"id": "9", "following": false}"#,
      relationshipUpdated: { updates.append($0) })
    StubServer.enqueue(
      "/api/v1/accounts/9/follow", method: "POST", json: #"{"id": "9", "following": true}"#)

    try await viewModel.toggleFollow()

    #expect(StubServer.requests == ["POST /api/v1/accounts/9/follow"])
    #expect(viewModel.relationship.following == true)
    #expect(updates.map(\.following) == [true])
  }

  @Test func unfollowShowsAndReportsTheNewRelationship() async throws {
    var updates: [Relationship] = []
    let viewModel = try makeViewModel(
      server: StubServer.host, relationship: #"{"id": "9", "following": true}"#,
      relationshipUpdated: { updates.append($0) })
    StubServer.enqueue(
      "/api/v1/accounts/9/unfollow", method: "POST", json: #"{"id": "9", "following": false}"#)

    try await viewModel.toggleFollow()

    #expect(StubServer.requests == ["POST /api/v1/accounts/9/unfollow"])
    #expect(viewModel.relationship.following == false)
    #expect(updates.map(\.following) == [false])
  }

  /// A pending request to follow a locked account is withdrawn by unfollowing.
  @Test func pendingRequestIsWithdrawn() async throws {
    var updates: [Relationship] = []
    let viewModel = try makeViewModel(
      server: StubServer.host, relationship: #"{"id": "9", "requested": true}"#,
      relationshipUpdated: { updates.append($0) })
    StubServer.enqueue(
      "/api/v1/accounts/9/unfollow", method: "POST", json: #"{"id": "9", "requested": false}"#)

    try await viewModel.toggleFollow()

    #expect(StubServer.requests == ["POST /api/v1/accounts/9/unfollow"])
    #expect(viewModel.relationship.requested == false)
    #expect(updates.map(\.requested) == [false])
  }
}

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
}

/// A follow button for account 9, signed in to `server`.
@MainActor
private func makeViewModel(
  server: String = OfflineURLProtocol.host,
  relationship json: String,
  relationshipUpdated: @escaping (Relationship) -> Void = { _ in }
) throws -> FollowButtonViewModel {
  let decoder = JSONDecoder()
  decoder.keyDecodingStrategy = .convertFromSnakeCase
  return try FollowButtonViewModel(
    client: MastodonClient(
      server: server,
      oauthToken: OauthToken(
        accessToken: "token", tokenType: "Bearer", scope: "read write", createdAt: 0
      )
    ),
    accountId: "9",
    relationship: decoder.decode(Relationship.self, from: Data(json.utf8)),
    shouldDisplayNotify: false,
    relationshipUpdated: relationshipUpdated
  )
}
