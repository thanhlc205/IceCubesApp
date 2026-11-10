import OSLog

extension Logger {
  /// The Account package's log. In Console, filter by subsystem `com.icecubesapp` and category
  /// `account`.
  static let account = Logger(subsystem: "com.icecubesapp", category: "account")
}
