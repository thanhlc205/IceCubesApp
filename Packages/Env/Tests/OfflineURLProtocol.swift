import Foundation

/// Fails every request to `host` with `URLError(.notConnectedToInternet)`, the way requests
/// fail with no network, so a test sees a failed request whatever this machine has running.
/// `.test` names are reserved and never reach a real server. Requests to other hosts go through
/// untouched, and the protocol keeps no state, so suites that use it can run in parallel.
final class OfflineURLProtocol: URLProtocol {
  static let host = "offline.test"

  /// Registers the protocol with `URLSession.shared`, which `MastodonClient` uses. Safe to call
  /// from every test: it registers once.
  static func install() {
    _ = registered
  }

  private static let registered = URLProtocol.registerClass(OfflineURLProtocol.self)

  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == host
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
  }

  override func stopLoading() {}
}
