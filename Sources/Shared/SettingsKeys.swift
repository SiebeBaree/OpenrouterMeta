import Foundation

/// Shared settings keys — compiled into both the app and the widget.
public enum SettingsKeys {
    public static let snowEnabled = "om.snow.enabled"
    public static let snowAmount = "om.snow.amount"          // 0...1
    public static let wind = "om.snow.wind"                  // -1...1
    public static let snowmanEnabled = "om.snowman.enabled"
    public static let catapultEnabled = "om.catapult.enabled"
    public static let santaEnabled = "om.santa.enabled"
    public static let santaInterval = "om.santa.interval"    // seconds 15/30/60
    public static let frostEnabled = "om.frost.enabled"
    public static let showHints = "om.hints.enabled"
    public static let suiteName = "group.com.openrouter.OpenrouterMeta"
}

public enum SharedDefaults {
    public static var userDefaults: UserDefaults {
        UserDefaults(suiteName: SettingsKeys.suiteName) ?? .standard
    }
}
