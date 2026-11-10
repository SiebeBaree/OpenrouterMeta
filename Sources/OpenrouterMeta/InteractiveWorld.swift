import AppKit

/// Coordinates every interactive Christmas entity: snowman, catapult,
/// Santa, presents, trees — plus mouse interaction (drag snowman, aim
/// catapult, click presents, tap trees). Owns the render loop.
final class InteractiveWorld: NSObject {
    var frame: CGRect = ScreenSpace.unionFrame
    var surfaces: [Surface] = []
    var snow: SnowEngine!
    var settings = SettingsStore.shared
    var frost: FrostManager!

    var snowman: Snowman?
    var catapult: Catapult?
    var santa = Santa()
    var presents: [Present] = []
    var trees: [ChristmasTree] = []
    let particles = Particles()

    private var lastTick = Date()
    private var displayTimer: Timer?
    private var santaTimer: Timer?
    private var nextSantaCountdown: TimeInterval = 30

    // Interaction state
    private var draggingSnowman = false
    private var aimingCatapult = false
    private var mousePos: CGPoint = .zero
    private var dragSamples: [(CGPoint, TimeInterval)] = []
    private var hoverCursor: NSCursor?
    private var hoveringInteractive = false

    var onDraw: (() -> Void)?

    func start() {
        ensureEntities()
        santa.onShouldDrop = { [weak self] in self?.dropPresent() }
        scheduleSanta()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(dropPresent),
                                               name: .omDropPresentNow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetSnowmanObs),
                                               name: .omResetSnowman, object: nil)
    }

    func stop() {
        displayTimer?.invalidate()
        santaTimer?.invalidate()
    }

    private func ensureEntities() {
        if snowman == nil, settings.snowmanEnabled, let s = groundSurface() {
            snowman = Snowman(on: s)
        }
        if catapult == nil, settings.catapultEnabled {
            let groundY = groundSurface()?.top ?? frame.minY
            catapult = Catapult(at: CGPoint(x: frame.minX + 86, y: groundY))
        }
    }

    private func groundSurface() -> Surface? {
        // Prefer the screen bottom of the main screen.
        surfaces.first(where: { $0.type == .screenBottom }) ?? surfaces.last
    }

    private func scheduleSanta() {
        santaTimer?.invalidate()
        guard settings.santaEnabled else { return }
        santaTimer = Timer.scheduledTimer(withTimeInterval: settings.santaInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.launchSanta() }
        }
        nextSantaCountdown = settings.santaInterval
    }

    private func launchSanta() {
        guard settings.santaEnabled, !santa.flying else { return }
        let goRight = CGFloat.random(in: 0...1) < 0.5
        let y = frame.minY + frame.height * CGFloat.random(in: 0.72...0.86)
        santa.launch(fromX: goRight ? frame.minX - 120 : frame.maxX + 120,
                     y: y, direction: goRight ? 1 : -1, frame: frame)
    }

    @objc private func dropPresent() {
        let spawn: CGPoint
        if santa.flying { spawn = santa.position }
        else { spawn = CGPoint(x: frame.minX + frame.width * CGFloat.random(in: 0.2...0.8), y: frame.maxY + 30) }
        let p = Present(at: spawn)
        presents.append(p)
        // Keep at most 3 presents around.
        if presents.count > 3 { presents.removeFirst() }
    }

    @objc private func resetSnowmanObs() {
        if let s = groundSurface() { snowman = Snowman(on: s) }
    }

    // Re-sync when settings change.
    func applySettings() {
        if !settings.snowmanEnabled { snowman = nil }
        else if snowman == nil, let s = groundSurface() { snowman = Snowman(on: s) }
        if !settings.catapultEnabled { catapult = nil }
        else if catapult == nil { ensureEntities() }
        scheduleSanta()
    }

    func updateSurfaces(_ surfaces: [Surface]) {
        self.surfaces = surfaces
        // Catapult glued to bottom / dock top of the main screen.
        if let catapult, let s = groundSurface() {
            catapult.moveToGround(s.top)
        }
        // Trees / landed presents follow their surface; if the surface moves
        // fast they tumble off (physics shake-off, like the snow).
        for tree in trees where !tree.dying {
            if let s = surfaces.first(where: { $0.id == tree.surfaceID }) {
                if s.speed > 750 {
                    // Tumbles off: shrink away with a poof.
                    tree.dying = true
                    particles.poof(at: CGPoint(x: tree.position.x, y: tree.position.y + 40), count: 10)
                } else {
                    let top = s.top + snow.snowHeight(surfaceID: s.id, offsetX: tree.position.x - s.left)
                    tree.position.y = top
                    tree.position.x = min(max(tree.position.x, s.left + 30), s.right - 30)
                }
            }
        }
        for p in presents where p.state == .landed {
            if let s = surfaces.first(where: { $0.id == p.surfaceID }) {
                if s.speed > 750 { p.state = .falling; p.velocity = CGPoint(x: s.velocity.x * 0.5, y: 0) }
                else {
                    let top = s.top + snow.snowHeight(surfaceID: s.id, offsetX: p.position.x - s.left)
                    p.position.y = top + p.size / 2
                }
            }
        }
    }

    private func tick() {
        let now = Date()
        let dt = min(0.05, CGFloat(now.timeIntervalSince(lastTick)))
        lastTick = now
        mousePos = NSEvent.mouseLocation
        guard dt > 0 else { return }

        ensureEntities()
        particles.update(dt: dt)

        if let sm = snowman, settings.snowmanEnabled {
            if !draggingSnowman { sm.update(dt: dt, surfaces: surfaces, snow: snow, mouse: mousePos, particles: particles, time: CGFloat(now.timeIntervalSinceReferenceDate)) }
            else {
                // Spring-lag follow while dragging.
                let target = CGPoint(x: mousePos.x, y: mousePos.y - sm.height / 2)
                sm.position.x += (target.x - sm.position.x) * min(1, dt * 18)
                sm.position.y += (target.y - sm.position.y) * min(1, dt * 18)
                sm.squash = 1 + sin(CGFloat(now.timeIntervalSinceReferenceDate) * 10) * 0.03
            }
        }

        if let cat = catapult, settings.catapultEnabled {
            cat.update(dt: dt, surfaces: surfaces, snowman: snowman, particles: particles) { [weak self] windowID in
                if let s = self?.surfaces.first(where: { $0.id == windowID }) {
                    self?.frost.freeze(windowID: windowID, rect: s.rect)
                }
            }
        }

        _ = santa.update(dt: dt, frame: frame)

        for p in presents { p.update(dt: dt, surfaces: surfaces, snow: snow, particles: particles) }
        for t in trees { t.update(dt: dt, particles: particles) }
        trees.removeAll { $0.isGone }

        onDraw?()
    }

    // MARK: Hit rects / mouse

    func hitRects() -> [CGRect] {
        var rects: [CGRect] = []
        if let sm = snowman { rects.append(sm.rect) }
        if let cat = catapult { rects.append(cat.rect) }
        for p in presents { rects.append(p.rect) }
        for t in trees { rects.append(t.rect) }
        return rects
    }

    func mouseDown(at p: CGPoint) {
        // Presents first (topmost priority).
        if let idx = presents.firstIndex(where: { $0.rect.insetBy(dx: -6, dy: -6).contains(p) && $0.state == .landed }) {
            let present = presents[idx]
            let base = CGPoint(x: present.position.x, y: present.position.y - present.size / 2)
            trees.append(ChristmasTree(at: base, surfaceID: present.surfaceID))
            particles.sparkles(at: present.position, count: 12)
            presents.remove(at: idx)
            return
        }
        // Trees: tap counter (3 taps removes).
        if let tree = trees.first(where: { $0.rect.insetBy(dx: -4, dy: -4).contains(p) && !$0.dying }) {
            tree.tap(particles: particles)
            return
        }
        // Snowman: start drag.
        if let sm = snowman, sm.rect.insetBy(dx: -8, dy: -8).contains(p) {
            draggingSnowman = true
            sm.state = .dragging
            dragSamples = [(p, Date().timeIntervalSinceReferenceDate)]
            return
        }
        // Catapult: start aiming.
        if let cat = catapult, cat.rect.insetBy(dx: -14, dy: -14).contains(p) {
            aimingCatapult = true
            cat.isAiming = true
            cat.dragStart = p
            cat.updateAim(cursor: p)
            return
        }
    }

    func mouseDragged(at p: CGPoint) {
        if draggingSnowman, let sm = snowman {
            dragSamples.append((p, Date().timeIntervalSinceReferenceDate))
            if dragSamples.count > 8 { dragSamples.removeFirst() }
            sm.position = CGPoint(x: p.x, y: p.y - sm.height / 2)
            _ = sm
        } else if aimingCatapult, let cat = catapult {
            cat.updateAim(cursor: p)
        }
    }

    func mouseUp(at p: CGPoint) {
        if draggingSnowman, let sm = snowman {
            draggingSnowman = false
            // Throw velocity from recent drag samples.
            if let first = dragSamples.first, let last = dragSamples.last, last.1 > first.1 {
                let dt = last.1 - first.1
                sm.velocity = CGPoint(x: (last.0.x - first.0.x) / dt, y: (last.0.y - first.0.y) / dt)
                sm.velocity.x = max(-700, min(700, sm.velocity.x))
                sm.velocity.y = max(-200, min(500, sm.velocity.y))
            }
            sm.state = .falling
            dragSamples = []
        } else if aimingCatapult, let cat = catapult {
            aimingCatapult = false
            cat.isAiming = false
            // Only fire if the pull was meaningful.
            let pulled = hypot(cat.position.x - p.x, p.y - cat.position.y)
            if pulled > 26 { _ = cat.launch() }
            else { cat.cancelAim() }
        }
    }

    func mouseMoved(at p: CGPoint) {
        mousePos = p
        let overInteractive = hitRects().contains { $0.insetBy(dx: -4, dy: -4).contains(p) }
        if overInteractive && !hoveringInteractive { NSCursor.pointingHand.push(); hoveringInteractive = true }
        else if !overInteractive && hoveringInteractive { NSCursor.pop(); hoveringInteractive = false }
    }

    // MARK: Drawing

    func draw(in ctx: CGContext) {
        let time = CGFloat(Date().timeIntervalSinceReferenceDate)
        santa.draw(in: ctx, time: time)
        for p in presents { p.draw(in: ctx, time: time) }
        for t in trees { t.draw(in: ctx, time: time) }
        catapult?.draw(in: ctx, time: time)
        catapult?.drawProjectiles(in: ctx)
        snowman?.draw(in: ctx, mouse: mousePos, time: time)
        particles.draw(in: ctx)

        // Hint caption (bottom centre, above the catapult/dock).
        if settings.showHints {
            let text = "❄ Drag the snowman · Pull the catapult to launch ice · Click presents · Tap trees 3× to remove"
            let font = NSFont.systemFont(ofSize: 11, weight: .medium)
            let size = (text as NSString).size(withAttributes: [.font: font])
            let rect = CGRect(x: frame.midX - size.width / 2 - 12, y: frame.minY + 12,
                              width: size.width + 24, height: size.height + 10)
            ctx.saveGState()
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 9, cornerHeight: 9, transform: nil)); ctx.fillPath()
            (text as NSString).draw(with: rect, options: .usesLineFragmentOrigin,
                                    attributes: [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.92)])
            ctx.restoreGState()
        }
    }
}
