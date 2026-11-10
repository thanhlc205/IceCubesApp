import Testing

/// The parent of every suite in this target. The suites share the stub server and the app's
/// services, so `.serialized` runs one test at a time across all of them.
@MainActor
@Suite(.serialized)
struct AppTests {}
