import SwiftUI

struct RootView: View {
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

private struct REYDLMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.indigo, .purple, .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("R")
                .font(.system(size: 31, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .offset(x: -4)
            Image(systemName: "bolt.fill")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(.white)
                .offset(x: 14, y: 9)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.20), lineWidth: 1)
        }
        .shadow(color: .indigo.opacity(0.30), radius: 12, y: 5)
    }
}

private struct BrandHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 14) {
                REYDLMark()
                    .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text("REYDL")
                            .font(.system(size: 29, weight: .black, design: .rounded))
                            .tracking(2)
                        Text("TURBO")
                            .font(.system(size: 9, weight: .black, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.14), in: Capsule())
                    }
                    Text("Accelerated Download Manager")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.74))
                    Text("Capture • Split • Resume")
                        .font(.caption2.monospaced().weight(.medium))
                        .foregroundStyle(.white.opacity(0.56))
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                brandChip("64× Ranges", icon: "square.split.2x2")
                brandChip("Live Engine", icon: "waveform.path.ecg")
                brandChip("Resume", icon: "play.circle")
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(
            LinearGradient(
                colors: [.black, .indigo.opacity(0.92), .purple.opacity(0.80)],
                startPoint: .bottomTrailing,
                endPoint: .topLeading
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private func brandChip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.white.opacity(0.10), in: Capsule())
    }
}

private struct DownloadDashboard: View {
    @EnvironmentObject private var downloads: DownloadManager

    private var active: Int {
        downloads.items.filter { [.probing, .downloading, .assembling].contains($0.state) }.count
    }

    private var turbo: Int {
        downloads.items.filter { $0.mode == .segmented && $0.state == .downloading }.count
    }

    private var completed: Int {
        downloads.items.filter { $0.state == .completed }.count
    }

    var body: some View {
        HStack(spacing: 10) {
            metric("ACTIVE", value: active, icon: "arrow.down.circle.fill")
            metric("TURBO", value: turbo, icon: "bolt.fill")
            metric("DONE", value: completed, icon: "checkmark.circle.fill")
        }
    }

    private func metric(_ label: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @State private var showingAdd = false
    @State private var urlText = ""

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    BrandHeader()
                    DownloadDashboard()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if downloads.items.isEmpty {
                ContentUnavailableView(
                    "Ready to accelerate",
                    systemImage: "bolt.horizontal.circle",
                    description: Text("Use Safari with the REYDL extension, paste a direct file URL, or browse inside REYDL.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section("Download Queue") {
                    ForEach(downloads.items) { item in
                        DownloadRow(item: item)
                    }
                }
            }
        }
        .navigationTitle("REYDL")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: {
                    Label("Add URL", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                Form {
                    Section("Direct URL") {
                        TextField("https://example.com/file.bin", text: $urlText)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Section {
                        Text("REYDL starts with its live transfer engine, uses parallel byte ranges when the server advertises range support, and automatically falls back to a direct single stream when necessary.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Add Download")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingAdd = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Start") {
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
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.indigo.opacity(0.10))
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(item.state == .failed ? .red : .indigo)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName).font(.headline).lineLimit(2)
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(percentText).font(.caption.monospacedDigit().weight(.bold))
            }

            ProgressView(value: item.progress)
                .tint(item.mode == .segmented ? .indigo : .accentColor)

            HStack(spacing: 16) {
                Text(sizeText).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if item.state == .downloading || item.state == .probing {
                    Button { downloads.pause(item.id) } label: { Image(systemName: "pause.fill") }
                } else if item.state == .paused || item.state == .failed {
                    Button { item.state == .failed ? downloads.retry(item.id) : downloads.resume(item.id) } label: {
                        Image(systemName: item.state == .failed ? "arrow.clockwise" : "play.fill")
                    }
                }
                if let fileURL = downloads.completedURL(for: item) {
                    ShareLink(item: fileURL) { Image(systemName: "square.and.arrow.up") }
                }
                Button(role: .destructive) { downloads.remove(item.id) } label: { Image(systemName: "trash") }
            }
            .buttonStyle(.borderless)

            if let error = item.errorMessage, item.state == .failed {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(3)
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
        default: return item.mode == .segmented ? "bolt.circle.fill" : "arrow.down.circle.fill"
        }
    }

    private var statusText: String {
        switch item.state {
        case .queued: return "Queued"
        case .probing: return "Probing server…"
        case .downloading: return item.mode == .segmented ? "Turbo • \(max(item.segmentCount, 1)) connections" : "Direct transfer • live engine"
        case .paused: return "Paused • resume available"
        case .assembling: return "Joining downloaded segments…"
        case .completed: return "Complete"
        case .failed: return "Needs attention"
        }
    }

    private var percentText: String { item.totalBytes > 0 ? "\(Int(item.progress * 100))%" : "—" }

    private var sizeText: String {
        if item.totalBytes > 0 {
            return "\(item.receivedBytes.reydlByteString) / \(item.totalBytes.reydlByteString)"
        }
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
            Section {
                Stepper("Maximum parallel ranges: \(downloads.segmentLimit)", value: $downloads.segmentLimit, in: 2...64, step: 2)
                LabeledContent("Queue limit", value: "No app-imposed limit")
                LabeledContent("Primary engine", value: "Live URLSession")
                LabeledContent("Resume", value: "Range + persisted queue")
            } header: {
                Text("Turbo Engine")
            } footer: {
                Text("REYDL uses an immediate live transfer engine and parallel HTTP byte ranges when the server supports them. iOS and the server can still limit actual concurrency. Fully suspended apps cannot be guaranteed to keep a live-session transfer running indefinitely.")
            }
            Section("Safari Capture") {
                Text("Enable REYDL in Settings → Apps → Safari → Extensions and set website access to Allow. Safari interception is best-effort; the in-app browser is the most reliable capture route on iOS.")
            }
            Section("Files") {
                Text("Completed files are stored in Documents/REYDL Downloads and exposed through Files app file sharing.")
            }
        }
        .navigationTitle("REYDL Turbo")
    }
}
