import Models
import SwiftUI
import TelemetryDeck

@MainActor
public class Telemetry {
  private static var isSetUp = false

  /// Starts TelemetryDeck when `TELEMETRYDECK_APP_ID` is set; otherwise every signal is dropped.
  public static func setup() {
    guard let appID = AppInfo.telemetryDeckAppID else { return }
    let config = TelemetryDeck.Config(appID: appID)
    TelemetryDeck.initialize(config: config)
    isSetUp = true
  }

  public static func signal(_ event: String, parameters: [String: String] = [:]) {
    // Signalling before `setup()` crashes TelemetryDeck, e.g. in unit tests.
    guard isSetUp else { return }
    TelemetryDeck.signal(event, parameters: parameters)
  }
}
