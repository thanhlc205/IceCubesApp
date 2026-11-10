import OSLog

extension Logger {
  /// The app target's log. In Console, filter by subsystem `com.icecubesapp` and category `app`.
  static let app = Logger(subsystem: "com.icecubesapp", category: "app")
}
