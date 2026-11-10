import AppKit

/// Physics snow: flakes fall with drag / wobble / wind, land on the highest
/// surface under them (window top, Dock top, screen bottom), and accumulate
/// into piles. Fast-moving surfaces shake their snow off (converted back
/// into falling flakes carrying the window's velocity).
final class SnowEngine {
    struct Flake {
        var position: CGPoint
        var velocity: CGPoint = .zero
        var size: CGFloat = 3
        var phase: CGFloat = 0
        var rotation: CGFloat = 0
        var spin: CGFloat = 0
        var maxFall: CGFloat = 70
    }

    private var flakes: [Flake] = []
    /// surfaceID -> columnIndex(6px) -> height
    private(set) var piles: [Int: [Int: CGFloat]] = [:]
    /// surfaceID -> last time we shook snow off it
    private var lastShake: [Int: TimeInterval] = [:]
    let particles = Particles()
    private var time: CGFloat = 0
    private var windGust: CGFloat = 0

    func surfaceID(forX x: CGFloat) -> Int? {
        _ = x
        return nil
    }

    func snowHeight(surfaceID: Int, offsetX: CGFloat) -> CGFloat {
        let col = Int((offsetX / 6).rounded())
        return piles[surfaceID]?[col] ?? 0
    }

    func clearAll() {
        piles.removeAll()
        flakes.removeAll()
    }

    func shakeOff(surface: Surface) {
        guard let cols = piles[surface.id], !cols.isEmpty else { return }
        for (col, h) in cols where h > 2 {
            let x = surface.left + CGFloat(col) * 6
            let y = surface.top + h
            let n = max(1, Int(h / 7))
            for _ in 0..<n {
                flakes.append(Flake(position: CGPoint(x: x + CGFloat.random(in: -3...3), y: y),
                                    velocity: CGPoint(x: surface.velocity.x * 0.65 + CGFloat.random(in: -25...25),
                                                        y: max(0, surface.velocity.y * 0.4) + CGFloat.random(in: -10...30)),
                                    size: CGFloat.random(in: 2...4.2),
                                    phase: CGFloat.random(in: 0...6.28),
                                    rotation: CGFloat.random(in: 0...6.28),
                                    spin: CGFloat.random(in: -2...2),
                                    maxFall: CGFloat.random(in: 45...95)))
            }
        }
        piles[surface.id] = [:]
    }

    func update(dt: CGFloat, surfaces: [Surface], amount: Double, wind: Double, frame: CGRect) {
        time += dt
        particles.update(dt: dt)
        guard dt > 0 else { return }

        // Slowly varying gust layered on the user's wind setting.
        windGust = sin(time * 0.23) * 22 + sin(time * 0.071) * 14
        let baseWind = CGFloat(wind) * 70 + windGust

        // Shake snow off surfaces moving fast (drag a window left↔right!).
        let now = TimeInterval(time)
        for s in surfaces where s.speed > 650 {
            if now - (lastShake[s.id] ?? -10) > 0.45 {
                lastShake[s.id] = now
                shakeOff(surface: s)
            }
        }

        // Spawn / recycle to target count.
        let target = Int(60 + amount * 380)
        while flakes.count < target {
            flakes.append(spawnFlake(frame: frame))
        }
        if flakes.count > target + 80 {
            flakes.removeFirst(flakes.count - target - 40)
        }

        // Piles slowly compact (so snow doesn't grow forever).
        if Int(time * 2) != Int((time - dt) * 2) {
            for key in Array(piles.keys) {
                var cols = piles[key]!
                for (c, h) in cols {
                    let nh = h * 0.995
                    cols[c] = nh < 0.4 ? 0 : nh
                }
                piles[key] = cols
            }
        }

        for i in flakes.indices {
            var f = flakes[i]
            // Aerodynamics: approach terminal fall speed, wobble sideways.
            let wobble = sin(time * 2.2 + f.phase) * 18
            let targetVX = baseWind + wobble
            let targetVY = -f.maxFall
            f.velocity.x += (targetVX - f.velocity.x) * min(1, dt * 2.4)
            f.velocity.y += (targetVY - f.velocity.y) * min(1, dt * 2.4)
            let prev = f.position
            f.position.x += f.velocity.x * dt
            f.position.y += f.velocity.y * dt
            f.rotation += f.spin * dt

            // Wrap horizontally.
            if f.position.x < frame.minX - 20 { f.position.x = frame.maxX + 16 }
            if f.position.x > frame.maxX + 20 { f.position.x = frame.minX - 16 }

            // Landing: highest surface whose top we crossed this step.
            if f.velocity.y <= 0 {
                var best: (Surface, CGFloat)?
                for s in surfaces where s.containsX(f.position.x) {
                    let top = s.top + snowHeight(surfaceID: s.id, offsetX: f.position.x - s.left)
                    if prev.y >= top - 1 && f.position.y <= top && (best == nil || top > best!.1) {
                        best = (s, top)
                    }
                }
                if let (surface, _) = best {
                    let col = Int(((f.position.x - surface.left) / 6).rounded())
                    var cols = piles[surface.id] ?? [:]
                    // Spread each landing across neighbours so piles form
                    // smooth drifts instead of spikes. Cap keeps windows
                    // near the screen top from burying things off-screen.
                    let add = f.size * 0.4
                    cols[col, default: 0] += add * 0.5
                    cols[col - 1, default: 0] += add * 0.25
                    cols[col + 1, default: 0] += add * 0.25
                    for k in [col - 1, col, col + 1] {
                        if let v = cols[k], v > 14 { cols[k] = 14 }
                    }
                    piles[surface.id] = cols
                    f = spawnFlake(frame: frame)
                }
            }
            flakes[i] = f
        }
    }

