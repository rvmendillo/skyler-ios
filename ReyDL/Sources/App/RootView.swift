import SwiftUI

struct RootView: View {
    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        TabView {
            NavigationStack { DownloadsView() }
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle.fill") }
            NavigationStack { BrowserScreen() }
                .tabItem { Label("Browser", systemImage: "safari.fill") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Turbo", systemImage: "bolt.fill") }
        }
        .tint(.indigo)
    }
}

private struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13).fill(.white.opacity(0.12))
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 30, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text("REYDL")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .tracking(2)
                Text("Accelerated Download Engine")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(
            LinearGradient(colors: [.indigo, .purple, .black], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }
}

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @State private var showingAdd = false
    @State private var urlText = ""

    var body: some View {
        List {
            Section { BrandHeader().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            if downloads.items.isEmpty {
                ContentUnavailableView("No downloads yet", systemImage: "arrow.down.doc", description: Text("Use Safari with the REYDL extension, paste a URL, or browse inside REYDL."))
                    .listRowBackground(Color.clear)
            } else {
                Section("Queue") {
                    ForEach(downloads.items) { item in
                        DownloadRow(item: item)
                    }
                }
            }
        }
        .navigationTitle("Downloads")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                Form {
                    TextField("https://example.com/file.zip", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .navigationTitle("Add URL")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingAdd = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Download") {
                            downloads.add(urlString: urlText)
                            urlText = ""
                            showingAdd = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

private struct DownloadRow: View {
    @EnvironmentObject private var downloads: DownloadManager
    let item: DownloadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName).font(.headline).lineLimit(2)
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(percentText).font(.caption.monospacedDigit().weight(.semibold))
            }

            ProgressView(value: item.progress)

            HStack(spacing: 16) {
                Text(sizeText).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if item.state == .downloading || item.state == .probing {
                    Button { downloads.pause(item.id) } label: { Image(systemName: "pause.fill") }
                } else if item.state == .paused || item.state == .failed {
                    Button { item.state == .failed ? downloads.retry(item.id) : downloads.resume(item.id) } label: { Image(systemName: item.state == .failed ? "arrow.clockwise" : "play.fill") }
                }
                if let fileURL = downloads.completedURL(for: item) {
                    ShareLink(item: fileURL) { Image(systemName: "square.and.arrow.up") }
                }
                Button(role: .destructive) { downloads.remove(item.id) } label: { Image(systemName: "trash") }
            }
            .buttonStyle(.borderless)

            if let error = item.errorMessage, item.state == .failed {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    private var icon: String {
        switch item.state {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .paused: return "pause.circle.fill"
        case .assembling: return "arrow.triangle.2.circlepath"
        default: return "arrow.down.circle.fill"
        }
    }

    private var statusText: String {
        switch item.state {
        case .queued: return "Queued"
        case .probing: return "Checking server capabilities…"
        case .downloading: return item.mode == .segmented ? "Turbo • \(max(item.segmentCount, 1)) ranges" : "Background transfer"
        case .paused: return "Paused"
        case .assembling: return "Joining segments…"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    private var percentText: String { item.totalBytes > 0 ? "\(Int(item.progress * 100))%" : "—" }
    private var sizeText: String {
        if item.totalBytes > 0 { return "\(item.receivedBytes.reydlByteString) / \(item.totalBytes.reydlByteString)" }
        return item.receivedBytes.reydlByteString
    }
}

struct SettingsView: View {
    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        Form {
            Section {
                BrandHeader()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section("Turbo engine") {
                Stepper("Maximum parallel ranges: \(downloads.segmentLimit)", value: $downloads.segmentLimit, in: 2...64, step: 2)
                LabeledContent("Queue limit", value: "No app-imposed limit")
                LabeledContent("Background engine", value: "URLSession")
                LabeledContent("Resume", value: "Range + task persistence")
            } footer: {
                Text("REYDL uses 2–64 HTTP byte ranges when the server supports them. iOS and the remote server can still cap real simultaneous connections, so higher is not always faster.")
            }
            Section("Safari") {
                Text("Enable REYDL in Settings → Apps → Safari → Extensions. Download-style links are handed to the app when Safari permits the custom-scheme handoff. Use the in-app browser for the most reliable capture.")
            }
            Section("Files") {
                Text("Completed files are stored in Documents/REYDL Downloads and are exposed through Files app file sharing.")
            }
        }
        .navigationTitle("REYDL Turbo")
    }
}
