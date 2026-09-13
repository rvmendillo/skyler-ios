import WidgetKit
import SwiftUI

struct NexusWidgetEntry: TimelineEntry {
    let date: Date
}

struct NexusWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> NexusWidgetEntry { NexusWidgetEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (NexusWidgetEntry) -> Void) { completion(NexusWidgetEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NexusWidgetEntry>) -> Void) {
        completion(Timeline(entries: [NexusWidgetEntry(date: Date())], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct NexusQuickWidget: Widget {
    let kind = "NexusQuickWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NexusWidgetProvider()) { _ in
            VStack(alignment: .leading, spacing: 9) {
                HStack { Image(systemName: "brain.head.profile.fill").foregroundStyle(.cyan); Text("NEXUS").font(.headline.bold()); Spacer() }
                Text("Personal Intelligence OS").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Link(destination: URL(string: "nexus://chat")!) { Label("Chat", systemImage: "bubble.left.fill").font(.caption.bold()) }
                    Link(destination: URL(string: "nexus://search")!) { Label("Search", systemImage: "magnifyingglass").font(.caption.bold()) }
                    Link(destination: URL(string: "nexus://capture")!) { Label("Capture", systemImage: "square.and.arrow.down").font(.caption.bold()) }
                }
                Text("Open NEXUS for live model, insight and project status.").font(.caption2).foregroundStyle(.secondary)
            }.padding().containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("NEXUS Quick Actions")
        .description("Jump directly to Chat, Search or Capture without exposing private vault data to the widget process.")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct NexusWidgetBundle: WidgetBundle {
    var body: some Widget { NexusQuickWidget() }
}
