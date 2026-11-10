import AppKit

/// Tiny shared particle system used by snow poofs, ice shatters, sparkles.
struct Particle {
    var position: CGPoint
    var velocity: CGPoint
    var life: CGFloat = 0
    var maxLife: CGFloat = 0.6
    var size: CGFloat = 4
    var color: NSColor = .white
    var gravity: CGFloat = -300
    var drag: CGFloat = 0.9
    var spin: CGFloat = 0
    var rotation: CGFloat = 0
    var isSparkle: Bool = false

    var alive: Bool { life < maxLife }
    var alpha: CGFloat { max(0, 1 - life / maxLife) }

    mutating func update(dt: CGFloat) {
        life += dt
        velocity.y += gravity * dt
        velocity.x *= pow(drag, dt * 60)
        velocity.y *= pow(drag, dt * 60)
        position.x += velocity.x * dt
        position.y += velocity.y * dt
        rotation += spin * dt
    }
}

final class Particles {
    private(set) var items: [Particle] = []

    func poof(at p: CGPoint, count: Int = 10, spread: CGFloat = 90) {
        for _ in 0..<count {
            let ang = CGFloat.random(in: 0...(CGFloat.pi * 2))
            let sp = CGFloat.random(in: 12...spread)
            items.append(Particle(position: p,
                                  velocity: CGPoint(x: cos(ang) * sp, y: abs(sin(ang)) * sp * 0.7),
                                  maxLife: CGFloat.random(in: 0.35...0.7),
                                  size: CGFloat.random(in: 2...6),
                                  color: .white, gravity: -60, drag: 0.92))
        }
    }

    func iceShatter(at p: CGPoint, velocity: CGPoint) {
        for _ in 0..<16 {
            let ang = CGFloat.random(in: 0...(CGFloat.pi * 2))
            let sp = CGFloat.random(in: 40...260)
            items.append(Particle(position: p,
                                  velocity: CGPoint(x: velocity.x * 0.25 + cos(ang) * sp,
                                                      y: velocity.y * 0.25 + sin(ang) * sp + 60),
                                  maxLife: CGFloat.random(in: 0.4...0.9),
                                  size: CGFloat.random(in: 2.5...7),
                                  color: NSColor(calibratedRed: 0.75, green: 0.9, blue: 1.0, alpha: 0.95),
                                  gravity: -1100, drag: 0.98, spin: CGFloat.random(in: -12...12)))
        }
        poof(at: p, count: 6, spread: 60)
    }

    func sparkles(at p: CGPoint, count: Int = 8, color: NSColor = .systemYellow) {
        for _ in 0..<count {
            let ang = CGFloat.random(in: 0...(CGFloat.pi * 2))
            let sp = CGFloat.random(in: 20...110)
            items.append(Particle(position: p,
                                  velocity: CGPoint(x: cos(ang) * sp, y: sin(ang) * sp),
                                  maxLife: CGFloat.random(in: 0.4...0.9),
                                  size: CGFloat.random(in: 2...4.5),
                                  color: color, gravity: 0, drag: 0.9, isSparkle: true))
        }
    }

    func hearts(at p: CGPoint, count: Int = 3) {
        for _ in 0..<count {
            items.append(Particle(position: CGPoint(x: p.x + CGFloat.random(in: -8...8), y: p.y),
                                  velocity: CGPoint(x: CGFloat.random(in: -14...14), y: CGFloat.random(in: 30...60)),
                                  maxLife: CGFloat.random(in: 0.7...1.1),
                                  size: CGFloat.random(in: 7...11),
                                  color: .systemPink, gravity: 20, drag: 0.98))
        }
    }

    func update(dt: CGFloat) {
        for i in items.indices { items[i].update(dt: dt) }
        items.removeAll { !$0.alive }
    }

    func draw(in ctx: CGContext) {
        for p in items {
            ctx.saveGState()
            ctx.translateBy(x: p.position.x, y: p.position.y)
            ctx.rotate(by: p.rotation)
            ctx.setAlpha(p.alpha)
            p.color.setFill()
            if p.isSparkle {
                let s = p.size * 2
                ctx.fill(CGRect(x: -s / 2, y: -0.8, width: s, height: 1.6))
                ctx.fill(CGRect(x: -0.8, y: -s / 2, width: 1.6, height: s))
            } else {
                ctx.fillEllipse(in: CGRect(x: -p.size / 2, y: -p.size / 2, width: p.size, height: p.size))
            }
            ctx.restoreGState()
        }
        ctx.setAlpha(1)
    }
}
