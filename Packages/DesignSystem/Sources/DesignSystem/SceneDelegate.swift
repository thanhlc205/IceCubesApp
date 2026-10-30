import UIKit

@Observable
@MainActor public class SceneDelegate: NSObject, UIWindowSceneDelegate, Sendable {
  public var window: UIWindow?
  public private(set) var windowWidth: CGFloat = 0
  public private(set) var windowHeight: CGFloat = 0
  #if !os(visionOS)
    /// Screen size of the connected scene, used while the window isn't available yet.
    private var screenSize: CGSize = .zero
  #endif

  public func scene(
    _ scene: UIScene,
    willConnectTo _: UISceneSession,
    options _: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }
    window = windowScene.keyWindow
    #if !os(visionOS)
      screenSize = windowScene.screen.bounds.size
      windowWidth = window?.bounds.size.width ?? screenSize.width
      windowHeight = window?.bounds.size.height ?? screenSize.height
    #endif

    #if targetEnvironment(macCatalyst)
      if let titlebar = windowScene.titlebar {
        titlebar.titleVisibility = .hidden
        titlebar.toolbar = nil
      }
    #endif
  }

  override public init() {
    super.init()

    Task { @MainActor in
      setup()
    }
  }

  private func setup() {
    #if os(visionOS)
      windowWidth = window?.bounds.size.width ?? 0
      windowHeight = window?.bounds.size.height ?? 0
    #else
      windowWidth = window?.bounds.size.width ?? screenSize.width
      windowHeight = window?.bounds.size.height ?? screenSize.height
    #endif
    Self.observedSceneDelegate.insert(self)
    _ = Self.observer  // just for activating the lazy static property
  }

  private static var observedSceneDelegate: Set<SceneDelegate> = []
  private static let observer = Task { @MainActor in
    while true {
      try? await Task.sleep(for: .seconds(0.1))
      for delegate in observedSceneDelegate {
        #if os(visionOS)
          let newWidth = delegate.window?.bounds.size.width ?? 0
          if delegate.windowWidth != newWidth {
            delegate.windowWidth = newWidth
          }
          let newHeight = delegate.window?.bounds.size.height ?? 0
          if delegate.windowHeight != newHeight {
            delegate.windowHeight = newHeight
          }
        #else
          let newWidth = delegate.window?.bounds.size.width ?? delegate.screenSize.width
          if delegate.windowWidth != newWidth {
            delegate.windowWidth = newWidth
          }
          let newHeight = delegate.window?.bounds.size.height ?? delegate.screenSize.height
          if delegate.windowHeight != newHeight {
            delegate.windowHeight = newHeight
          }
        #endif
      }
    }
  }
}
