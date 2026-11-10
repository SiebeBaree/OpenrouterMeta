import AppKit

// MARK: - Santa's sleigh (flies across every `interval` seconds)

final class Santa {
    var position: CGPoint = .zero   // centre of sleigh
    var velocity: CGPoint = .zero
    var flying = false
    var droppedPresent = false
    var legPhase: CGFloat = 0
    var onShouldDrop: (() -> Void)?

    let width: CGFloat = 190
    let height: CGFloat = 74

    func launch(fromX x: CGFloat, y: CGFloat, direction: CGFloat, frame: CGRect) {
        flying = true
        droppedPresent = false
        position = CGPoint(x: x, y: y)
        velocity = CGPoint(x: direction * 330, y: 0)
        _ = frame
    }

    func update(dt: CGFloat, frame: CGRect) -> Bool {
        guard flying else { return false }
        legPhase += dt * 14
        position.x += velocity.x * dt
        position.y += sin(legPhase * 0.25) * 6 * dt
        // Drop roughly mid-flight.
        if !droppedPresent, position.x > frame.minX + frame.width * 0.3, position.x < frame.minX + frame.width * 0.7 {
            droppedPresent = true
            onShouldDrop?()
        }
        if position.x < frame.minX - 240 || position.x > frame.maxX + 240 { flying = false }
        return flying
    }

