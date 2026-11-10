import SwiftUI
import WidgetKit

/// Notification-Center widget (the "widget preferred" surface).
/// Shows live Christmas-mode status from the shared app-group defaults
/// and deep-links back into the app's menu-bar popover.
struct StatusEntry: TimelineEntry {
    let date: Date
    let snowOn: Bool
    let snowmanOn: Bool
    let catapultOn: Bool
    let santaOn: Bool
    let interval: Double
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry { entry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(entry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let now = Date()
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: now)!
        completion(Timeline(entries: [entry(date: now)], policy: .after(next)))
    }
    private func entry(date: Date) -> StatusEntry {
        let d = SharedDefaults.userDefaults
        func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) == nil ? def : d.bool(forKey: k) }
        return StatusEntry(
            date: date,
            snowOn: bool(SettingsKeys.snowEnabled, true),
            snowmanOn: bool(SettingsKeys.snowmanEnabled, true),
            catapultOn: bool(SettingsKeys.catapultEnabled, true),
            santaOn: bool(SettingsKeys.santaEnabled, true),
            interval: d.object(forKey: SettingsKeys.santaInterval) == nil ? 30 : d.double(forKey: SettingsKeys.santaInterval))
    }
}

struct StatusWidgetView: View {
    var entry: StatusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("❄️").font(.title2)
                Text("Christmas Mode").font(.headline)
                Spacer()
                Text("🎄").font(.title2)
            }
            statusRow(icon: "Snowfall", on: entry.snowOn)
            statusRow(icon: "Snowman", on: entry.snowmanOn)
            statusRow(icon: "Catapult", on: entry.catapultOn)
            statusRow(icon: "Santa · \(Int(entry.interval))s", on: entry.santaOn)
            Text("Click to open settings")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .containerBackground(.ultraThinMaterial, for: .widget)
    }

    private func statusRow(icon: String, on: Bool) -> some View {
        HStack {
            Text(on ? "✅" : "⬜")
            Text(icon).font(.caption)
            Spacer()
        }
    }
}

@main
struct OpenrouterMetaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenrouterMetaWidget", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Christmas Mode")
        .description("Snow, snowman, catapult and Santa status for OpenrouterMeta.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
