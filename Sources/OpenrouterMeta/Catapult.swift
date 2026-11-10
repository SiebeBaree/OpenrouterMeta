import AppKit

// MARK: - Catapult + ice-block projectiles

struct Projectile {
    var position: CGPoint
    var velocity: CGPoint
    var rotation: CGFloat = 0
    var size: CGFloat = 22
    var landed = false
}

final class Catapult {
    var position: CGPoint            // base centre (on ground)
    var aimAngle: CGFloat = 0.7      // radians above horizontal
    var aimPower: CGFloat = 0.5      // 0...1
    var isAiming: Bool = false
    var recoil: CGFloat = 0          // decays after firing
    var reloadTimer: CGFloat = 0
    var projectiles: [Projectile] = []
    var dragStart: CGPoint = .zero

    let width: CGFloat = 92
    let height: CGFloat = 64

    var rect: CGRect { CGRect(x: position.x - width / 2, y: position.y, width: width, height: height) }
    var launchPoint: CGPoint {
        CGPoint(x: position.x + cos(aimAngle) * 30, y: position.y + 38 + sin(aimAngle) * 30)
    }

    init(at ground: CGPoint) { position = ground }

    func moveToGround(_ y: CGFloat) {
        // Catapult stays glued to the screen bottom / dock top.
        position.y = y
    }

    func cancelAim() { isAiming = false }

    /// Drag vector from catapult → cursor, mirrored angry-birds style:
    /// pull back (left/down) to aim up-right.
    func updateAim(cursor: CGPoint) {
        let dx = position.x - cursor.x   // pull left = aim right
        let dy = cursor.y - position.y
        let dist = hypot(dx, dy)
        aimPower = min(1, max(0.12, dist / 190))
        // Angle from the pull direction, clamped to a sensible arc.
        var ang = atan2(dy, dx)
        if dx < 0 { ang = atan2(dy, -dx) } // pulling right still launches up-right? keep simple:
        aimAngle = min(1.35, max(0.15, ang))
    }

    func launch() -> Projectile? {
        guard reloadTimer <= 0 else { return nil }
        reloadTimer = 0.55
        recoil = 1
        let speed: CGFloat = 420 + aimPower * 640
        let p = Projectile(position: launchPoint,
                           velocity: CGPoint(x: cos(aimAngle) * speed, y: sin(aimAngle) * speed))
        projectiles.append(p)
        return p
    }

    func trajectoryPoints() -> [CGPoint] {
        guard isAiming else { return [] }
        let speed: CGFloat = 420 + aimPower * 640
        var v = CGPoint(x: cos(aimAngle) * speed, y: sin(aimAngle) * speed)
        var p = launchPoint
        var pts: [CGPoint] = []
        let dt: CGFloat = 0.055
        for step in 0..<26 {
            v.y -= 1400 * dt
            p.x += v.x * dt; p.y += v.y * dt
            if step % 2 == 0 { pts.append(p) }
            if p.y < ScreenSpace.unionFrame.minY - 40 { break }
        }
        return pts
    }

    /// Returns hit events: "window:<id>" or "ground" or "snowman".
    func update(dt: CGFloat, surfaces: [Surface], snowman: Snowman?,
                particles: Particles, onFreezeWindow: (Int) -> Void) {
        if reloadTimer > 0 { reloadTimer -= dt }
        if recoil > 0 { recoil = max(0, recoil - dt * 4) }

        for i in projectiles.indices {
            var pr = projectiles[i]
            if pr.landed { continue }
            pr.velocity.y -= 1400 * dt
            pr.position.x += pr.velocity.x * dt
            pr.position.y += pr.velocity.y * dt
            pr.rotation += dt * (pr.velocity.x * 0.01)

            var consumed = false
            // Hit snowman?
            if let sm = snowman, pr.position.x > sm.rect.minX - 6, pr.position.x < sm.rect.maxX + 6,
               pr.position.y > sm.rect.minY, pr.position.y < sm.rect.maxY + 6 {
                sm.bonk(at: pr.position, particles: particles)
                particles.iceShatter(at: pr.position, velocity: pr.velocity)
                consumed = true
            }
            // Hit a window (anything except screen-bottom strips)?
            if !consumed {
                for s in surfaces where s.type == .window {
                    if pr.position.x >= s.rect.minX && pr.position.x <= s.rect.maxX &&
                       pr.position.y >= s.rect.minY && pr.position.y <= s.rect.maxY {
                        onFreezeWindow(s.id)
                        particles.iceShatter(at: pr.position, velocity: pr.velocity)
                        consumed = true
                        break
                    }
                }
            }
            // Hit ground / dock / snow pile surface top.
            if !consumed, let (s, top) = WindowTracker.surfaceTop(atX: pr.position.x, in: surfaces, snowHeightAt: { surf, x in
                // projectiles don't have snow access here; approximated by caller passing surfaces only.
                _ = x; _ = surf; return 0
            }), pr.position.y <= top + 4, pr.velocity.y < 0 {
                particles.iceShatter(at: CGPoint(x: pr.position.x, y: top + 4), velocity: pr.velocity)
                consumed = true
                _ = s
            }
            if consumed { pr.landed = true }
            projectiles[i] = pr
        }
        projectiles.removeAll { $0.landed }
    }

