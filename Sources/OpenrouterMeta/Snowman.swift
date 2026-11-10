import AppKit

/// PostHog-style walking snowman: strolls along the top of windows / Dock /
/// screen bottom, waddles, blinks, watches your cursor, can be dragged and
/// thrown — lands with a squash-and-stretch bounce and a snow poof.
final class Snowman {
    enum State { case walking, idle, dragging, falling, bonked }

    var position: CGPoint           // feet position (centre of feet)
    var velocity: CGPoint = .zero
    var direction: CGFloat = 1      // 1 facing right, -1 left
    var state: State = .walking
    var surfaceID: Int?
    var walkPhase: CGFloat = 0
    var idleTimer: CGFloat = 0
    var squash: CGFloat = 1         // <1 squashed, >1 stretched (scaleY)
    var squashVelocity: CGFloat = 0
    var blinkTimer: CGFloat = 2
    var isBlinking: Bool = false
    var bonkTimer: CGFloat = 0
    var waveTimer: CGFloat = 0
    var dragOffset: CGPoint = .zero
    var dragHistory: [(CGPoint, TimeInterval)] = []
    var throwVelocity: CGPoint = .zero
    var hopVelocity: CGPoint = .zero
    var isHopping: Bool = false
    var footprints: [(position: CGPoint, life: CGFloat)] = []
    var footprintPhase: CGFloat = 0

    let height: CGFloat = 62
    let width: CGFloat = 44

    var rect: CGRect {
        CGRect(x: position.x - width / 2, y: position.y, width: width, height: height)
    }
    var headCenter: CGPoint { CGPoint(x: position.x, y: position.y + height - 11) }

    init(on surface: Surface) {
        position = CGPoint(x: surface.left + surface.width / 2, y: surface.top)
        surfaceID = surface.id
    }

    func reset(on surface: Surface) {
        position = CGPoint(x: surface.left + surface.width / 2, y: surface.top)
        velocity = .zero
        state = .walking
        surfaceID = surface.id
        squash = 1
    }

    private func groundY(surfaces: [Surface], snow: SnowEngine, atX x: CGFloat) -> (Surface, CGFloat)? {
        WindowTracker.surfaceTop(atX: x, in: surfaces) { s, _ in
            snow.snowHeight(surfaceID: s.id, offsetX: x - s.left)
        }
    }

    func update(dt: CGFloat, surfaces: [Surface], snow: SnowEngine,
                mouse: CGPoint, particles: Particles, time: CGFloat) {
        // Spring squash.
        let k: CGFloat = 170, damping: CGFloat = 11
        squashVelocity += (-(squash - 1) * k - squashVelocity * damping) * dt
        squash += squashVelocity * dt

        blinkTimer -= dt
        if blinkTimer < 0 { isBlinking.toggle(); blinkTimer = isBlinking ? 0.12 : CGFloat.random(in: 1.6...4.2) }
        if bonkTimer > 0 { bonkTimer -= dt }
        if waveTimer > 0 { waveTimer -= dt }

        switch state {
        case .walking:
            let speed: CGFloat = 46
            position.x += direction * speed * dt
            walkPhase += dt * 9
            // Leave fading footprints.
            footprintPhase += dt
            if footprintPhase > 0.22 {
                footprintPhase = 0
                footprints.append((position, 1))
            }
            guard let (surface, top) = groundY(surfaces: surfaces, snow: snow, atX: position.x) else {
                state = .falling; velocity = CGPoint(x: direction * speed, y: 0); return
            }
            surfaceID = surface.id
            position.y = top
            // Edge behaviour: mostly turn, sometimes hop down to whatever's below.
            let margin: CGFloat = 26
            if position.x < surface.left + margin || position.x > surface.right - margin {
                if CGFloat.random(in: 0...1) < 0.18, let lower = lowerSurface(x: position.x, below: surface, surfaces: surfaces) {
                    isHopping = true
                    hopVelocity = CGPoint(x: direction * 90, y: 230)
                    velocity = hopVelocity
                    state = .falling
                } else {
                    direction *= -1
                    position.x = min(max(position.x, surface.left + margin), surface.right - margin)
                }
            }
            idleTimer += dt
            if idleTimer > 9, CGFloat.random(in: 0...1) < dt * 0.25 {
                state = .idle; idleTimer = 0
            }
            if waveTimer <= 0, CGFloat.random(in: 0...1) < dt * 0.12 { waveTimer = 1.6 }

        case .idle:
            idleTimer += dt
            if let (surface, top) = groundY(surfaces: surfaces, snow: snow, atX: position.x) {
                surfaceID = surface.id; position.y = top
            }
            if idleTimer > CGFloat.random(in: 2...4) { state = .walking; idleTimer = 0; direction = CGFloat.random(in: 0...1) < 0.5 ? -1 : 1 }

        case .dragging:
            // Handled by drag manager (position set externally with spring lag).
            break

        case .falling:
            velocity.y -= 1500 * dt
            position.x += velocity.x * dt
            position.y += velocity.y * dt
            if let (surface, top) = groundY(surfaces: surfaces, snow: snow, atX: position.x),
               position.y <= top, velocity.y <= 0 {
                position.y = top
                surfaceID = surface.id
                let impact = -velocity.y
                particles.poof(at: CGPoint(x: position.x, y: top + 2), count: impact > 300 ? 14 : 7, spread: 80)
                squashVelocity = -impact * 0.012
                if impact > 420 {
                    // Bouncy landing: one small hop back up.
                    velocity = CGPoint(x: velocity.x * 0.4, y: impact * 0.32)
                    if impact > 700 { state = .falling; return }
                }
                velocity = .zero
                state = .walking
                idleTimer = 0
            }
            // Fell off the world (surface removed) — respawn on screen bottom.
            if position.y < ScreenSpace.unionFrame.minY - 200, let s = surfaces.last(where: { $0.type == .screenBottom }) {
                reset(on: s)
            }

        case .bonked:
            if bonkTimer <= 0 { state = .walking }
        }

        for i in footprints.indices { footprints[i].life -= dt * 0.35 }
        footprints.removeAll { $0.life <= 0 }
    }

