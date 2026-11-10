import AppKit

/// Frost overlay: when an ice block hits a window, a frosted panel is drawn
/// exactly over that window for 10 seconds (icicles, crystalline corners,
/// melt-out in the last 2 s). The panel follows the window if it moves.
final class FrostManager {
    struct FrozenWindow {
        var id: Int
        var rect: CGRect
        var start: Date
        var duration: TimeInterval = 10
        var panel: NSPanel
        var seed: Int
        var remaining: TimeInterval { max(0, duration - Date().timeIntervalSince(start)) }
        var isExpired: Bool { remaining <= 0 }
    }

    private(set) var frozen: [Int: FrozenWindow] = [:]
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func freeze(windowID: Int, rect: CGRect) {
        guard SettingsStore.shared.frostEnabled else { return }
        if frozen[windowID] != nil { return } // already frozen; don't restart the 10 s
        let panel = makePanel(rect: rect)
        frozen[windowID] = FrozenWindow(id: windowID, rect: rect, start: Date(), panel: panel,
                                        seed: windowID &* 31 &+ 7)
        panel.makeKeyAndOrderFront(nil)
        tick()
    }

    func freezeRandom(surfaces: [Surface]) {
        let windows = surfaces.filter { $0.type == .window && frozen[$0.id] == nil }
        guard let pick = windows.randomElement() else { return }
        freeze(windowID: pick.id, rect: pick.rect)
    }

    private func tick(surfaces: [Surface]? = nil) {
        guard !frozen.isEmpty else { return }
        // Expiry.
        for (id, f) in frozen where f.isExpired {
            f.panel.orderOut(nil)
            frozen.removeValue(forKey: id)
        }
        // Follow windows (caller passes fresh surfaces when available).
        if let surfaces {
            for (id, _) in frozen {
                if let s = surfaces.first(where: { $0.id == id }) {
                    frozen[id]?.rect = s.rect
                } else {
                    // Window closed — unfreeze early.
                    frozen[id]?.panel.orderOut(nil)
                    frozen.removeValue(forKey: id)
                }
            }
        }
        for (_, f) in frozen {
            if f.panel.frame != f.rect { f.panel.setFrame(f.rect, display: true) }
            (f.panel.contentView as? FrostView)?.frozen = f
            f.panel.contentView?.needsDisplay = true
        }
    }

    func update(surfaces: [Surface]) { tick(surfaces: surfaces) }

    func clearAll() {
        for (_, f) in frozen { f.panel.orderOut(nil) }
        frozen.removeAll()
    }
}

private func makePanel(rect: CGRect) -> NSPanel {
    let panel = NSPanel(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .floating
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .stationary, .fullScreenAuxiliary]
    panel.isFloatingPanel = true
    panel.orderFrontRegardless()
    panel.contentView = FrostView(frame: rect)
    panel.contentView?.wantsLayer = true
    return panel
}

final class FrostView: NSView {
    var frozen: FrostManager.FrozenWindow?

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let f = frozen, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds
        let remain = f.remaining
        let alpha: CGFloat = remain < 2 ? CGFloat(remain / 2) * 0.85 + 0.15 : 0.85
        let melt = remain < 2 ? CGFloat(1 - remain / 2) : 0   // 0 solid → 1 melted

        // Translucent frost wash.
        ctx.saveGState()
        ctx.setFillColor(NSColor(calibratedRed: 0.82, green: 0.92, blue: 1.0, alpha: 0.30 * alpha).cgColor)
        ctx.fill(rect)
        // Slight vignette at edges (frost creeps in from the frame).
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [NSColor(calibratedRed: 0.9, green: 0.96, blue: 1.0, alpha: 0.5 * alpha).cgColor,
                                       NSColor(calibratedRed: 0.9, green: 0.96, blue: 1.0, alpha: 0).cgColor] as CFArray,
                              locations: [0, 1])!
        ctx.setStrokeColor(NSColor(calibratedRed: 0.95, green: 0.98, blue: 1.0, alpha: 0.9 * alpha).cgColor)
        ctx.setLineWidth(5)
        ctx.stroke(rect.insetBy(dx: 2.5, dy: 2.5))

        // Crystalline corner patterns (seeded, stable per window).
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.75 * alpha).cgColor)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.55 * alpha).cgColor)
        ctx.setLineWidth(1.1)
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        _ = grad
        for (ci, (origin, sx, sy)) in corners.enumerated() {
            for i in 0..<7 {
                let r = seededRandom(seed: f.seed + ci * 100, index: i)
                let len = (26 + r * 70) * (1 - melt * 0.5)
                let ang = seededRandom(seed: f.seed + ci * 100, index: i + 50)
                // Fan of crystals from the corner.
                let a = (CGFloat(i) / 7) * 1.1 + ang * 0.5
                let dx = cos(a) * len * sx, dy = sin(a) * len * sy
                ctx.beginPath()
                ctx.move(to: origin)
                ctx.addLine(to: CGPoint(x: origin.x + dx, y: origin.y + dy))
                ctx.strokePath()
                ctx.fillEllipse(in: CGRect(x: origin.x + dx - 1.6, y: origin.y + dy - 1.6, width: 3.2, height: 3.2))
            }
        }

        // Icicles hanging from the top edge.
        let icicleCount = Int(rect.width / 46)
        for i in 0..<max(3, icicleCount) {
            let x = rect.minX + 24 + CGFloat(i) * 46 + seededRandom(seed: f.seed, index: i + 200) * 22
            let len = (18 + seededRandom(seed: f.seed, index: i + 300) * 42) * (1 - melt * 0.85)
            guard len > 3 else { continue }
            ctx.setFillColor(NSColor(calibratedRed: 0.88, green: 0.95, blue: 1.0, alpha: 0.8 * alpha).cgColor)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x - 4, y: rect.maxY))
            ctx.addLine(to: CGPoint(x: x + 4, y: rect.maxY))
            ctx.addLine(to: CGPoint(x: x, y: rect.maxY - len))
            ctx.closePath(); ctx.fillPath()
        }

        // Countdown badge: ❄ 7s, top-centre of the frozen window.
        let secs = Int(ceil(remain))
        let label = "❄ Frozen · \(secs)s"
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let size = (label as NSString).size(withAttributes: [.font: font])
        let badge = CGRect(x: rect.midX - size.width / 2 - 10, y: rect.maxY - 30,
                           width: size.width + 20, height: size.height + 10)
        ctx.setFillColor(NSColor(calibratedRed: 0.25, green: 0.45, blue: 0.7, alpha: 0.85 * alpha).cgColor)
        ctx.addPath(CGPath(roundedRect: badge, cornerWidth: 9, cornerHeight: 9, transform: nil)); ctx.fillPath()
        (label as NSString).draw(with: badge, options: .usesLineFragmentOrigin,
                                 attributes: [.font: font, .foregroundColor: NSColor.white])
        ctx.restoreGState()
    }
}
