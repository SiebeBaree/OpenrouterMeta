import AppKit
import Foundation

// MARK: - Surfaces (things snow / snowman / presents can stand on)

enum SurfaceType: String, Sendable {
    case window
    case dock
    case screenBottom
}

struct Surface: Identifiable, Sendable {
    /// CGWindowID for windows, 9999 for dock, 10000+screenIndex for screen bottom.
    let id: Int
    let type: SurfaceType
    let ownerName: String
    /// AppKit global coordinates (origin bottom-left).
    var rect: CGRect
    /// Smoothed velocity in px/s, computed by WindowTracker.
    var velocity: CGPoint = .zero

    var top: CGFloat { rect.maxY }
    var left: CGFloat { rect.minX }
    var right: CGFloat { rect.maxX }
    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
    var speed: CGFloat { hypot(velocity.x, velocity.y) }

    func containsX(_ x: CGFloat, padding: CGFloat = 0) -> Bool {
        x >= left - padding && x <= right + padding
    }
}

// MARK: - Settings store (source of truth, persisted to shared defaults)

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var snowEnabled: Bool { didSet { persist() } }
    @Published var snowAmount: Double { didSet { persist() } }
    @Published var wind: Double { didSet { persist() } }
    @Published var snowmanEnabled: Bool { didSet { persist() } }
    @Published var catapultEnabled: Bool { didSet { persist() } }
    @Published var santaEnabled: Bool { didSet { persist() } }
    @Published var santaInterval: Double { didSet { persist() } }
    @Published var frostEnabled: Bool { didSet { persist() } }
    @Published var showHints: Bool { didSet { persist() } }

    private var isLoading = true

    init() {
        let d = SharedDefaults.userDefaults
        func bool(_ key: String, _ def: Bool) -> Bool {
            d.object(forKey: key) == nil ? def : d.bool(forKey: key)
        }
        func double(_ key: String, _ def: Double) -> Double {
            d.object(forKey: key) == nil ? def : d.double(forKey: key)
        }
        snowEnabled = bool(SettingsKeys.snowEnabled, true)
        snowAmount = double(SettingsKeys.snowAmount, 0.55)
        wind = double(SettingsKeys.wind, 0.15)
        snowmanEnabled = bool(SettingsKeys.snowmanEnabled, true)
        catapultEnabled = bool(SettingsKeys.catapultEnabled, true)
        santaEnabled = bool(SettingsKeys.santaEnabled, true)
        santaInterval = double(SettingsKeys.santaInterval, 30)
        frostEnabled = bool(SettingsKeys.frostEnabled, true)
        showHints = bool(SettingsKeys.showHints, true)
        isLoading = false
    }

    private func persist() {
        guard !isLoading else { return }
        let d = SharedDefaults.userDefaults
        d.set(snowEnabled, forKey: SettingsKeys.snowEnabled)
        d.set(snowAmount, forKey: SettingsKeys.snowAmount)
        d.set(wind, forKey: SettingsKeys.wind)
        d.set(snowmanEnabled, forKey: SettingsKeys.snowmanEnabled)
        d.set(catapultEnabled, forKey: SettingsKeys.catapultEnabled)
        d.set(santaEnabled, forKey: SettingsKeys.santaEnabled)
        d.set(santaInterval, forKey: SettingsKeys.santaInterval)
        d.set(frostEnabled, forKey: SettingsKeys.frostEnabled)
        d.set(showHints, forKey: SettingsKeys.showHints)
    }

    func dropPresentNow() { NotificationCenter.default.post(name: .omDropPresentNow, object: nil) }
    func freezeRandomWindow() { NotificationCenter.default.post(name: .omFreezeRandomWindow, object: nil) }
    func clearSnow() { NotificationCenter.default.post(name: .omClearSnow, object: nil) }
    func resetSnowman() { NotificationCenter.default.post(name: .omResetSnowman, object: nil) }
}

extension Notification.Name {
    static let omDropPresentNow = Notification.Name("om.dropPresentNow")
    static let omFreezeRandomWindow = Notification.Name("om.freezeRandomWindow")
    static let omClearSnow = Notification.Name("om.clearSnow")
    static let omResetSnowman = Notification.Name("om.resetSnowman")
}

// MARK: - Geometry helpers

extension CGFloat {
    var clampedToUnit: CGFloat { self < 0 ? 0 : self > 1 ? 1 : self }
}

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

/// Deterministic pseudo-random from an Int seed (stable frost / sparkle patterns).
func seededRandom(seed: Int, index: Int) -> CGFloat {
    var x = UInt64(bitPattern: Int64(seed &* 6364136223846793005 &+ index &* 1442695040888963407 &+ 1))
    x ^= x >> 33
    x = x &* 0xff51afd7ed558ccd
    x ^= x >> 33
    return CGFloat(x % 10000) / 10000.0
}

enum ScreenSpace {
    nonisolated static var unionFrame: CGRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return CGRect(x: 0, y: 0, width: 1440, height: 900) }
        return screens.reduce(CGRect.null) { $0.union($1.frame) }
    }
    nonisolated static var mainFrame: CGRect {
        NSScreen.main?.frame ?? unionFrame
    }
}