    func draw(in ctx: CGContext, time: CGFloat) {
        guard flying else { return }
        let dir: CGFloat = velocity.x >= 0 ? 1 : -1
        ctx.saveGState()
        ctx.translateBy(x: position.x, y: position.y)
        ctx.scaleBy(x: dir, y: 1)
        ctx.rotate(by: sin(time * 2.2) * 0.03)

        // --- Reindeer (2, galloping) ---
        for (i, rx) in [CGFloat(48), CGFloat(86)].enumerated() {
            let gallop = sin(legPhase + CGFloat(i) * 1.4) * 5
            let bobY = abs(sin(legPhase + CGFloat(i) * 1.4)) * 3
            ctx.saveGState()
            ctx.translateBy(x: rx, y: 6 + bobY)
            // Body.
            ctx.setFillColor(NSColor(calibratedRed: 0.55, green: 0.36, blue: 0.2, alpha: 1).cgColor)
            ctx.fill(CGRect(x: -16, y: 0, width: 32, height: 14))
            // Head.
            ctx.fill(CGRect(x: 12, y: 4, width: 13, height: 11))
            // Legs.
            ctx.setFillColor(NSColor(calibratedRed: 0.45, green: 0.28, blue: 0.15, alpha: 1).cgColor)
            for (lx, ph) in [(-12, 0), (-5, 3.14), (6, 3.14), (12, 0)] as [(CGFloat, CGFloat)] {
                let ly = -6 + sin(legPhase + ph) * 3 + (lx == -12 || lx == 12 ? gallop * 0.4 : -gallop * 0.4)
                ctx.fill(CGRect(x: lx - 2, y: ly, width: 4, height: 10))
            }
            // Antlers.
            ctx.setStrokeColor(NSColor(calibratedRed: 0.8, green: 0.68, blue: 0.45, alpha: 1).cgColor)
            ctx.setLineWidth(1.6)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 19, y: 14)); ctx.addLine(to: CGPoint(x: 24, y: 24)); ctx.addLine(to: CGPoint(x: 21, y: 27))
            ctx.move(to: CGPoint(x: 22, y: 14)); ctx.addLine(to: CGPoint(x: 28, y: 22))
            ctx.strokePath()
            // Harness + glowing nose (Rudolph leads).
            ctx.setFillColor(NSColor.systemRed.cgColor)
            ctx.fill(CGRect(x: 8, y: 2, width: 3, height: 12))
            if i == 1 {
                ctx.setFillColor(NSColor.systemRed.withAlphaComponent(0.6 + sin(time * 6) * 0.4).cgColor)
                ctx.fillEllipse(in: CGRect(x: 23, y: 7, width: 5, height: 5))
            }
            // Eye.
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillEllipse(in: CGRect(x: 20, y: 11, width: 2, height: 2))
            ctx.restoreGState()
        }

        // --- Sleigh ---
        ctx.setFillColor(NSColor.systemRed.cgColor)
        let sleighPath = CGMutablePath()
        sleighPath.move(to: CGPoint(x: -78, y: 4))
        sleighPath.addLine(to: CGPoint(x: -62, y: 18))
        sleighPath.addLine(to: CGPoint(x: -6, y: 18))
        sleighPath.addCurve(to: CGPoint(x: 26, y: 8), control1: CGPoint(x: 8, y: 18), control2: CGPoint(x: 18, y: 14))
        sleighPath.addLine(to: CGPoint(x: 30, y: 4))
        sleighPath.closeSubpath()
        ctx.addPath(sleighPath); ctx.fillPath()
        ctx.setFillColor(NSColor(calibratedRed: 0.6, green: 0.1, blue: 0.1, alpha: 1).cgColor)
        ctx.fill(CGRect(x: -70, y: 16, width: 92, height: 4))
        // Runners.
        ctx.setStrokeColor(NSColor.systemGray.cgColor); ctx.setLineWidth(2.4)
        ctx.beginPath(); ctx.move(to: CGPoint(x: -80, y: 0)); ctx.addLine(to: CGPoint(x: 34, y: 0)); ctx.strokePath()
        // Gold trim + bells.
        ctx.setFillColor(NSColor.systemYellow.cgColor)
        ctx.fill(CGRect(x: -62, y: 17, width: 88, height: 1.6))
        for bx in stride(from: -56, through: 18, by: 12) {
            ctx.fillEllipse(in: CGRect(x: bx, y: 12, width: 3, height: 3))
        }

        // --- Santa ---
        ctx.saveGState()
        ctx.translateBy(x: -34, y: 18)
        ctx.setFillColor(NSColor.systemRed.cgColor)          // suit
        ctx.fill(CGRect(x: -8, y: 0, width: 16, height: 18))
        ctx.setFillColor(NSColor.white.cgColor)               // trim + beard
        ctx.fill(CGRect(x: -8, y: 15, width: 16, height: 3))
        ctx.fillEllipse(in: CGRect(x: -5, y: 16, width: 10, height: 9))
        ctx.setFillColor(NSColor(calibratedRed: 0.98, green: 0.78, blue: 0.62, alpha: 1).cgColor) // face
        ctx.fillEllipse(in: CGRect(x: -4, y: 21, width: 8, height: 7))
        ctx.setFillColor(NSColor.systemRed.cgColor)           // hat
        ctx.beginPath()
        ctx.move(to: CGPoint(x: -5, y: 27)); ctx.addLine(to: CGPoint(x: 5, y: 27)); ctx.addLine(to: CGPoint(x: 9, y: 33)); ctx.closePath(); ctx.fillPath()
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: 7, y: 31, width: 4.5, height: 4.5))
        // Arm waving.
        ctx.setStrokeColor(NSColor.systemRed.cgColor); ctx.setLineWidth(4); ctx.setLineCap(.round)
        ctx.beginPath(); ctx.move(to: CGPoint(x: 6, y: 13)); ctx.addLine(to: CGPoint(x: 13, y: 20 + sin(time * 7) * 2)); ctx.strokePath()
        // Sack of presents.
        ctx.setFillColor(NSColor(calibratedRed: 0.35, green: 0.6, blue: 0.25, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: -19, y: 2, width: 13, height: 11))
        ctx.setFillColor(NSColor.systemRed.cgColor)
        ctx.fill(CGRect(x: -17, y: 6, width: 9, height: 3))
        ctx.restoreGState()
        ctx.restoreGState()
    }
}

// MARK: - Present (parachute airdrop)

final class Present {
    var position: CGPoint          // centre of box
    var velocity: CGPoint = .zero
    var state: State = .falling
    var surfaceID: Int?
    var swayPhase: CGFloat = .random(in: 0...6.28)
    var bounceSquash: CGFloat = 1
    var bounceVel: CGFloat = 0

    enum State { case falling, landed }

    let size: CGFloat = 34
    var rect: CGRect { CGRect(x: position.x - size / 2, y: position.y - size / 2, width: size, height: size) }

    init(at p: CGPoint) { position = p }

