import Foundation
import os

/// Answers requests to `host` with canned JSON, so a real `MastodonClient` runs its real
/// request building and decoding without reaching the network. It's a trimmed copy of the
/// Notifications tests' stub that takes only requests to its own host, so other stubs, such as
/// `OfflineURLProtocol`, can sit beside it.
///
/// Responses are queued per method and path and served in order, each with its status code. A
/// request with nothing queued gets a 404 with a Mastodon error body, which the client throws as
/// a `ServerError`. `requests` lists what was sent. The state is global, so suites that use it
/// must be `.serialized`.
enum StubServer {
  static let host = "stub.test"

  private struct State {
    var queued: [String: [(status: Int, json: String)]] = [:]
    var requests: [String] = []
  }

  private static let state = OSAllocatedUnfairLock(initialState: State())
  private static let registered = URLProtocol.registerClass(StubURLProtocol.self)

  /// Registers the stub with `URLSession.shared`, which `MastodonClient` uses. Safe to call from
  /// every test: it registers once.
  static func install() {
    _ = registered
  }

  static func reset() {
    state.withLock { $0 = State() }
  }

  /// Queues an answer. `json` is sent as is, so an error page can be any text.
  static func enqueue(_ path: String, method: String = "GET", status: Int = 200, json: String) {
    state.withLock { $0.queued["\(method) \(path)", default: []].append((status, json)) }
  }

  /// Every request sent since the last `reset()`, in order, as "METHOD /path".
  static var requests: [String] {
    state.withLock { $0.requests }
  }

  fileprivate static func respond(to request: URLRequest) -> (status: Int, body: Data) {
    let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
    return state.withLock { state in
      state.requests.append(key)
      guard var queue = state.queued[key], !queue.isEmpty else {
        return (404, Data(#"{"error":"Record not found"}"#.utf8))
      }
      let answer = queue.removeFirst()
      state.queued[key] = queue
      return (answer.status, Data(answer.json.utf8))
    }
  }
}

private final class StubURLProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == StubServer.host
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let (status, body) = StubServer.respond(to: request)
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
