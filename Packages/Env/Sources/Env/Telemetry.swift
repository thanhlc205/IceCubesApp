import SwiftUI
import TelemetryDeck

@MainActor
public class Telemetry {
  private static var isSetUp = false

  public static func setup() {
    let config = TelemetryDeck.Config(appID: "F04175D2-599A-4504-867E-CE870B991EB7")
    TelemetryDeck.initialize(config: config)
    isSetUp = true
  }

  public static func signal(_ event: String, parameters: [String: String] = [:]) {
    // Signalling before `setup()` crashes TelemetryDeck, e.g. in unit tests.
    guard isSetUp else { return }
    TelemetryDeck.signal(event, parameters: parameters)
  }
}
