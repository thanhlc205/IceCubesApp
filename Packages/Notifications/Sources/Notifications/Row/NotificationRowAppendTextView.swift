import Models
import SwiftUI

nonisolated func NotificationRowAppendTextView(notification: ConsolidatedNotification) -> Text {
  if notification.accounts.count > 1 {
    let othersCount: Int
    // For favorites and reblogs, use the actual count from the status
    if notification.type == .favourite, let favCount = notification.status?.favouritesCount,
      favCount > 1
    {
      othersCount = favCount - 1
    } else if notification.type == .reblog, let reblogCount = notification.status?.reblogsCount,
      reblogCount > 1
    {
      othersCount = reblogCount - 1
    } else {
      // For other types (like follow), use the accounts count
      othersCount = notification.accounts.count - 1
    }
    let others = Text("notifications-others-count \(othersCount)")
      .font(.subheadline)
      .fontWeight(.regular)
    return Text("\(others)\(separator)\(createdAt(of: notification))")
  } else {
    let label = Text(notification.type.label(count: 1))
      .font(.subheadline)
      .fontWeight(.regular)
    return Text(" \(label)\(separator)\(createdAt(of: notification))")
  }
}

private nonisolated var separator: Text {
  Text(" ⸱ ")
    .font(.footnote)
    .fontWeight(.regular)
    .foregroundStyle(.secondary)
}

private nonisolated func createdAt(of notification: ConsolidatedNotification) -> Text {
  Text(notification.createdAt.relativeFormatted)
    .font(.footnote)
    .fontWeight(.regular)
    .foregroundStyle(.secondary)
}
