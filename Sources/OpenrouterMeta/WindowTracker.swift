import AppKit
import Foundation

/// Polls CGWindowListCopyWindowInfo to discover every on-screen window,
/// the Dock, and derives screen-bottom surfaces. Tracks per-window velocity
/// so snow (and trees / presents) can be shaken off fast-moving windows.
final class WindowTracker: ObservableObject {
    @Published private(set) var surfaces: [Surface] = []
    @Published private(set) var trackedWindowCount: Int = 0

    private var timer: Timer?
    private var previous: [Int: SampledSurface] = [:]
    private let pollInterval: TimeInterval = 0.07

    var onSurfacesUpdated: (([Surface]) -> Void)?

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let now = Date()
        let raw = readWindows()
        var next: [SampledSurface] = []

        // --- Real windows + Dock ---
        for w in raw {
            let id = w.id
            let rect = w.rect
            guard rect.width >= 60, rect.height >= 40 else { continue }
            let isDock = w.owner.lowercased() == "dock"
            let type: SurfaceType = isDock ? .dock : .window
            var velocity: CGPoint = .zero
            if let prev = previous[id] {
                let dt = max(0.01, now.timeIntervalSince(prev.sampledAt))
                let vx = (rect.minX - prev.rect.minX) / CGFloat(dt)
                let vy = (rect.minY - prev.rect.minY) / CGFloat(dt)
                // Smooth so jitter from poll quantization doesn't look like a 'fast move'.
                velocity = CGPoint(x: lerp(prev.velocity.x, vx, 0.45),
                                   y: lerp(prev.velocity.y, vy, 0.45))
            }
            next.append(SampledSurface(id: id, type: type, owner: w.owner, rect: rect,
                                       velocity: velocity, sampledAt: now))
        }

        // --- Screen bottoms (always present, under everything) ---
        for (i, screen) in NSScreen.screens.enumerated() {
            let f = screen.frame
            // Only the bottom strip is a surface; snow lands at y = f.minY.
            let bottom = CGRect(x: f.minX, y: f.minY, width: f.width, height: 4)
            next.append(SampledSurface(id: 10000 + i, type: .screenBottom, owner: "Screen",
                                       rect: bottom, velocity: .zero, sampledAt: now))
        }

        let surfaces = next.map { Surface(id: $0.id, type: $0.type, ownerName: $0.owner,
                                          rect: $0.rect, velocity: $0.velocity) }
        previous = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })

        // Only publish when something meaningfully changed (cheap check).
        let changed = surfaces.count != self.surfaces.count ||
            zip(surfaces, self.surfaces).contains { a, b in
                abs(a.rect.minX - b.rect.minX) > 0.5 || abs(a.rect.minY - b.rect.minY) > 0.5 ||
                abs(a.rect.width - b.rect.width) > 0.5 || abs(a.rect.height - b.rect.height) > 0.5
            }
        self.surfaces = surfaces
        trackedWindowCount = surfaces.filter { $0.type == .window }.count
        if changed || true {
            onSurfacesUpdated?(surfaces)
        }
    }

    private struct RawWindow { let id: Int; let owner: String; let rect: CGRect }

    private struct SampledSurface {
        let id: Int; let type: SurfaceType; let owner: String
        let rect: CGRect; let velocity: CGPoint; let sampledAt: Date
    }

    /// CGWindowListCopyWindowInfo returns Quartz coords (origin top-left).
    /// Convert to AppKit coords (origin bottom-left) using the main screen height.
    private func readWindows() -> [RawWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let mainHeight = (NSScreen.main?.frame.maxY ?? ScreenSpace.unionFrame.maxY)
        let ownName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "OpenrouterMeta"
        var out: [RawWindow] = []
        for entry in list {
            guard let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let number = entry[kCGWindowNumber as String] as? Int,
                  let owner = entry[kCGWindowOwnerName as String] as? String else { continue }
            // Skip ourselves (overlay panels are full-screen and would swallow snow).
            if owner == ownName || owner == "OpenrouterMeta" { continue }
            let x = bounds["X"] ?? 0, y = bounds["Y"] ?? 0
            let w = bounds["Width"] ?? 0, h = bounds["Height"] ?? 0
            // Skip menu-bar-height strips and tiny utility windows.
            if h < 40 || w < 60 { continue }
            let appKitRect = CGRect(x: x, y: mainHeight - y - h, width: w, height: h)
            out.append(RawWindow(id: number, owner: owner, rect: appKitRect))
        }
        return out
    }

    /// Highest surface top at x (including accumulated snow height when provided).
    nonisolated static func surfaceTop(atX x: CGFloat, in surfaces: [Surface],
                           snowHeightAt: ((Surface, CGFloat) -> CGFloat)? = nil) -> (Surface, CGFloat)? {
        var best: (Surface, CGFloat)?
        for s in surfaces where s.containsX(x) {
            let extra = snowHeightAt?(s, x) ?? 0
            let top = s.top + extra
            if best == nil || top > best!.1 { best = (s, top) }
        }
        return best
    }
}
