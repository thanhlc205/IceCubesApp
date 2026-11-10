import OSLog

extension Logger {
  /// The Env package's log. In Console, filter by subsystem `com.icecubesapp` and category `env`.
  static let env = Logger(subsystem: "com.icecubesapp", category: "env")
}
