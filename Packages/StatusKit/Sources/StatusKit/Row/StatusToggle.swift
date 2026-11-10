import Env
import Foundation

/// A favourite, boost or bookmark from a status row.
enum StatusToggle {
  case favorite
  case boost
  case bookmark

  /// The toast title when the toggle doesn't go through. `undoing` is true when the post was
  /// already favourited, boosted or bookmarked, so the user was taking it back.
  func failureTitle(undoing: Bool) -> String {
    switch (self, undoing) {
    case (.favorite, false): String(localized: "status.action.favorite-failed")
    case (.favorite, true): String(localized: "status.action.unfavorite-failed")
    case (.boost, false): String(localized: "status.action.boost-failed")
    case (.boost, true): String(localized: "status.action.unboost-failed")
    case (.bookmark, false): String(localized: "status.action.bookmark-failed")
    case (.bookmark, true): String(localized: "status.action.unbookmark-failed")
    }
  }
}

extension ToastCenter {
  /// For views: runs a status toggle and shows a toast when it doesn't go through.
  func run(_ toggle: StatusToggle, undoing: Bool, _ action: () async throws -> Void) async {
    do {
      try await action()
    } catch {
      showFailure(title: toggle.failureTitle(undoing: undoing), error: error)
    }
  }
}
