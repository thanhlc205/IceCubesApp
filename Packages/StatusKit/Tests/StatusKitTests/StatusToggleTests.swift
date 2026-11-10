@testable import Env
import Foundation
@testable import StatusKit
import Testing

/// The toast a status row shows when a favourite, boost or bookmark doesn't go through.
@MainActor
struct StatusToggleTests {
  let toastCenter = ToastCenter()

  @Test(arguments: [
    (StatusToggle.favorite, false, "status.action.favorite-failed"),
    (.favorite, true, "status.action.unfavorite-failed"),
    (.boost, false, "status.action.boost-failed"),
    (.boost, true, "status.action.unboost-failed"),
    (.bookmark, false, "status.action.bookmark-failed"),
    (.bookmark, true, "status.action.unbookmark-failed"),
  ])
  func failedToggleShowsWhatDidNotHappen(_ toggle: StatusToggle, undoing: Bool, title: String) async {
    await toastCenter.run(toggle, undoing: undoing) {
      throw URLError(.notConnectedToInternet)
    }

    #expect(toastCenter.toast?.title == title)
    #expect(toastCenter.toast?.message == URLError(.notConnectedToInternet).localizedDescription)
  }

  @Test func successfulToggleShowsNothing() async {
    await toastCenter.run(.boost, undoing: false) {}

    #expect(toastCenter.toast == nil)
  }

  @Test func cancelledToggleShowsNothing() async {
    await toastCenter.run(.boost, undoing: false) {
      throw CancellationError()
    }

    #expect(toastCenter.toast == nil)
  }
}