    private func spawnFlake(frame: CGRect) -> Flake {
        let size = CGFloat.random(in: 1.6...4.6)
        return Flake(position: CGPoint(x: CGFloat.random(in: frame.minX...frame.maxX),
                                       y: frame.maxY + CGFloat.random(in: 4...120)),
                     velocity: .zero, size: size,
                     phase: CGFloat.random(in: 0...6.28),
                     rotation: CGFloat.random(in: 0...6.28),
                     spin: CGFloat.random(in: -1.5...1.5),
                     maxFall: 38 + size * 16)
    }

    // MARK: Drawing

    func drawFlakes(in ctx: CGContext) {
        for f in flakes {
            ctx.saveGState()
            ctx.translateBy(x: f.position.x, y: f.position.y)
            ctx.rotate(by: f.rotation)
            let a: CGFloat = 0.55 + (f.size / 4.6) * 0.45
            ctx.setFillColor(NSColor.white.withAlphaComponent(a).cgColor)
            let s = f.size
            ctx.fillEllipse(in: CGRect(x: -s / 2, y: -s / 2, width: s, height: s))
            ctx.restoreGState()
        }
    }

    func drawPiles(in ctx: CGContext, surfaces: [Surface]) {
        for s in surfaces {
            guard let cols = piles[s.id], !cols.isEmpty else { continue }
            let keys = cols.keys.sorted()
            // Smoothed heights: average each column with its neighbours so
            // the drift reads as a soft snow line, not icicle spikes.
            func smoothed(_ k: Int) -> CGFloat {
                let a = cols[k - 1] ?? cols[k] ?? 0
                let b = cols[k] ?? 0
                let c = cols[k + 1] ?? cols[k] ?? 0
                return (a + b * 2 + c) / 4
            }
            ctx.saveGState()
            let path = CGMutablePath()
            var started = false
            var minX = CGFloat.greatestFiniteMagnitude, maxX = -CGFloat.greatestFiniteMagnitude
            for k in keys {
                let h = smoothed(k)
                guard h > 0.6 else { continue }
                let x = s.left + CGFloat(k) * 6
                let y = s.top + h
                if !started { path.move(to: CGPoint(x: x, y: s.top)); started = true }
                path.addLine(to: CGPoint(x: x, y: y))
                minX = min(minX, x); maxX = max(maxX, x)
            }
            guard started else { ctx.restoreGState(); continue }
            path.addLine(to: CGPoint(x: maxX, y: s.top))
            path.closeSubpath()
            ctx.addPath(path)
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [NSColor.white.cgColor,
                                           NSColor(calibratedRed: 0.86, green: 0.92, blue: 1.0, alpha: 1).cgColor] as CFArray,
                                  locations: [0, 1])!
            ctx.clip()
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s.top + 16),
                                   end: CGPoint(x: 0, y: s.top), options: [])
            ctx.restoreGState()
            // Sparkle dots on the pile crest.
            ctx.saveGState()
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            for k in keys {
                let h = smoothed(k)
                if h > 2, seededRandom(seed: s.id, index: k) > 0.82 {
                    let x = s.left + CGFloat(k) * 6
                    ctx.fillEllipse(in: CGRect(x: x - 1, y: s.top + h - 1, width: 2, height: 2))
                }
            }
            ctx.restoreGState()
        }
    }
}
