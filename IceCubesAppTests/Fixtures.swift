import Foundation
import Models

/// JSON in the shapes the Mastodon API returns, trimmed to the fields the models require.
enum Fixture {
  static func account(_ id: String) -> String {
    """
    {
      "id": "\(id)",
      "username": "user\(id)",
      "acct": "user\(id)@example.com",
      "display_name": "User \(id)",
      "note": "",
      "avatar": "https://example.com/\(id).png",
      "header": "https://example.com/\(id)-header.png",
      "locked": false,
      "emojis": [],
      "fields": [],
      "created_at": "2026-01-01T00:00:00.000Z",
      "followers_count": 0,
      "following_count": 0,
      "statuses_count": 0,
      "bot": false,
      "discoverable": true
    }
    """
  }

  static func status(_ id: String) -> String {
    """
    {
      "id": "\(id)",
      "content": "<p>Status \(id)</p>",
      "account": \(account("author")),
      "created_at": "2026-06-01T00:00:00.000Z",
      "media_attachments": [],
      "mentions": [],
      "replies_count": 0,
      "reblogs_count": 0,
      "favourites_count": 0,
      "emojis": [],
      "visibility": "public",
      "spoiler_text": "",
      "sensitive": false,
      "tags": [],
      "filtered": []
    }
    """
  }

  static let emptyContext = #"{"ancestors": [], "descendants": []}"#

  static func list(_ id: String) -> String {
    #"{"id": "\#(id)", "title": "List \#(id)"}"#
  }

  static func conversation(lastStatus statusId: String) -> String {
    #"{"id": "c\#(statusId)", "unread": false, "accounts": [\#(account("c"))], "last_status": \#(status(statusId))}"#
  }

  static func collection(_ id: String) -> String {
    """
    {
      "id": "\(id)",
      "account_id": "author",
      "uri": "https://stub.example/collections/\(id)",
      "name": "Collection \(id)",
      "description": "",
      "local": true,
      "sensitive": false,
      "discoverable": true,
      "created_at": "2026-01-01T00:00:00.000Z",
      "updated_at": "2026-01-01T00:00:00.000Z",
      "item_count": 0,
      "items": []
    }
    """
  }

  static func tag(_ name: String) -> String {
    #"{"name": "\#(name)", "url": "https://stub.example/tags/\#(name)"}"#
  }

  static let instance = """
  {
    "title": "Example",
    "domain": "stub.example",
    "version": "4.5.0",
    "registrations": { "enabled": false },
    "thumbnail": {},
    "contact": { "email": "admin@example.com" }
  }
  """

  /// The body of `GET /api/v2/search` when it finds one status.
  static func search(findingStatus statusId: String) -> String {
    #"{"accounts": [], "statuses": [\#(status(statusId))], "hashtags": []}"#
  }

  /// Decodes a model the way `MastodonClient` does.
  static func decode<T: Decodable>(_ json: String, as _: T.Type = T.self) throws -> T {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: Data(json.utf8))
  }
}
