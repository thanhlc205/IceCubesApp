import Foundation
import Models
import SwiftUI

extension ToastCenter {
  /// Tells the user that something they did didn't go through. The message is the server's
  /// explanation or the connection problem, when there is one. A cancelled request shows nothing.
  public func showFailure(title: String, error: any Error) {
    guard !Self.isCancellation(error) else { return }
    show(
      Toast(
        title: title,
        message: Self.failureMessage(for: error),
        systemImage: "exclamationmark.triangle.fill",
        tint: .red
      ),
      autoDismissAfter: .seconds(4)
    )
  }

  /// Only messages a person can act on: the server's own explanation, or the system's
  /// description of a connection problem. Decoding and other internal errors get none.
  static func failureMessage(for error: any Error) -> String? {
    switch error {
    case let error as ServerError:
      guard let message = error.error, !message.isEmpty else { return nil }
      return message
    case let error as URLError:
      return error.localizedDescription
    default:
      return nil
    }
  }

  static func isCancellation(_ error: any Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
  }
}
