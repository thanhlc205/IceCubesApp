import Foundation
import os

/// Answers every `URLSession.shared` request with canned JSON, so screens run their real
/// request building and decoding without reaching the network.
///
/// Only requests to `host` are recorded and answered from the queue; the test host app's own
/// screens talk to another server and always get a 404. Responses are queued per method and
/// path and served in order. A request with nothing queued gets a 404 with a Mastodon error
/// body, which `MastodonClient` throws as a `ServerError`. The state is global, so suites that
/// use it must be `.serialized`.
///
/// This is a copy of the stub in `NotificationsTests`, plus the host check. The app's test
/// target can't import a package's test target.
enum StubServer {
  static let host = "stub.example"

  struct Request: Sendable {
    let method: String
    let path: String
    let query: [URLQueryItem]

    func values(_ name: String) -> [String] {
      query.filter { $0.name == name }.compactMap(\.value)
    }

    func value(_ name: String) -> String? {
      values(name).first
    }
  }

  private struct State {
    var queued: [String: [String]] = [:]
    var requests: [Request] = []
  }

  private static let state = OSAllocatedUnfairLock(initialState: State())
  private static let installed = OSAllocatedUnfairLock(initialState: false)

  static func install() {
    installed.withLock { isInstalled in
      guard !isInstalled else { return }
      URLProtocol.registerClass(StubURLProtocol.self)
      isInstalled = true
    }
  }

  static func reset() {
    state.withLock { $0 = State() }
  }

  static func enqueue(_ path: String, method: String = "GET", json: String) {
    state.withLock { $0.queued["\(method) \(path)", default: []].append(json) }
  }

  static func requests(_ path: String, method: String = "GET") -> [Request] {
    state.withLock { $0.requests.filter { $0.method == method && $0.path == path } }
  }

  /// Waits up to five seconds for a screen to send a request to `path`.
  static func waitForRequest(_ path: String, method: String = "GET") async throws -> Request? {
    for _ in 0 ..< 250 {
      if let request = requests(path, method: method).last {
        return request
      }
      try await Task.sleep(for: .milliseconds(20))
    }
    return nil
  }

  fileprivate static func respond(to request: URLRequest) -> (status: Int, body: Data) {
    let notFound = (404, Data(#"{"error":"Record not found"}"#.utf8))
    guard let url = request.url, url.host() == host else { return notFound }
    let recorded = Request(
      method: request.httpMethod ?? "GET",
      path: url.path,
      query: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    )
    return state.withLock { state in
      state.requests.append(recorded)
      let key = "\(recorded.method) \(recorded.path)"
      guard var queue = state.queued[key], !queue.isEmpty else { return notFound }
      let json = queue.removeFirst()
      state.queued[key] = queue
      return (200, Data(json.utf8))
    }
  }
}

private final class StubURLProtocol: URLProtocol {
  override class func canInit(with _: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let (status, body) = StubServer.respond(to: request)
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