    func update(dt: CGFloat, surfaces: [Surface], snow: SnowEngine, particles: Particles) {
        bounceVel += (-(bounceSquash - 1) * 160 - bounceVel * 11) * dt
        bounceSquash += bounceVel * dt
        guard state == .falling else { return }
        swayPhase += dt * 2.4
        velocity.y = max(velocity.y - 260 * dt, -115)     // parachute terminal velocity
        velocity.x = sin(swayPhase) * 26
        position.x += velocity.x * dt
        position.y += velocity.y * dt

        if let (surface, top) = WindowTracker.surfaceTop(atX: position.x, in: surfaces, snowHeightAt: { s, x in
            snow.snowHeight(surfaceID: s.id, offsetX: x - s.left)
        }), position.y - size / 2 <= top, velocity.y <= 0 {
            position.y = top + size / 2
            state = .landed
            surfaceID = surface.id
            bounceVel = -3.2
            particles.poof(at: CGPoint(x: position.x, y: top + 3), count: 10)
            particles.sparkles(at: position, count: 5)
        }
        if position.y < ScreenSpace.unionFrame.minY - 80 { state = .landed }
    }

    func draw(in ctx: CGContext, time: CGFloat) {
        ctx.saveGState()
        // Shadow on ground when landed.
        if state == .landed {
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.18).cgColor)
            ctx.fillEllipse(in: CGRect(x: position.x - 17, y: position.y - size / 2 - 2, width: 34, height: 6))
        }
        if state == .falling {
            // Parachute.
            let sway = sin(swayPhase) * 3
            ctx.setStrokeColor(NSColor.systemGray.cgColor); ctx.setLineWidth(1)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: position.x - 14, y: position.y + 12)); ctx.addLine(to: CGPoint(x: position.x - 18 + sway, y: position.y + 34))
            ctx.move(to: CGPoint(x: position.x + 14, y: position.y + 12)); ctx.addLine(to: CGPoint(x: position.x + 18 + sway, y: position.y + 34))
            ctx.strokePath()
            ctx.setFillColor(NSColor.systemRed.withAlphaComponent(0.92).cgColor)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: position.x - 20 + sway, y: position.y + 34))
            ctx.addCurve(to: CGPoint(x: position.x + 20 + sway, y: position.y + 34),
                         control1: CGPoint(x: position.x - 12 + sway, y: position.y + 52),
                         control2: CGPoint(x: position.x + 12 + sway, y: position.y + 52))
            ctx.closePath(); ctx.fillPath()
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            ctx.fill(CGRect(x: position.x - 2 + sway, y: position.y + 34, width: 4, height: 16))
        }
        ctx.translateBy(x: position.x, y: position.y)
        ctx.scaleBy(x: 1 / bounceSquash, y: bounceSquash)
        // Box.
        let box = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [NSColor(calibratedRed: 0.85, green: 0.16, blue: 0.2, alpha: 1).cgColor,
                                       NSColor(calibratedRed: 0.6, green: 0.08, blue: 0.12, alpha: 1).cgColor] as CFArray,
                              locations: [0, 1])!
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: 3, cornerHeight: 3, transform: nil)); ctx.clip()
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size / 2), end: CGPoint(x: 0, y: -size / 2), options: [])
        ctx.restoreGState()
        ctx.setStrokeColor(NSColor(calibratedRed: 0.45, green: 0.05, blue: 0.08, alpha: 1).cgColor); ctx.setLineWidth(1)
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: 3, cornerHeight: 3, transform: nil)); ctx.strokePath()
        // Ribbon.
        ctx.setFillColor(NSColor.systemYellow.cgColor)
        ctx.fill(CGRect(x: -2.4, y: -size / 2, width: 4.8, height: size))
        ctx.fill(CGRect(x: -size / 2, y: -2.4, width: size, height: 4.8))
        // Bow.
        ctx.setFillColor(NSColor.systemYellow.cgColor)
        ctx.fillEllipse(in: CGRect(x: -8, y: size / 2 - 4, width: 7, height: 5))
        ctx.fillEllipse(in: CGRect(x: 1, y: size / 2 - 4, width: 7, height: 5))
        ctx.restoreGState()

        // "Click me!" hint bubble while landed.
        if state == .landed {
            let bobY = sin(time * 3) * 2
            drawHintBubble(in: ctx, at: CGPoint(x: position.x, y: position.y + size / 2 + 22 + bobY), text: "Click me! 🎁")
        }
    }
}

