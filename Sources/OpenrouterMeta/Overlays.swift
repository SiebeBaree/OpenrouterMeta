import AppKit

/// Creates a borderless, transparent, always-on-top overlay panel that
/// joins every Space and app and never steals focus.
func makeOverlayPanel(frame: CGRect, ignoresMouse: Bool) -> NSPanel {
    let panel = NSPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    // .floating keeps the overlay above every normal window but BELOW the
    // menu bar, so menu-bar icons (incl. our own ❄️ item) stay clickable.
    panel.level = .floating
    panel.ignoresMouseEvents = ignoresMouse
    panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    panel.isFloatingPanel = true
    panel.becomesKeyOnlyIfNeeded = true
    panel.orderFrontRegardless()
    return panel
}

/// Full-screen snow layer: purely visual, clicks pass straight through.
final class SnowOverlayView: NSView {
    var engine: SnowEngine!
    var surfaces: [Surface] = []
    var settings: SettingsStore!

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        engine.drawPiles(in: ctx, surfaces: surfaces)
        engine.drawFlakes(in: ctx)
        engine.particles.draw(in: ctx)
        ctx.restoreGState()
    }
}

/// Interactive layer: draws snowman / catapult / santa / presents / trees.
/// Hit-testing is selective: clicks outside interactive rects fall through
/// to the apps underneath.
final class InteractiveOverlayView: NSView {
    var world: InteractiveWorld!

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let world else { return nil }
        // point is in view coords; world uses global AppKit coords.
        let local = convert(point, from: nil)
        // InteractiveOverlayView fills its panel, whose origin is the union frame origin.
        let global = CGPoint(x: local.x + world.frame.minX, y: local.y + world.frame.minY)
        // Never intercept clicks in the menu-bar strip (top ~28pt).
        if global.y > world.frame.maxY - 28 { return nil }
        if world.hitRects().contains(where: { $0.insetBy(dx: -4, dy: -4).contains(global) }) {
            return self
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        world.mouseDown(at: globalPoint(from: event))
    }
    override func mouseDragged(with event: NSEvent) {
        world.mouseDragged(at: globalPoint(from: event))
    }
    override func mouseUp(with event: NSEvent) {
        world.mouseUp(at: globalPoint(from: event))
    }
    override func mouseMoved(with event: NSEvent) {
        world.mouseMoved(at: globalPoint(from: event))
    }

    private func globalPoint(from event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: local.x + world.frame.minX, y: local.y + world.frame.minY)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        // Panel origin == union frame origin; shift drawing into global coords.
        ctx.translateBy(x: 0, y: 0)
        world.draw(in: ctx)
        ctx.restoreGState()
    }
}
