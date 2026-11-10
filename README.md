# OpenrouterMeta 🎄❄️

A native macOS Christmas desktop game — written in Swift (AppKit + SwiftUI),
where **macOS itself is the game engine**: snow, the snowman, the catapult
and Santa all live on real windows, the Dock and the desktop.

## Features

- **Physics snow** — flakes fall with drag / wobble / wind gusts, land on the
  highest surface under them (window tops, Dock top, screen bottom) and
  accumulate into smooth drifts. Drag any window fast left↔right (>650 px/s)
  and its snow shakes off, carrying the window's velocity.
- **Walking snowman** — strolls along window/Dock tops (waddle, blink, waves,
  cursor-tracking eyes, fading footprints). Drag & throw him: he tumbles with
  squash-and-stretch bounces and a snow poof. Ice blocks bonk him (dizzy stars).
- **Ice catapult** — pull back (Angry-Birds style, with trajectory preview)
  and release to lob ice blocks. Hit a window and it **freezes for 10 s**
  (frost overlay with icicles, crystalline corners, countdown badge, melt-out;
  the frost follows the window if it moves).
- **Santa fly-by** — every 30 s (15/30/60 selectable) Santa + reindeer + sleigh
  cross the sky and parachute-drop a present. Click the present → it grows a
  twinkling Christmas tree. Tap the tree **3×** to remove it (1/3, 2/3 counter).
- **Menu-bar settings (❄️)** — toggles for snowfall / snowman / catapult /
  Santa / frost / hints, snowfall amount + wind sliders, Santa interval,
  plus *Freeze window*, *Clear snow*, *Reset snowman*, *Drop present*.
- **Widget** — a Notification-Center widget (`OpenrouterMetaWidget`) shows
  live Christmas-mode status from the shared defaults.

## Build & run

Requires Xcode 16+ / macOS 14+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
to regenerate the project from `project.yml` (the generated `.xcodeproj` is
committed, so it also opens as-is).

```sh
xcodegen generate            # if you change project.yml
open OpenrouterMeta.xcodeproj
# Run the OpenrouterMeta scheme in Xcode, or:
xcodebuild -project OpenrouterMeta.xcodeproj -scheme OpenrouterMeta \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

The app is an `LSUIElement` menu-bar app (no Dock icon). On launch it
activates once so its overlay panels register with the WindowServer.
No Accessibility permission needed — window discovery uses
`CGWindowListCopyWindowInfo`.

## Controls

| Action | How |
|---|---|
| Drag / throw snowman | Mouse-down on him, drag, release |
| Aim + fire catapult | Mouse-down on catapult, pull back, release |
| Present → tree | Click a landed present |
| Remove tree | Tap it 3 times |
| Shake snow off a window | Drag the window fast left↔right |
| Settings | Click the ❄️ menu-bar icon |

## How it works

- `WindowTracker` polls `CGWindowListCopyWindowInfo` (≈14 Hz) for every
  on-screen window + the Dock, converts Quartz → AppKit coordinates and
  computes per-window velocity.
- `SnowEngine` simulates flakes (terminal velocity, wobble, gusts) and
  per-surface snow piles (6 px columns, smoothed drifts, capped height).
- Two full-screen transparent panels at `.floating` level (above normal
  windows, **below** the menu bar): a click-through snow layer and a
  selectively hit-tested interactive layer (snowman / catapult / Santa /
  presents / trees). Clicks outside hotspots pass through to apps below.
- `FrostManager` draws a per-window frost panel for 10 s after an ice hit.
- Settings persist to shared `UserDefaults` (`group.com.openrouter.OpenrouterMeta`,
  falling back to standard defaults) so the widget reads the same values.

## Project layout

```
project.yml                  XcodeGen spec (app + widget targets)
Sources/OpenrouterMeta/      app: AppDelegate, SnowEngine, Snowman,
                             Catapult, SantaPresentTree, FrostManager,
                             WindowTracker, InteractiveWorld, Overlays, …
Sources/OpenrouterMetaWidget/ WidgetKit Notification-Center widget
Sources/Shared/              settings keys shared by app + widget
```
