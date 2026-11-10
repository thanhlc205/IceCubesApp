@testable import Env
import Foundation
import Models
import Testing

/// What the failure toast says for each kind of error, and when it stays out of the way.
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

  /// There is one toast slot. Posting keeps a progress toast up and replaces it with its own
  /// result, so a failed boost in the meantime must not take the slot.
  @Test func failureLeavesAProgressToastInPlace() {
    let postingID = toastCenter.showProgress(title: "Posting")

    toastCenter.showFailure(title: "Couldn't boost", error: URLError(.notConnectedToInternet))
    #expect(toastCenter.toast?.id == postingID)

    toastCenter.update(id: postingID, toast: ToastCenter.Toast(id: postingID, title: "Posted"))
    #expect(toastCenter.toast?.title == "Posted")
  }
}