    private func lowerSurface(x: CGFloat, below: Surface, surfaces: [Surface]) -> Surface? {
        surfaces.filter { $0.id != below.id && $0.top < below.top - 30 && $0.containsX(x) }
                .max(by: { $0.top < $1.top })
    }

    func bonk(at p: CGPoint, particles: Particles) {
        state = .bonked
        bonkTimer = 1.1
        velocity = CGPoint(x: CGFloat.random(in: -40...40), y: 120)
        particles.poof(at: headCenter, count: 12)
        particles.sparkles(at: headCenter, count: 6)
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, mouse: CGPoint, time: CGFloat) {
        // Footprints.
        ctx.saveGState()
        for fp in footprints {
            ctx.setFillColor(NSColor(calibratedRed: 0.82, green: 0.9, blue: 1.0, alpha: 0.5 * fp.life).cgColor)
            ctx.fillEllipse(in: CGRect(x: fp.position.x - 3.5, y: fp.position.y, width: 7, height: 2.6))
        }
        ctx.restoreGState()

        let waddle = state == .walking ? sin(walkPhase) * 0.07 : sin(time * 1.4) * 0.02
        let bob = state == .walking ? abs(sin(walkPhase)) * 2.2 : sin(time * 2) * 0.8
        // Shadow.
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.18).cgColor)
        ctx.fillEllipse(in: CGRect(x: position.x - 19, y: position.y - 2, width: 38, height: 7))
        ctx.restoreGState()

        ctx.saveGState()
        ctx.translateBy(x: position.x, y: position.y + bob)
        ctx.scaleBy(x: direction, y: 1)
        ctx.rotate(by: waddle)
        // Squash & stretch.
        ctx.translateBy(x: 0, y: 0)
        ctx.scaleBy(x: 1 / squash, y: squash)

        // Boots (alternate while walking).
        let step = state == .walking ? sin(walkPhase) * 4 : 0
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(x: -13 + step, y: -1, width: 11, height: 5))
        ctx.fill(CGRect(x: 2 - step, y: -1, width: 11, height: 5))

        // Body: 3 stacked circles.
        func circle(_ c: CGPoint, _ r: CGFloat) {
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            // Soft blue shade at the bottom + highlight at the top.
            ctx.setFillColor(NSColor(calibratedRed: 0.82, green: 0.9, blue: 1.0, alpha: 0.55).cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - r * 0.5, y: c.y - r * 0.85, width: r, height: r * 0.45))
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - r * 0.55, y: c.y + r * 0.25, width: r * 0.6, height: r * 0.4))
            ctx.setStrokeColor(NSColor(calibratedRed: 0.75, green: 0.83, blue: 0.95, alpha: 0.8).cgColor)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        circle(CGPoint(x: 0, y: 13), 13)
        circle(CGPoint(x: 0, y: 31), 10)
        circle(CGPoint(x: 0, y: 47), 8)

        // Stick arms.
        ctx.setStrokeColor(NSColor(calibratedRed: 0.45, green: 0.3, blue: 0.15, alpha: 1).cgColor)
        ctx.setLineWidth(2.2)
        ctx.setLineCap(.round)
        let armSwing = state == .walking ? sin(walkPhase) * 4 : 0
        let waving = waveTimer > 0
        ctx.beginPath()
        // left arm (behind)
        ctx.move(to: CGPoint(x: -9, y: 32)); ctx.addLine(to: CGPoint(x: -19, y: 26 + armSwing))
        // right arm (front) — raised when waving / dragging
        if waving || state == .dragging {
            ctx.move(to: CGPoint(x: 9, y: 32)); ctx.addLine(to: CGPoint(x: 18, y: 44))
            ctx.move(to: CGPoint(x: 18, y: 44)); ctx.addLine(to: CGPoint(x: 22, y: 50))
        } else {
            ctx.move(to: CGPoint(x: 9, y: 32)); ctx.addLine(to: CGPoint(x: 19, y: 26 - armSwing))
        }
        ctx.strokePath()

        // Scarf.
        ctx.setFillColor(NSColor.systemRed.cgColor)
        ctx.fill(CGRect(x: -8, y: 36, width: 16, height: 5))
        ctx.fill(CGRect(x: 4, y: 27, width: 5, height: 10))
        ctx.setFillColor(NSColor.systemYellow.cgColor)
        ctx.fill(CGRect(x: -8, y: 36, width: 16, height: 1.4))

        // Face.
        let head = CGPoint(x: 0, y: 47)
        // Eyes look toward cursor.
        let look = CGPoint(x: max(-2, min(2, (mouse.x - position.x) * 0.012 * direction)),
                           y: max(-1.5, min(1.5, (mouse.y - position.y) * 0.008)))
        ctx.setFillColor(NSColor.black.cgColor)
        if isBlinking || bonkTimer > 0 {
            ctx.setLineWidth(1.4); ctx.setStrokeColor(NSColor.black.cgColor)
            for ex in [-3.2, 3.2] {
                ctx.beginPath(); ctx.move(to: CGPoint(x: ex - 1.6, y: head.y + 2)); ctx.addLine(to: CGPoint(x: ex + 1.6, y: head.y + 2)); ctx.strokePath()
            }
        } else {
            for ex in [-3.2, 3.2] {
                ctx.fillEllipse(in: CGRect(x: ex - 1.3 + look.x, y: head.y + 0.7 + look.y, width: 2.6, height: 3.2))
            }
        }
        // Rosy cheeks.
        ctx.setFillColor(NSColor.systemPink.withAlphaComponent(0.55).cgColor)
        ctx.fillEllipse(in: CGRect(x: -6.4, y: head.y - 2.2, width: 3.4, height: 2.4))
        ctx.fillEllipse(in: CGRect(x: 3, y: head.y - 2.2, width: 3.4, height: 2.4))
        // Carrot nose.
        ctx.setFillColor(NSColor.systemOrange.cgColor)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: head.y - 0.5)); ctx.addLine(to: CGPoint(x: 8.5, y: head.y - 2.4)); ctx.addLine(to: CGPoint(x: 0, y: head.y - 4)); ctx.closePath(); ctx.fillPath()
        // Smile (or 'o' mouth when dragging/falling).
        ctx.setStrokeColor(NSColor.black.cgColor); ctx.setLineWidth(1.1)
        if state == .dragging || state == .falling {
            ctx.strokeEllipse(in: CGRect(x: -1.6, y: head.y - 6.4, width: 3.2, height: 3.6))
        } else {
            ctx.beginPath(); ctx.addArc(center: CGPoint(x: 0, y: head.y - 3.4), radius: 2.6, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false); ctx.strokePath()
        }
        // Top hat.
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(x: -7, y: head.y + 5, width: 14, height: 3))
        ctx.fill(CGRect(x: -5.5, y: head.y + 8, width: 11, height: 9))
        ctx.setFillColor(NSColor.systemRed.cgColor)
        ctx.fill(CGRect(x: -5.5, y: head.y + 8, width: 11, height: 2.6))

        // Dizzy stars when bonked.
        if bonkTimer > 0 {
            ctx.setFillColor(NSColor.systemYellow.cgColor)
            for i in 0..<3 {
                let a = time * 5 + CGFloat(i) * 2.1
                let sx = cos(a) * 9, sy = head.y + 9 + sin(a) * 3
                ctx.fillEllipse(in: CGRect(x: sx - 2, y: sy - 2, width: 4, height: 4))
            }
        }
        ctx.restoreGState()
    }
}