// MARK: - Christmas tree (grows from a present, removed by 3 taps)

final class ChristmasTree {
    var position: CGPoint          // base centre (trunk bottom)
    var surfaceID: Int?
    var scale: CGFloat = 0.01
    var scaleVelocity: CGFloat = 0
    var targetScale: CGFloat = 1
    var taps: Int = 0
    var shake: CGFloat = 0
    var dying = false
    var deathTimer: CGFloat = 0
    var ornaments: [(x: CGFloat, y: CGFloat, color: NSColor, phase: CGFloat)] = []
    var seed: Int

    let width: CGFloat = 76
    let height: CGFloat = 104

    var rect: CGRect {
        CGRect(x: position.x - width * scale / 2, y: position.y,
               width: width * scale, height: height * scale)
    }

    init(at base: CGPoint, surfaceID: Int?) {
        position = base
        self.surfaceID = surfaceID
        seed = Int.random(in: 0...100000)
        let colors: [NSColor] = [.systemRed, .systemYellow, .systemBlue, .systemPink, .systemOrange, .systemPurple]
        for i in 0..<16 {
            ornaments.append((x: (seededRandom(seed: seed, index: i * 3 + 1) - 0.5) * 44,
                              y: 18 + seededRandom(seed: seed, index: i * 3 + 2) * 62,
                              color: colors[i % colors.count],
                              phase: seededRandom(seed: seed, index: i * 3 + 3) * 6.28))
        }
    }

    func update(dt: CGFloat, particles: Particles) {
        if dying {
            deathTimer += dt
            scale = max(0.01, scale - dt * 2.2)
            if deathTimer > 0.5 { particles.sparkles(at: CGPoint(x: position.x, y: position.y + 40), count: 4) }
            return
        }
        // Spring grow.
        scaleVelocity += ((targetScale - scale) * 90 - scaleVelocity * 10) * dt
        scale += scaleVelocity * dt
        scale = min(scale, 1.35)
        if shake > 0 { shake = max(0, shake - dt * 3) }
    }

    var isGone: Bool { dying && scale <= 0.02 }

    func tap(particles: Particles) {
        taps += 1
        shake = 1
        if taps >= 3 {
            dying = true
            particles.poof(at: CGPoint(x: position.x, y: position.y + 30), count: 14)
            particles.sparkles(at: CGPoint(x: position.x, y: position.y + 50), count: 10)
        } else {
            particles.hearts(at: CGPoint(x: position.x, y: position.y + height * scale + 6), count: 1)
        }
    }

