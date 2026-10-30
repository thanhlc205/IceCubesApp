import Foundation

extension URL {
  /// Whether the URL is a web link that the app can hand to `openURL`.
  /// Replaces `UIApplication.canOpenURL(_:)`, which is deprecated in iOS 27.
  public var isWebLink: Bool {
    guard let scheme = scheme?.lowercased() else { return false }
    return scheme == "http" || scheme == "https"
  }
}
