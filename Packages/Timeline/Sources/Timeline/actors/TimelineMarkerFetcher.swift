import Foundation
import Models
import NetworkClient

nonisolated protocol TimelineMarkerFetching: Sendable {
  func fetchHomeMarker(client: MastodonClient) async throws -> Marker.Content?
  func saveHomeMarker(client: MastodonClient, lastReadId: String) async throws -> Marker.Content?
  func fetchStatus(client: MastodonClient, id: String) async throws -> Status
}

struct TimelineMarkerFetcher: TimelineMarkerFetching {
  func fetchHomeMarker(client: MastodonClient) async throws -> Marker.Content? {
    let marker: Marker = try await client.get(endpoint: Markers.markers)
    return marker.home
  }

  func saveHomeMarker(client: MastodonClient, lastReadId: String) async throws -> Marker.Content? {
    let marker: Marker = try await client.post(endpoint: Markers.markHome(lastReadId: lastReadId))
    return marker.home
  }

  func fetchStatus(client: MastodonClient, id: String) async throws -> Status {
    try await client.get(endpoint: Statuses.status(id: id))
  }
}