    func draw(in ctx: CGContext, time: CGFloat) {
        guard scale > 0.02 else { return }
        let shakeX = shake > 0 ? sin(time * 42) * 3.5 * shake : 0
        ctx.saveGState()
        ctx.translateBy(x: position.x + shakeX, y: position.y)
        ctx.scaleBy(x: scale, y: scale)

        // Shadow.
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.16).cgColor)
        ctx.fillEllipse(in: CGRect(x: -30, y: -3, width: 60, height: 9))

        // Trunk.
        ctx.setFillColor(NSColor(calibratedRed: 0.4, green: 0.25, blue: 0.12, alpha: 1).cgColor)
        ctx.fill(CGRect(x: -5, y: 0, width: 10, height: 14))

        // Three layered triangles.
        let greens: [NSColor] = [
            NSColor(calibratedRed: 0.08, green: 0.45, blue: 0.2, alpha: 1),
            NSColor(calibratedRed: 0.1, green: 0.55, blue: 0.25, alpha: 1),
            NSColor(calibratedRed: 0.14, green: 0.65, blue: 0.3, alpha: 1),
        ]
        let layers: [(w: CGFloat, y0: CGFloat, y1: CGFloat)] = [(64, 10, 46), (48, 36, 72), (32, 60, 98)]
        for (i, l) in layers.enumerated() {
            ctx.setFillColor(greens[i].cgColor)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: -l.w / 2, y: l.y0))
            ctx.addLine(to: CGPoint(x: l.w / 2, y: l.y0))
            ctx.addLine(to: CGPoint(x: 0, y: l.y1))
            ctx.closePath(); ctx.fillPath()
            // Snow dusting on layer edges.
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.5).cgColor)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: -l.w / 2, y: l.y0))
            ctx.addLine(to: CGPoint(x: l.w / 2, y: l.y0))
            ctx.addLine(to: CGPoint(x: 0, y: l.y0 + 4))
            ctx.closePath(); ctx.fillPath()
        }

        // Twinkling light string (zigzag).
        ctx.setLineWidth(1.2)
        for row in 0..<3 {
            let y = 30 + CGFloat(row) * 24
            let w = 40 - CGFloat(row) * 10
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: -w / 2, y: y + 8))
            ctx.addLine(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: w / 2, y: y + 8))
            ctx.strokePath()
            for j in 0..<5 {
                let lx = -w / 2 + CGFloat(j) * (w / 4)
                let ly = y + 8 - (j % 2 == 0 ? 0 : 4)
                let tw = 0.55 + 0.45 * sin(time * 3.2 + CGFloat(j + row * 2) * 1.3)
                ctx.setFillColor(NSColor(hue: CGFloat((j + row) % 6) / 6, saturation: 0.85, brightness: 1, alpha: 1 * tw).cgColor)
                ctx.fillEllipse(in: CGRect(x: lx - 1.8, y: ly - 1.8, width: 3.6, height: 3.6))
            }
        }

        // Ornaments.
        for o in ornaments {
            let tw = 0.7 + 0.3 * sin(time * 2.4 + o.phase)
            ctx.setFillColor(o.color.withAlphaComponent(tw).cgColor)
            ctx.fillEllipse(in: CGRect(x: o.x - 3, y: o.y - 3, width: 6, height: 6))
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.7).cgColor)
            ctx.fillEllipse(in: CGRect(x: o.x - 1.6, y: o.y + 0.6, width: 1.8, height: 1.8))
        }

        // Star.
        let starY: CGFloat = 104
        let glow = 0.6 + 0.4 * sin(time * 2.8)
        ctx.saveGState()
        ctx.setFillColor(NSColor.systemYellow.withAlphaComponent(0.25 * glow).cgColor)
        ctx.fillEllipse(in: CGRect(x: -13, y: starY - 13, width: 26, height: 26))
        ctx.setFillColor(NSColor.systemYellow.cgColor)
        ctx.beginPath()
        for i in 0..<10 {
            let ang = CGFloat(i) * .pi / 5 - .pi / 2
            let r: CGFloat = i % 2 == 0 ? 8 : 3.4
            let x = cos(ang) * r, y = starY + sin(ang) * r
            if i == 0 { ctx.move(to: CGPoint(x: x, y: y)) } else { ctx.addLine(to: CGPoint(x: x, y: y)) }
        }
        ctx.closePath(); ctx.fillPath()
        ctx.restoreGState()

        // Tap progress.
        if taps > 0 && !dying {
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
            ctx.fill(CGRect(x: -16, y: 110, width: 32, height: 12))
            ctx.setFillColor(NSColor.systemGray.cgColor)
            let label = "\(taps)/3 taps"
            let font = NSFont.systemFont(ofSize: 8, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.systemGray]
            label.draw(with: CGRect(x: -16, y: 112, width: 32, height: 10), options: .usesLineFragmentOrigin, attributes: attrs)
        }
        ctx.restoreGState()
    }
}

// MARK: - Hint bubble

func drawHintBubble(in ctx: CGContext, at p: CGPoint, text: String) {
    let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    let size = (text as NSString).size(withAttributes: [.font: font])
    let rect = CGRect(x: p.x - size.width / 2 - 9, y: p.y - size.height / 2 - 5,
                      width: size.width + 18, height: size.height + 10)
    ctx.saveGState()
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.95).cgColor)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)); ctx.fillPath()
    ctx.setFillColor(NSColor(calibratedRed: 0.15, green: 0.3, blue: 0.5, alpha: 1).cgColor)
    (text as NSString).draw(with: rect, options: .usesLineFragmentOrigin,
                            attributes: [.font: font, .foregroundColor: NSColor(calibratedRed: 0.15, green: 0.3, blue: 0.5, alpha: 1)])
    ctx.restoreGState()
}
