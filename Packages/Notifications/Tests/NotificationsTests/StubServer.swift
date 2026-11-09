import Foundation
import os

/// Answers every `URLSession.shared` request with canned JSON, so a real `MastodonClient`
/// runs its real request building and decoding without reaching the network.
///
/// Responses are queued per method and path and served in order. A request with nothing queued
/// gets a 404 with a Mastodon error body, which the client throws as a `ServerError`.
/// The state is global, so suites that use it must be `.serialized`.
enum StubServer {
  struct Request: Sendable {
    let method: String
    let path: String
    let query: [URLQueryItem]
    let body: Data?

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

  /// Waits up to two seconds for a request the code under test sends from a task it doesn't
  /// await. `matching` keeps a late request from an earlier test from counting.
  static func waitForRequest(
    _ path: String, method: String, matching: @Sendable (Request) -> Bool
  ) async throws -> Request? {
    for _ in 0..<100 {
      if let request = requests(path, method: method).last(where: matching) { return request }
      try await Task.sleep(for: .milliseconds(20))
    }
    return nil
  }

  fileprivate static func respond(to request: URLRequest) -> (status: Int, body: Data) {
    let url = request.url!
    let recorded = Request(
      method: request.httpMethod ?? "GET",
      path: url.path,
      query: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [],
      body: request.httpBody ?? request.httpBodyStream.map(readAll))
    return state.withLock { state in
      state.requests.append(recorded)
      let key = "\(recorded.method) \(recorded.path)"
      guard var queue = state.queued[key], !queue.isEmpty else {
        return (404, Data(#"{"error":"Record not found"}"#.utf8))
      }
      let json = queue.removeFirst()
      state.queued[key] = queue
      return (200, Data(json.utf8))
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
  override class func canInit(with request: URLRequest) -> Bool { true }

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
