import Foundation

public enum AppInfo {
  public static let appStoreAppId = "6444915884"
  public static let clientName = "IceCubesApp"
  public static let scheme = "icecubesapp://"
  public static let scopes = "read write follow push"
  public static let weblink = "https://github.com/Dimillian/IceCubesApp"
  public static let defaultServer = "mastodon.social"

  /// The shared app group, read from the running target's `AppGroupIdentifier` Info.plist key,
  /// which is built from `BUNDLE_ID_PREFIX` like the entitlements. `nil` when the bundle doesn't
  /// declare it, for example in package tests.
  public static let appGroup: String? = infoPlistValue(forKey: "AppGroupIdentifier")

  /// The shared keychain access group, read from the running target's `KeychainAccessGroup`
  /// Info.plist key, which is built from `AppIdentifierPrefix` and `BUNDLE_ID_PREFIX` like the
  /// entitlements. `nil` when the bundle doesn't declare it or the build isn't signed.
  public static let keychainGroup: String? = infoPlistValue(forKey: "KeychainAccessGroup")
    .flatMap { $0.hasPrefix(".") ? nil : $0 }  // AppIdentifierPrefix is empty when unsigned.

  // Third-party service keys come from `Secrets.xcconfig` (see `Secrets.xcconfig.template`)
  // through the app's Info.plist. Each one is `nil` when unset, and that service stays off.

  /// RevenueCat public API key, used for the tip jar and supporter subscription.
  public static let revenueCatKey: String? = infoPlistValue(forKey: "RevenueCatAPIKey")
  /// TelemetryDeck app ID, used for anonymous usage signals.
  public static let telemetryDeckAppID: String? = infoPlistValue(forKey: "TelemetryDeckAppID")
  /// WishKit API key, used for the feature-request list.
  public static let wishKitAPIKey: String? = infoPlistValue(forKey: "WishKitAPIKey")
  /// instances.social API token, used to suggest servers when adding an account.
  public static let instancesSocialToken: String? = infoPlistValue(forKey: "InstancesSocialToken")

  private static func infoPlistValue(forKey key: String) -> String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
      !value.isEmpty,
      !value.contains("$(")  // Build setting left unexpanded.
    else {
      return nil
    }
    return value
  }
}
