import AppAccount
import DesignSystem
import Env
@testable import Ice_Cubes
import Models
import NetworkClient
import NetworkStubs
import SwiftData
import SwiftUI
import Testing
import UIKit

/// Shows the app's navigation and sheet mapping in a window, set up the way a tab sets it up:
/// a `NavigationStack` on a `RouterPath`, with `withAppRouter()` and `withSheetDestinations`,
/// inside the services the main window injects. Screens get a signed-in client for
/// `StubServer.host`, so the requests they send can be checked.
@MainActor
final class RouterHarness {
  let routerPath = RouterPath()
  let client = MastodonClient(
    server: StubServer.host,
    oauthToken: OauthToken(
      accessToken: "test-token", tokenType: "Bearer", scope: "read write follow push",
      createdAt: 0
    )
  )
  private let window: UIWindow

  init() throws {
    let scene = try #require(
      UIApplication.shared.connectedScenes.lazy.compactMap { $0 as? UIWindowScene }.first
    )
    // SwiftUI puts the app's `SceneDelegate` in the environment of the windows it creates,
    // and that instance isn't reachable from here. Status rows only read the window size from
    // it, so a new one stands in, as `StatusRowMediaPreviewView` does.
    let sceneDelegate = SceneDelegate()
    window = UIWindow(windowScene: scene)
    routerPath.client = client
    window.rootViewController = UIHostingController(
      rootView: HarnessRoot(routerPath: routerPath, client: client, sceneDelegate: sceneDelegate)
    )
    window.makeKeyAndVisible()
  }

  /// The controller a sheet is shown in, while one is up.
  var presentedController: UIViewController? {
    window.rootViewController?.presentedViewController
  }

  /// The navigation title of the screen on top of the stack.
  var topTitle: String? {
    navigationController(in: window.rootViewController)?.topViewController?.navigationItem.title
  }

  /// Polls `condition` for up to five seconds and returns whether it became true.
  func waitUntil(_ condition: () -> Bool) async throws -> Bool {
    for _ in 0 ..< 250 {
      if condition() {
        return true
      }
      try await Task.sleep(for: .milliseconds(20))
    }
    return condition()
  }

  func close() {
    window.rootViewController?.dismiss(animated: false)
    window.isHidden = true
    window.rootViewController = nil
  }

  private func navigationController(in controller: UIViewController?) -> UINavigationController? {
    guard let controller else { return nil }
    if let navigation = controller as? UINavigationController {
      return navigation
    }
    for child in controller.children {
      if let navigation = navigationController(in: child) {
        return navigation
      }
    }
    return nil
  }
}

private struct HarnessRoot: View {
  let routerPath: RouterPath
  let client: MastodonClient
  let sceneDelegate: SceneDelegate
  @Namespace private var namespace

  var body: some View {
    @Bindable var routerPath = routerPath
    NavigationStack(path: $routerPath.path) {
      Color.clear
        .withAppRouter()
        .withSheetDestinations(
          sheetDestinations: $routerPath.presentedSheet,
          routerPath: routerPath
        )
    }
    .environment(routerPath)
    .environment(sceneDelegate)
    // Closer to the screens than the graph's own client, so it wins.
    .environment(client)
    // The same instances `IceCubesApp` passes for the main window.
    .withAppDependencyGraph(.sharedInstances(), namespace: namespace)
    .modelContainer(
      for: [
        Draft.self, LocalTimeline.self, TagGroup.self, RecentTag.self,
        MetricsNotificationGroup.self,
      ], inMemory: true
    )
  }
}
