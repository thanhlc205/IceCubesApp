import Foundation

extension URL {
  /// Whether the URL uses a scheme the app offers to open through `openURL`:
  /// web links, email addresses and phone numbers.
  /// Replaces `UIApplication.canOpenURL(_:)`, which is deprecated in iOS 27.
  public var isOpenableLink: Bool {
    guard let scheme = scheme?.lowercased() else { return false }
    return ["http", "https", "mailto", "tel"].contains(scheme)
  }
}
