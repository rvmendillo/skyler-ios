import SwiftUI

struct ContentView: View {
    @EnvironmentObject var analytics: AnalyticsService

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Analytics", systemImage: "chart.bar.xaxis") }

            MediaView()
                .tabItem { Label("Media", systemImage: "rectangle.stack") }

            InstagramBrowserScreen()
                .tabItem { Label("Instagram", systemImage: "camera") }

            EndpointExplorerView()
                .tabItem { Label("Endpoints", systemImage: "waveform.path.ecg") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

private struct DashboardView: View {
    @EnvironmentObject var analytics: AnalyticsService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        StatCard(title: "Followers", value: "\(analytics.profile.followers)", subtitle: signed(analytics.followerDelta()))
                        StatCard(title: "Following", value: "\(analytics.profile.follows)", subtitle: nil)
                    }

                    HStack(spacing: 12) {
                        StatCard(title: "Posts", value: "\(analytics.profile.mediaCount)", subtitle: nil)
                        StatCard(title: "Metrics", value: "\(analytics.probes.filter(\.supported).count)", subtitle: "supported")
                    }

                    if !analytics.profile.username.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("@\(analytics.profile.username)")
                                .font(.title2.bold())
                            if !analytics.profile.name.isEmpty {
                                Text(analytics.profile.name)
                                    .foregroundStyle(.secondary)
                            }
                            if !analytics.profile.biography.isEmpty {
                                Text(analytics.profile.biography)
                                    .font(.subheadline)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }

                    Button {
                        Task { await analytics.refreshAll() }
                    } label: {
                        HStack {
                            if analytics.isLoading { ProgressView() }
                            Text(analytics.isLoading ? "Refreshing…" : "Refresh All Official Data")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(analytics.isLoading)

                    if !analytics.lastError.isEmpty {
                        Text(analytics.lastError)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let latest = analytics.snapshots.first {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Latest Snapshot").font(.headline)
                            Text(latest.date.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                            Text("\(latest.metrics.count) numeric metrics saved locally")
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding()
            }
            .navigationTitle("InstagramLens")
        }
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title.bold())
            if let subtitle {
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct MediaView: View {
    @EnvironmentObject var analytics: AnalyticsService

    var body: some View {
        NavigationStack {
            List(analytics.media) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(item.mediaType ?? "MEDIA")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let timestamp = item.timestamp {
                            Text(timestamp.prefix(10))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let caption = item.caption, !caption.isEmpty {
                        Text(caption)
                            .lineLimit(4)
                    }

                    HStack {
                        if let permalink = item.permalink, let url = URL(string: permalink) {
                            Link("Open", destination: url)
                        }
                        if let permalink = item.permalink {
                            ShareLink(item: permalink) {
                                Label("Share/Repost", systemImage: "arrowshape.turn.up.right")
                            }
                        }
                    }
                    .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
            .overlay {
                if analytics.media.isEmpty {
                    ContentUnavailableView("No media loaded", systemImage: "rectangle.stack", description: Text("Add API credentials, then refresh."))
                }
            }
            .navigationTitle("Media")
        }
    }
}

private struct EndpointExplorerView: View {
    @EnvironmentObject var analytics: AnalyticsService
    @State private var showUnsupported = false

    var filtered: [ProbeResult] {
        showUnsupported ? analytics.probes : analytics.probes.filter(\.supported)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Show unsupported", isOn: $showUnsupported)
                }

                ForEach(filtered) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.metric).fontWeight(.semibold)
                            Spacer()
                            Image(systemName: item.supported ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(item.supported ? .green : .secondary)
                        }
                        Text(item.scope)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
            .navigationTitle("Endpoint Explorer")
        }
    }
}

#Preview {
    ContentView().environmentObject(AnalyticsService())
}
