import AppAccount
import DesignSystem
import Env
@testable import Ice_Cubes
import NetworkClient
import SwiftUI
import Testing
import UIKit

extension AppDependencies {
  /// The app's own instances, the ones `IceCubesApp` holds for its windows.
  static func sharedInstances(isSupporter: Bool = false) -> AppDependencies {
    AppDependencies(
      appAccountsManager: .shared,
      currentAccount: .shared,
      currentInstance: .shared,
      userPreferences: .shared,
      theme: .shared,
      watcher: .shared,
      pushNotificationsService: .shared,
      appIntentService: .shared,
      quickLook: .shared,
      toastCenter: .shared,
      isSupporter: isSupporter
    )
  }
}

extension AppTests {
  /// `withAppDependencies(_:)` is the one list of services for the main window, the media sheet,
  /// and the editor and media windows on Mac and Vision Pro. A service missing from it stops the
  /// app as soon as a screen in one of those windows reads it.
  @MainActor
  struct AppDependenciesTests {
    @Test func everyServiceReachesTheWindow() async throws {
      let probe = ServiceProbe.Result()
      let scene = try #require(
        UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first
      )
      // A window SwiftUI didn't create, so the app's own environment can't fill any gaps.
      let window = UIWindow(windowScene: scene)
      defer {
        window.isHidden = true
        window.rootViewController = nil
      }
      window.rootViewController = UIHostingController(
        rootView: ServiceProbe(result: probe)
          .withAppDependencies(.sharedInstances(isSupporter: true))
      )
      window.makeKeyAndVisible()

      for _ in 0 ..< 250 where probe.found == nil {
        try await Task.sleep(for: .milliseconds(20))
      }

      #expect(probe.found == ServiceProbe.every)
      #expect(probe.isSupporter == true)
    }
  }
}

/// Reads every service a window should have, without stopping the app when one is missing.
private struct ServiceProbe: View {
  @MainActor
  final class Result {
    var found: Set<String>?
    var isSupporter = false
  }

  static let every: Set<String> = [
    "AppAccountsManager", "MastodonClient", "QuickLook", "CurrentAccount", "CurrentInstance",
    "UserPreferences", "Theme", "StreamWatcher", "PushNotificationsService", "AppIntentService",
    "ToastCenter",
  ]

  let result: Result

  @Environment(AppAccountsManager.self) private var appAccountsManager: AppAccountsManager?
  @Environment(MastodonClient.self) private var client: MastodonClient?
  @Environment(QuickLook.self) private var quickLook: QuickLook?
  @Environment(CurrentAccount.self) private var currentAccount: CurrentAccount?
  @Environment(CurrentInstance.self) private var currentInstance: CurrentInstance?
  @Environment(UserPreferences.self) private var userPreferences: UserPreferences?
  @Environment(Theme.self) private var theme: Theme?
  @Environment(StreamWatcher.self) private var watcher: StreamWatcher?
  @Environment(PushNotificationsService.self) private var pushNotifications:
    PushNotificationsService?
  @Environment(AppIntentService.self) private var appIntentService: AppIntentService?
  @Environment(ToastCenter.self) private var toastCenter: ToastCenter?
  @Environment(\.isSupporter) private var isSupporter

  var body: some View {
    Color.clear.onAppear {
      let services: [(String, Any?)] = [
        ("AppAccountsManager", appAccountsManager), ("MastodonClient", client),
        ("QuickLook", quickLook), ("CurrentAccount", currentAccount),
        ("CurrentInstance", currentInstance), ("UserPreferences", userPreferences),
        ("Theme", theme), ("StreamWatcher", watcher),
        ("PushNotificationsService", pushNotifications),
        ("AppIntentService", appIntentService), ("ToastCenter", toastCenter),
      ]
      result.found = Set(services.compactMap { name, service in service == nil ? nil : name })
      result.isSupporter = isSupporter
    }
  }
}
