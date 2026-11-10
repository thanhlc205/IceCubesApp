import Foundation
import Models
@testable import NetworkClient
import Testing

/// What `MastodonClient` throws when the server answers with an error. A `Relationship` gives
/// every field a default, so it would decode from an error body: these show the status code
/// decides, not whether the body happens to decode.
@Suite(.serialized)
struct MastodonClientErrorTests {
  let client = MastodonClient(
    server: StubServer.host,
    oauthToken: OauthToken(accessToken: "token", tokenType: "Bearer", scope: "read write", createdAt: 0)
  )

  init() {
    StubServer.install()
    StubServer.reset()
  }

  @Test func refusedRequestThrowsTheServersError() async throws {
    StubServer.enqueue(
      "/api/v1/accounts/9/follow", method: "POST", status: 403,
      json: #"{"error": "This action is not allowed"}"#)

    let error = await #expect(throws: ServerError.self) {
      let _: Relationship = try await client.post(
        endpoint: Accounts.follow(id: "9", notify: false, reblogs: true))
    }

    #expect(error?.error == "This action is not allowed")
    #expect(error?.httpCode == 403)
  }

  /// A proxy in front of the server can answer with a web page instead of JSON.
  @Test func errorPageThrowsTheStatus() async throws {
    StubServer.enqueue(
      "/api/v1/accounts/9/follow", method: "POST", status: 502,
      json: "<html><body>Bad Gateway</body></html>")

    let error = await #expect(throws: ServerError.self) {
      let _: Relationship = try await client.post(
        endpoint: Accounts.follow(id: "9", notify: false, reblogs: true))
    }

    #expect(error?.error == nil)
    #expect(error?.httpCode == 502)
  }

  @Test func successfulRequestDecodesTheAnswer() async throws {
    StubServer.enqueue(
      "/api/v1/accounts/9/follow", method: "POST", json: #"{"id": "9", "following": true}"#)

    let relationship: Relationship = try await client.post(
      endpoint: Accounts.follow(id: "9", notify: false, reblogs: true))

    #expect(relationship.id == "9")
    #expect(relationship.following == true)
  }
}
