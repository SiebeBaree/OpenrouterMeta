import SwiftUI

/// Menu-bar popover settings (the reliable, always-working surface —
/// see the widget extension for the Notification-Center glanceable view).
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    var trackedWindows: Int
    var onDropPresent: () -> Void
    var onFreezeRandom: () -> Void
    var onClearSnow: () -> Void
    var onResetSnowman: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("❄️").font(.system(size: 26))
                VStack(alignment: .leading, spacing: 1) {
                    Text("OpenrouterMeta").font(.headline)
                    Text("Christmas Mode 🎄 · \(trackedWindows) windows tracked")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Toggle("Snowfall", isOn: $settings.snowEnabled)
            if settings.snowEnabled {
                HStack {
                    Text("Amount").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $settings.snowAmount, in: 0.05...1)
                    Text("\(Int(settings.snowAmount * 100))%").font(.caption.monospacedDigit()).frame(width: 36)
                }
                HStack {
                    Text("Wind").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $settings.wind, in: -1...1)
                    Text(settings.wind < -0.05 ? "←" : settings.wind > 0.05 ? "→" : "·")
                        .font(.caption).frame(width: 16)
                }
            }

            Toggle("Snowman (drag & throw him!)", isOn: $settings.snowmanEnabled)
            Toggle("Ice catapult", isOn: $settings.catapultEnabled)

            Toggle("Santa fly-by + presents", isOn: $settings.santaEnabled)
            if settings.santaEnabled {
                HStack(spacing: 6) {
                    Text("Every").font(.caption).foregroundStyle(.secondary)
                    ForEach([15.0, 30.0, 60.0], id: \.self) { v in
                        Button("\(Int(v))s") { settings.santaInterval = v }
                            .buttonStyle(.bordered)
                            .tint(settings.santaInterval == v ? .red : .gray)
                            .font(.caption)
                    }
                    Spacer()
                    Button("Drop") { onDropPresent() }.font(.caption)
                }
            }

            Toggle("Freeze windows with ice blocks", isOn: $settings.frostEnabled)
            Toggle("Show hints", isOn: $settings.showHints)

            Divider()

            HStack(spacing: 6) {
                Button("Freeze") { onFreezeRandom() }.font(.caption)
                Button("Clear snow") { onClearSnow() }.font(.caption)
                Button("Reset snowman") { onResetSnowman() }.font(.caption)
            }
            HStack {
                Text("Tip: drag any window fast left↔right — its snow shakes off!")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { onQuit() }.font(.caption).foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}
