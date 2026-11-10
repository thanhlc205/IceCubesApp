import Foundation
import Models
import NetworkClient
import OSLog
import Observation
import SwiftUI

@MainActor
public protocol StatusDataControlling {
  var isReblogged: Bool { get set }
  var isBookmarked: Bool { get set }
  var isFavorited: Bool { get set }

  var favoritesCount: Int { get set }
  var reblogsCount: Int { get set }
  var repliesCount: Int { get set }

  /// Each toggle shows the change at once. If the request fails, it puts the post back as it
  /// was and tells the user through `toastCenter`.
  func toggleBookmark(remoteStatus: String?, toastCenter: ToastCenter) async
  func toggleReblog(remoteStatus: String?, toastCenter: ToastCenter) async
  func toggleFavorite(remoteStatus: String?, toastCenter: ToastCenter) async
}

@MainActor
public final class StatusDataControllerProvider {
  public static let shared = StatusDataControllerProvider()

  private var cache: NSMutableDictionary = [:]

  private struct CacheKey: Hashable {
    let statusId: String
    let client: MastodonClient
  }

  public func dataController(for status: any AnyStatus, client: MastodonClient)
    -> StatusDataController
  {
    let key = CacheKey(statusId: status.id, client: client)
    if let controller = cache[key] as? StatusDataController {
      return controller
    }
    let controller = StatusDataController(status: status, client: client)
    cache[key] = controller
    return controller
  }

  public func updateDataControllers(for statuses: [Status], client: MastodonClient) {
    for status in statuses {
      let realStatus: AnyStatus = status.reblog ?? status
      let controller = dataController(for: realStatus, client: client)
      controller.updateFrom(status: realStatus)
    }
  }
}

@MainActor
@Observable public final class StatusDataController: StatusDataControlling {
  private let status: AnyStatus
  private let client: MastodonClient

  public var isReblogged: Bool
  public var isBookmarked: Bool
  public var isFavorited: Bool
  public var content: HTMLString

  public var favoritesCount: Int
  public var reblogsCount: Int
  public var repliesCount: Int
  public var quotesCount: Int

  init(status: AnyStatus, client: MastodonClient) {
    self.status = status
    self.client = client

    isReblogged = status.reblogged == true
    isBookmarked = status.bookmarked == true
    isFavorited = status.favourited == true

    reblogsCount = status.reblogsCount
    repliesCount = status.repliesCount
    favoritesCount = status.favouritesCount
    quotesCount = status.quotesCount ?? 0
    content = status.content
  }

  public func updateFrom(status: AnyStatus) {
    isReblogged = status.reblogged == true
    isBookmarked = status.bookmarked == true
    isFavorited = status.favourited == true

    reblogsCount = status.reblogsCount
    repliesCount = status.repliesCount
    favoritesCount = status.favouritesCount
    quotesCount = status.quotesCount ?? 0
    content = status.content
  }

  public func toggleFavorite(remoteStatus: String?, toastCenter: ToastCenter) async {
    guard client.isAuth else { return }
    isFavorited.toggle()
    let id = remoteStatus ?? status.id
    let endpoint = isFavorited ? Statuses.favorite(id: id) : Statuses.unfavorite(id: id)
    withAnimation(.default) {
      favoritesCount += isFavorited ? 1 : -1
    }
    do {
      let status: Status = try await client.post(endpoint: endpoint)
      updateFrom(status: status)
    } catch {
      isFavorited.toggle()
      favoritesCount += isFavorited ? 1 : -1
      report(
        error, action: "favourite", toastCenter: toastCenter,
        title: isFavorited
          ? String(localized: "status.action.unfavorite-failed")
          : String(localized: "status.action.favorite-failed"))
    }
  }

  public func toggleReblog(remoteStatus: String?, toastCenter: ToastCenter) async {
    guard client.isAuth else { return }
    isReblogged.toggle()
    let id = remoteStatus ?? status.id
    let endpoint = isReblogged ? Statuses.reblog(id: id) : Statuses.unreblog(id: id)
    withAnimation(.default) {
      reblogsCount += isReblogged ? 1 : -1
    }
    do {
      let status: Status = try await client.post(endpoint: endpoint)
      updateFrom(status: status.reblog ?? status)
    } catch {
      isReblogged.toggle()
      reblogsCount += isReblogged ? 1 : -1
      report(
        error, action: "boost", toastCenter: toastCenter,
        title: isReblogged
          ? String(localized: "status.action.unboost-failed")
          : String(localized: "status.action.boost-failed"))
    }
  }

  public func toggleBookmark(remoteStatus: String?, toastCenter: ToastCenter) async {
    guard client.isAuth else { return }
    isBookmarked.toggle()
    let id = remoteStatus ?? status.id
    let endpoint = isBookmarked ? Statuses.bookmark(id: id) : Statuses.unbookmark(id: id)
    do {
      let status: Status = try await client.post(endpoint: endpoint)
      updateFrom(status: status)
    } catch {
      isBookmarked.toggle()
      report(
        error, action: "bookmark", toastCenter: toastCenter,
        title: isBookmarked
          ? String(localized: "status.action.unbookmark-failed")
          : String(localized: "status.action.bookmark-failed"))
    }
  }

  /// `title` names what didn't happen. By the time this runs, the toggle is back where it
  /// started, so a post that is still favourited means the unfavourite failed.
  private func report(_ error: any Error, action: String, toastCenter: ToastCenter, title: String) {
    Logger.env.error(
      "\(action, privacy: .public) toggle failed for status \(self.status.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
    )
    toastCenter.showFailure(title: title, error: error)
  }
}