    // MARK: Drawing

    func draw(in ctx: CGContext, time: CGFloat) {
        // Shadow.
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.2).cgColor)
        ctx.fillEllipse(in: CGRect(x: position.x - 42, y: position.y - 3, width: 84, height: 10))
        ctx.restoreGState()

        ctx.saveGState()
        ctx.translateBy(x: position.x, y: position.y)
        // Recoil shove.
        ctx.translateBy(x: -cos(aimAngle) * recoil * 7, y: -sin(aimAngle) * recoil * 4)

        // Wheels.
        ctx.setFillColor(NSColor(calibratedRed: 0.35, green: 0.22, blue: 0.1, alpha: 1).cgColor)
        for wx in [-30, 30] {
            ctx.fillEllipse(in: CGRect(x: wx - 9, y: 0, width: 18, height: 18))
            ctx.setFillColor(NSColor(calibratedRed: 0.6, green: 0.42, blue: 0.2, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: wx - 4, y: 5, width: 8, height: 8))
            ctx.setFillColor(NSColor(calibratedRed: 0.35, green: 0.22, blue: 0.1, alpha: 1).cgColor)
        }

        // Frame.
        ctx.setFillColor(NSColor(calibratedRed: 0.5, green: 0.33, blue: 0.15, alpha: 1).cgColor)
        ctx.fill(CGRect(x: -40, y: 14, width: 80, height: 10))
        ctx.setFillColor(NSColor(calibratedRed: 0.42, green: 0.27, blue: 0.12, alpha: 1).cgColor)
        ctx.fill(CGRect(x: -34, y: 24, width: 12, height: 16))
        ctx.fill(CGRect(x: 22, y: 24, width: 12, height: 16))

        // Arm, rotating around pivot.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: 34)
        let armAngle = isAiming ? (aimAngle - 0.9) * 0.6 - 0.5 : sin(time * 1.2) * 0.04 - 0.15
        ctx.rotate(by: armAngle)
        ctx.setFillColor(NSColor(calibratedRed: 0.58, green: 0.38, blue: 0.18, alpha: 1).cgColor)
        ctx.fill(CGRect(x: -5, y: 0, width: 10, height: 36))
        // Bucket.
        ctx.setFillColor(NSColor(calibratedRed: 0.3, green: 0.2, blue: 0.3, alpha: 1).cgColor)
        ctx.fill(CGRect(x: -11, y: 34, width: 22, height: 10))
        // Loaded ice block (hidden while aiming/reloading).
        if !isAiming && reloadTimer <= 0 {
            drawIceBlock(in: ctx, at: CGPoint(x: 0, y: 48), size: 18, rotation: 0.3)
        }
        ctx.restoreGState()

        // Pivot bolt.
        ctx.setFillColor(NSColor.systemGray.cgColor)
        ctx.fillEllipse(in: CGRect(x: -4, y: 30, width: 8, height: 8))
        ctx.restoreGState()

        // Trajectory preview.
        if isAiming {
            ctx.saveGState()
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.75).cgColor)
            for (i, p) in trajectoryPoints().enumerated() {
                let r = 3.2 - CGFloat(i) * 0.08
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
            ctx.restoreGState()
        }
    }

    func drawProjectiles(in ctx: CGContext) {
        for pr in projectiles {
            drawIceBlock(in: ctx, at: pr.position, size: pr.size, rotation: pr.rotation)
        }
    }
}

func drawIceBlock(in ctx: CGContext, at p: CGPoint, size: CGFloat, rotation: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: p.x, y: p.y)
    ctx.rotate(by: rotation)
    let r: CGFloat = 5
    let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
    let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    ctx.addPath(path)
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [NSColor(calibratedRed: 0.85, green: 0.95, blue: 1.0, alpha: 0.95).cgColor,
                                   NSColor(calibratedRed: 0.55, green: 0.8, blue: 1.0, alpha: 0.95).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.clip()
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size / 2), end: CGPoint(x: 0, y: -size / 2), options: [])
    ctx.restoreGState()
    ctx.saveGState()
    ctx.translateBy(x: p.x, y: p.y)
    ctx.rotate(by: rotation)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
    ctx.setLineWidth(1.2)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)); ctx.strokePath()
    // Sparkle.
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: -size * 0.22, y: size * 0.1, width: 3, height: 3))
    ctx.restoreGState()
}
