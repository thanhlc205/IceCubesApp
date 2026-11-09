import Foundation
import Models

/// JSON in the shapes the Mastodon API returns, trimmed to the fields the models require.
enum Fixture {
  /// A timestamp `minute` minutes after a fixed base time, so a higher minute is newer.
  static func time(_ minute: Int) -> String {
    String(format: "2026-06-10T%02d:%02d:00.000Z", 10 + minute / 60, minute % 60)
  }

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

  /// A status. `hidden` attaches a filter whose action hides it in notifications.
  static func status(_ id: String, hidden: Bool = false) -> String {
    let filtered =
      hidden
      ? """
      [{
        "filter": {
          "id": "filter-1",
          "title": "Hidden words",
          "context": ["notifications"],
          "filter_action": "hide"
        },
        "keyword_matches": ["spoiler"]
      }]
      """ : "[]"
    return """
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
        "filtered": \(filtered)
      }
      """
  }

  static func notification(
    _ id: String,
    _ type: String,
    minute: Int,
    account accountId: String,
    status statusId: String? = nil,
    hiddenStatus: Bool = false,
    groupKey: String? = nil
  ) -> String {
    let status = statusId.map { self.status($0, hidden: hiddenStatus) } ?? "null"
    let groupKey = groupKey.map { "\"\($0)\"" } ?? "null"
    return """
      {
        "id": "\(id)",
        "type": "\(type)",
        "created_at": "\(time(minute))",
        "group_key": \(groupKey),
        "account": \(account(accountId)),
        "status": \(status)
      }
      """
  }

  static func list(_ items: [String]) -> String {
    "[\(items.joined(separator: ","))]"
  }

  /// A page of `count` mentions with ids counting down from `newestId`, newest first.
  static func mentions(count: Int, newestId: Int) -> String {
    list(
      (0..<count).map { offset in
        let id = newestId - offset
        return notification(String(id), "mention", minute: id, account: "a1", status: "s\(id)")
      })
  }

  /// One group from `GET /api/v2/notifications`.
  static func group(
    _ groupKey: String,
    _ type: String,
    mostRecentId: Int,
    minute: Int,
    accounts: [String],
    status statusId: String? = nil
  ) -> String {
    let statusId = statusId.map { "\"\($0)\"" } ?? "null"
    let accountIds = accounts.map { "\"\($0)\"" }.joined(separator: ",")
    return """
      {
        "group_key": "\(groupKey)",
        "notifications_count": \(accounts.count),
        "type": "\(type)",
        "most_recent_notification_id": \(mostRecentId),
        "page_min_id": "\(mostRecentId)",
        "page_max_id": "\(mostRecentId)",
        "latest_page_notification_at": "\(time(minute))",
        "sample_account_ids": [\(accountIds)],
        "status_id": \(statusId)
      }
      """
  }

  /// The body of `GET /api/v2/notifications`.
  static func grouped(groups: [String], accounts: [String], statuses: [String] = []) -> String {
    """
    {
      "accounts": \(list(accounts.map(account))),
      "statuses": \(list(statuses.map { status($0) })),
      "notification_groups": \(list(groups))
    }
    """
  }

  /// The body of `GET /api/v2/instance`, trimmed to the required fields.
  static func instance(version: String) -> String {
    """
    {
      "title": "Example",
      "domain": "stub.example",
      "version": "\(version)",
      "registrations": { "enabled": false },
      "thumbnail": { "url": null },
      "contact": { "email": "admin@example.com" }
    }
    """
  }

  /// Decodes a notification the way `MastodonClient` does, for stream events.
  static func decodeNotification(_ json: String) throws -> Models.Notification {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Models.Notification.self, from: Data(json.utf8))
  }
}
