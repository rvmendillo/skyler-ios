import Foundation

enum DownloadState: String, Codable {
    case queued, probing, downloading, paused, assembling, completed, failed
}

enum DownloadMode: String, Codable {
    case unknown, segmented, single
}

struct DownloadItem: Identifiable, Codable, Equatable {
    var id: UUID
    var urlString: String
    var fileName: String
    var state: DownloadState
    var mode: DownloadMode
    var createdAt: Date
    var totalBytes: Int64
    var receivedBytes: Int64
    var segmentCount: Int
    var completedSegments: Int
    var errorMessage: String?
    var etag: String?
    var lastModified: String?

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(receivedBytes) / Double(totalBytes)))
    }

    var sourceURL: URL? { URL(string: urlString) }
}

extension Int64 {
    var reydlByteString: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
