import AppKit
import Combine
import SwiftUI

/// Menu-bar app entry point. Owns the overlay panels, the render loops,
/// and the status-item popover. LSUIElement = true in Info.plist, so
/// there is no Dock icon — just the ❄️ menu-bar item.
@main
enum AppMain {
    // Retained for the lifetime of the process (NSApplication.delegate is weak).
    private static let delegate = AppDelegate()

    static func main() {
        NSApplication.shared.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var snowPanel: NSPanel!
    private var interactivePanel: NSPanel!
    private var snowView: SnowOverlayView!
    private var interactiveView: InteractiveOverlayView!

    private let settings = SettingsStore.shared
    private let tracker = WindowTracker()
    private let snow = SnowEngine()
    private let frost = FrostManager()
    private let world = InteractiveWorld()
    private var cancellables = Set<AnyCancellable>()
    private var snowTimer: Timer?
    private var lastSnowTick = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupPanels()
        setupWorld()
        setupStatusItem()
        setupActions()
        tracker.start()
        frost.start()
        world.start()
        startSnowLoop()
        applySettingsVisibility()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Panels

    private func setupPanels() {
        let frame = ScreenSpace.unionFrame
        world.frame = frame
        world.snow = snow
        world.settings = settings
        world.frost = frost

        snowPanel = makeOverlayPanel(frame: frame, ignoresMouse: true)
        snowView = SnowOverlayView(frame: frame)
        snowView.engine = snow
        snowView.settings = settings
        snowPanel.contentView = snowView
        snowPanel.contentView?.wantsLayer = true

        interactivePanel = makeOverlayPanel(frame: frame, ignoresMouse: false)
        interactiveView = InteractiveOverlayView(frame: frame)
        interactiveView.world = world
        interactivePanel.contentView = interactiveView
        interactivePanel.contentView?.wantsLayer = true

        // Interactive layer sits just above the snow layer so the
        // snowman / catapult stay crisp on top of the falling snow.
        interactivePanel.level = .floating
        snowPanel.level = .floating - 1

    }

    private func setupWorld() {
        world.onDraw = { [weak self] in
            self?.interactiveView.needsDisplay = true
        }
        tracker.onSurfacesUpdated = { [weak self] surfaces in
            guard let self else { return }
            world.updateSurfaces(surfaces)
            self.snowView.surfaces = surfaces
            self.frost.update(surfaces: surfaces)
        }
        // Publish tracked-window count into the popover.
        tracker.$trackedWindowCount.sink { [weak self] _ in
            self?.refreshPopover()
        }.store(in: &cancellables)
    }

    // MARK: Snow loop

    private func startSnowLoop() {
        snowTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            let dt = min(0.05, CGFloat(now.timeIntervalSince(self.lastSnowTick)))
            self.lastSnowTick = now
            if self.settings.snowEnabled {
                self.snow.update(dt: dt, surfaces: self.snowView.surfaces,
                                 amount: self.settings.snowAmount, wind: self.settings.wind,
                                 frame: self.snowView.frame)
                self.snowView.needsDisplay = true
            }
        }
    }

    // MARK: Status item + popover

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            // Proper menu-bar glyph: SF Symbol rendered as a template image
            // (monochrome, 16pt, aligned with the other menu-bar icons).
            // The previous emoji-text title rendered oversized and clipped.
            if let image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "OpenrouterMeta Christmas settings") {
                image.isTemplate = true
                let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium, scale: .medium)
                let sized = image.withSymbolConfiguration(config) ?? image
                button.image = sized
                button.imagePosition = .imageOnly
            }
            button.title = ""
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
            button.toolTip = "OpenrouterMeta — Christmas settings"
        }
        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = true
        refreshPopover()
    }

    private func refreshPopover() {
        guard popover != nil else { return }
        let view = SettingsView(settings: settings,
                                trackedWindows: tracker.trackedWindowCount,
                                onDropPresent: { self.settings.dropPresentNow() },
                                onFreezeRandom: { self.frost.freezeRandom(surfaces: self.snowView.surfaces) },
                                onClearSnow: { self.snow.clearAll() },
                                onResetSnowman: { self.settings.resetSnowman() },
                                onQuit: { NSApp.terminate(nil) })
        let host = NSHostingController(rootView: view)
        host.view.wantsLayer = true
        // Follow the system appearance so the popover matches dark/light mode.
        host.view.appearance = NSApp.effectiveAppearance
        popover.appearance = NSApp.effectiveAppearance
        popover.contentViewController = host
        // Size from the SwiftUI content's fitting size so nothing is clipped.
        host.view.layoutSubtreeIfNeeded()
        let fitting = host.view.fittingSize
        popover.contentSize = NSSize(width: max(300, fitting.width),
                                    height: max(380, fitting.height))
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown { popover.close() }
        else if let button = statusItem.button {
            // Activate first so the popover's controls receive events reliably.
            NSApp.activate(ignoringOtherApps: true)
            refreshPopover()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        }
    }

    // MARK: Settings plumbing

    private func setupActions() {
        NotificationCenter.default.addObserver(self, selector: #selector(clearSnowObs),
                                               name: .omClearSnow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(freezeRandomObs),
                                               name: .omFreezeRandomWindow, object: nil)

        // Observe settings changes from the SwiftUI popover.
        settings.$snowEnabled.sink { [weak self] _ in self?.applySettingsVisibility() }.store(in: &cancellables)
        settings.$snowmanEnabled.sink { [weak self] _ in self?.world.applySettings() }.store(in: &cancellables)
        settings.$catapultEnabled.sink { [weak self] _ in self?.world.applySettings() }.store(in: &cancellables)
        settings.$santaEnabled.sink { [weak self] _ in self?.world.applySettings() }.store(in: &cancellables)
        settings.$santaInterval.sink { [weak self] _ in self?.world.applySettings() }.store(in: &cancellables)
    }

    private func applySettingsVisibility() {
        if settings.snowEnabled { snowPanel.orderFrontRegardless() }
        else { snowPanel.orderOut(nil); snow.clearAll() }
    }

    @objc private func clearSnowObs() { snow.clearAll() }
    @objc private func freezeRandomObs() { frost.freezeRandom(surfaces: snowView.surfaces) }

    func applicationWillTerminate(_ notification: Notification) {
        snowTimer?.invalidate()
        tracker.stop()
        frost.stop()
        world.stop()
    }
}

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) { /* keep state */ }
}
