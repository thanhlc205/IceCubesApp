import Foundation
import os

/// Answers `URLSession.shared` requests to `host` with canned JSON, so a real `MastodonClient`
/// runs its real request building and decoding without reaching the network. Point the client
/// at `StubServer.host`.
///
/// Responses are queued per method and path and served in order, each with its status code. A
/// request with nothing queued gets a 404 with a Mastodon error body, which the client throws as
/// a `ServerError`. The state is global, so suites that use it must be `.serialized`.
public enum StubServer {
  public static let host = "stub.example"

  public struct Request: Sendable {
    public let method: String
    public let path: String
    public let query: [URLQueryItem]
    public let body: Data?

    public func values(_ name: String) -> [String] {
      query.filter { $0.name == name }.compactMap(\.value)
    }

    public func value(_ name: String) -> String? {
      values(name).first
    }
  }

  private struct State {
    var queued: [String: [(status: Int, json: String)]] = [:]
    var requests: [Request] = []
  }

  private static let state = OSAllocatedUnfairLock(initialState: State())
  private static let catchesEveryHost = OSAllocatedUnfairLock(initialState: false)
  private static let registered = URLProtocol.registerClass(StubURLProtocol.self)

  /// Registers the stub with `URLSession.shared`, which `MastodonClient` uses. Safe to call from
  /// every test: it registers once.
  ///
  /// With `everyHost`, requests to any other host get a 404 too, so nothing in the test process
  /// reaches the network. Leave it off in a test target that uses `OfflineURLProtocol`, which
  /// must see its own requests.
  public static func install(everyHost: Bool = false) {
    _ = registered
    if everyHost {
      catchesEveryHost.withLock { $0 = true }
    }
  }

  public static func reset() {
    state.withLock { $0 = State() }
  }

  /// Queues an answer. `json` is sent as is, so an error page can be any text.
  public static func enqueue(
    _ path: String, method: String = "GET", status: Int = 200, json: String
  ) {
    state.withLock { $0.queued["\(method) \(path)", default: []].append((status, json)) }
  }

  /// The requests sent to `path` since the last `reset()`, in order.
  public static func requests(_ path: String, method: String = "GET") -> [Request] {
    state.withLock { $0.requests.filter { $0.method == method && $0.path == path } }
  }

  /// Every request sent since the last `reset()`, in order, as "METHOD /path".
  public static var sent: [String] {
    state.withLock { $0.requests.map { "\($0.method) \($0.path)" } }
  }

  /// Waits up to five seconds for a request that the code under test sends from a task it
  /// doesn't await. `matching` keeps a late request from an earlier test from counting.
  public static func waitForRequest(
    _ path: String, method: String = "GET",
    matching: @Sendable (Request) -> Bool = { _ in true }
  ) async throws -> Request? {
    for _ in 0..<250 {
      if let request = requests(path, method: method).last(where: matching) { return request }
      try await Task.sleep(for: .milliseconds(20))
    }
    return nil
  }

  fileprivate static func handles(_ request: URLRequest) -> Bool {
    request.url?.host() == host || catchesEveryHost.withLock { $0 }
  }

  fileprivate static func respond(to request: URLRequest) -> (status: Int, body: Data) {
    let notFound = (404, Data(#"{"error":"Record not found"}"#.utf8))
    guard let url = request.url, url.host() == host else { return notFound }
    let recorded = Request(
      method: request.httpMethod ?? "GET",
      path: url.path,
      query: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [],
      body: request.httpBody ?? request.httpBodyStream.map(readAll))
    return state.withLock { state in
      state.requests.append(recorded)
      let key = "\(recorded.method) \(recorded.path)"
      guard var queue = state.queued[key], !queue.isEmpty else { return notFound }
      let answer = queue.removeFirst()
      state.queued[key] = queue
      return (answer.status, Data(answer.json.utf8))
    }
  }

  private static func readAll(_ stream: InputStream) -> Data {
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { break }
      data.append(buffer, count: count)
    }
    return data
  }
}

private final class StubURLProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool {
    StubServer.handles(request)
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
