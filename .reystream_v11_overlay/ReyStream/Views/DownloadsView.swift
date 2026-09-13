import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject var downloads: DownloadManager
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        List {
            if downloads.jobs.isEmpty {
                ContentUnavailableView("No downloads", systemImage: "arrow.down.circle", description: Text("Authorized direct downloads appear here."))
            }
            ForEach(downloads.jobs) { job in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(job.title).font(.headline).lineLimit(1)
                        Spacer()
                        if job.connections > 1 && [.downloading, .paused, .merging].contains(job.status) {
                            Label("\(job.connections)x", systemImage: "point.3.connected.trianglepath.dotted")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ProgressView(value: job.progress)
                    HStack(spacing: 10) {
                        Text(statusText(job)).font(.caption).foregroundStyle(.secondary)
                        if job.speedBytesPerSecond > 0 && job.status == .downloading {
                            Text("• \(ByteCountFormatter.string(fromByteCount: Int64(job.speedBytesPerSecond), countStyle: .file))/s")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        controls(job)
                    }
                    if let e = job.error, job.status == .failed { Text(e).font(.caption).foregroundStyle(.red) }
                }
                .padding(.vertical, 5)
                .swipeActions(edge: .trailing) { Button(role: .destructive) { downloads.remove(job) } label: { Label("Remove", systemImage: "trash") } }
            }
        }
        .navigationTitle("Download Manager")
        .toolbar {
            if downloads.jobs.contains(where: { [.complete, .cancelled].contains($0.status) }) {
                Button("Clear Finished") { downloads.clearFinished() }
            }
        }
    }

    @ViewBuilder private func controls(_ job: DownloadJob) -> some View {
        switch job.status {
        case .probing, .downloading:
            Button { downloads.pause(job) } label: { Image(systemName: "pause.fill") }
            Button(role: .destructive) { downloads.cancel(job) } label: { Image(systemName: "xmark") }
        case .paused:
            Button { downloads.resume(job) } label: { Label("Resume", systemImage: "play.fill") }
        case .failed:
            Button { downloads.retry(job) } label: { Label("Retry", systemImage: "arrow.clockwise") }
        case .complete:
            if let u = job.localURL { Button("Add to Library") { library.registerDownloadedFile(u) } }
        case .queued, .merging, .cancelled:
            EmptyView()
        }
    }

    private func statusText(_ job: DownloadJob) -> String {
        let bytes = job.downloadedBytes > 0 ? ByteCountFormatter.string(fromByteCount: job.downloadedBytes, countStyle: .file) : ""
        let total = (job.totalBytes ?? 0) > 0 ? ByteCountFormatter.string(fromByteCount: job.totalBytes!, countStyle: .file) : ""
        let detail = !bytes.isEmpty && !total.isEmpty ? " • \(bytes) / \(total)" : (!bytes.isEmpty ? " • \(bytes)" : "")
        return job.status.rawValue.capitalized + detail
    }
}
