import Foundation

public struct ServerError: Decodable, Error {
  public let error: String?
  public var httpCode: Int?

  public init(error: String?, httpCode: Int?) {
    self.error = error
    self.httpCode = httpCode
  }
}

extension ServerError: Sendable {}
