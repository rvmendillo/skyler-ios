import Foundation
import SwiftUI
import Photos
import AVFoundation
import UIKit
import ZIPFoundation
import UniformTypeIdentifiers

struct NexusMediaImportReport: Hashable {
    var imported = 0
    var skipped = 0
    var failed = 0
    var bytesCopied: Int64 = 0
    var detail: String = ""

    var summary: String {
        var parts = ["\(imported) media file\(imported == 1 ? "" : "s") imported"]
        if skipped > 0 { parts.append("\(skipped) skipped") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: " • ")
    }
}

enum NexusMediaTypes {
    static let imageExtensions: Set<String> = ["png","jpg","jpeg","heic","heif","webp","gif","bmp","tif","tiff"]
    static let videoExtensions: Set<String> = ["mov","mp4","m4v","avi","mpeg","mpg","3gp","3g2","mts","m2ts","webm"]
    static let allExtensions = imageExtensions.union(videoExtensions)

    static func isImage(_ url: URL) -> Bool { imageExtensions.contains(url.pathExtension.lowercased()) }
    static func isVideo(_ url: URL) -> Bool { videoExtensions.contains(url.pathExtension.lowercased()) }
}

@MainActor
final class NexusMediaIngestionStore: ObservableObject {
    static let shared = NexusMediaIngestionStore()

    @Published private(set) var busy = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var status = "Media ingestion ready"
    @Published private(set) var lastReport = NexusMediaImportReport()

    private let minimumFreeBytes: Int64 = 1_500_000_000
    private let maximumSingleMediaBytes: Int64 = 2_500_000_000

    func importMedia(from selections: [URL]) async -> NexusMediaImportReport {
        guard !busy else { return lastReport }
        busy = true
        progress = 0
        status = "Scanning for photos and videos…"
        defer { busy = false }

        var report = NexusMediaImportReport()
        var candidates: [NexusMediaCandidate] = []

        for source in selections {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            do {
                candidates.append(contentsOf: try scan(source))
            } catch {
                report.failed += 1
            }
        }

        if candidates.isEmpty {
            status = "No photo/video files found in this selection"
            lastReport = report
            return report
        }

        let total = candidates.count
        for (index, candidate) in candidates.enumerated() {
            status = "Importing media • \(index + 1)/\(total) • \(candidate.name)"
            progress = Double(index) / Double(max(1, total))

            guard hasStorageHeadroom(extraBytes: candidate.size) else {
                report.skipped += total - index
                report.detail = "Stopped before storage became critically low."
                break
            }
            guard candidate.size <= maximumSingleMediaBytes else {
                report.skipped += 1
                continue
            }

            do {
                if alreadyImported(name: candidate.name, size: candidate.size) {
                    report.skipped += 1
                } else {
                    let temp = try candidate.materialize()
                    defer { if candidate.removeAfterImport { cleanupTemporaryMedia(temp) } }
                    let imported = try NexusV8FileLibrary.shared.importURLs([temp])
                    if imported.isEmpty {
                        report.failed += 1
                    } else {
                        report.imported += imported.count
                        report.bytesCopied += candidate.size
                    }
                }
            } catch {
                report.failed += 1
            }

            progress = Double(index + 1) / Double(max(1, total))
            await Task.yield()
        }

        lastReport = report
        status = report.summary
        if report.imported > 0 {
            await NexusPreanalysisStore.shared.analyzePending(NexusV8FileLibrary.shared.files)
        }
        return report
    }

    func importRecentPhotoLibrary(limit: Int?) async -> NexusMediaImportReport {
        guard !busy else { return lastReport }
        let auth = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard auth == .authorized || auth == .limited else {
            let report = NexusMediaImportReport(imported: 0, skipped: 0, failed: 1, bytesCopied: 0, detail: "Photos access was not granted.")
            lastReport = report
            status = report.detail
            return report
        }

        busy = true
        progress = 0
        status = "Reading actual Photos library media…"
        defer { busy = false }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: options)
        let count = min(assets.count, limit ?? assets.count)
        var report = NexusMediaImportReport()

        for index in 0..<count {
            guard hasStorageHeadroom(extraBytes: 0) else {
                report.skipped += count - index
                report.detail = "Stopped before storage became critically low."
                break
            }

            let asset = assets.object(at: index)
            status = "Importing Photos media • \(index + 1)/\(count)"
            progress = Double(index) / Double(max(1, count))

            do {
                if asset.mediaType == .image {
                    let url = try await exportPhotoAsset(asset)
                    defer { cleanupTemporaryMedia(url) }
                    let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                    if size <= maximumSingleMediaBytes && hasStorageHeadroom(extraBytes: size) && !alreadyImported(name: url.lastPathComponent, size: size) {
                        report.imported += try NexusV8FileLibrary.shared.importURLs([url]).count
                        report.bytesCopied += size
                    } else {
                        report.skipped += 1
                    }
                } else if asset.mediaType == .video {
                    let url = try await exportVideoAsset(asset)
                    defer { cleanupTemporaryMedia(url) }
                    let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                    if size <= maximumSingleMediaBytes && hasStorageHeadroom(extraBytes: size) && !alreadyImported(name: url.lastPathComponent, size: size) {
                        report.imported += try NexusV8FileLibrary.shared.importURLs([url]).count
                        report.bytesCopied += size
                    } else {
                        report.skipped += 1
                    }
                } else {
                    report.skipped += 1
                }
            } catch {
                report.failed += 1
            }

            progress = Double(index + 1) / Double(max(1, count))
            await Task.yield()
        }

        lastReport = report
        status = report.summary
        if report.imported > 0 {
            await NexusPreanalysisStore.shared.analyzePending(NexusV8FileLibrary.shared.files)
        }
        return report
    }

    private func scan(_ source: URL) throws -> [NexusMediaCandidate] {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return scanDirectory(source)
        }
        if source.pathExtension.lowercased() == "zip" {
            return try scanZIP(source)
        }
        if NexusMediaTypes.allExtensions.contains(source.pathExtension.lowercased()) {
            let size = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            return [NexusMediaCandidate(name: source.lastPathComponent, size: size, removeAfterImport: false) { source }]
        }
        return []
    }

    private func scanDirectory(_ root: URL) -> [NexusMediaCandidate] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return [] }
        var result: [NexusMediaCandidate] = []
        for case let file as URL in enumerator {
            guard NexusMediaTypes.allExtensions.contains(file.pathExtension.lowercased()) else { continue }
            let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            result.append(NexusMediaCandidate(name: file.lastPathComponent, size: size, removeAfterImport: false) { file })
        }
        return result
    }

    private func scanZIP(_ archiveURL: URL) throws -> [NexusMediaCandidate] {
        let archive = try Archive(url: archiveURL, accessMode: .read)
        var result: [NexusMediaCandidate] = []
        for entry in archive where entry.type == .file {
            let ext = URL(fileURLWithPath: entry.path).pathExtension.lowercased()
            guard NexusMediaTypes.allExtensions.contains(ext) else { continue }
            let name = URL(fileURLWithPath: entry.path).lastPathComponent
            let size = Int64(entry.uncompressedSize)
            let path = entry.path
            result.append(NexusMediaCandidate(name: name, size: size, removeAfterImport: true) {
                let freshArchive = try Archive(url: archiveURL, accessMode: .read)
                guard let freshEntry = freshArchive[path] else { throw NexusMediaError.archiveEntryMissing }
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-media-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let temp = tempDir.appendingPathComponent(name)
                try freshArchive.extract(freshEntry, to: temp, bufferSize: 256 * 1024, skipCRC32: false)
                return temp
            })
        }
        return result
    }

    private func exportPhotoAsset(_ asset: PHAsset) async throws -> URL {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto }) ?? resources.first else {
            throw NexusMediaError.assetUnavailable
        }
        let ext = URL(fileURLWithPath: resource.originalFilename).pathExtension.isEmpty ? "jpg" : URL(fileURLWithPath: resource.originalFilename).pathExtension
        let identifier = asset.localIdentifier.replacingOccurrences(of: "/", with: "_")
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-photos-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let destination = tempDir.appendingPathComponent("Photos-\(identifier).\(ext)")
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: destination) }
            }
        }
    }

    private func exportVideoAsset(_ asset: PHAsset) async throws -> URL {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .video || $0.type == .fullSizeVideo }) ?? resources.first else {
            throw NexusMediaError.assetUnavailable
        }
        let ext = URL(fileURLWithPath: resource.originalFilename).pathExtension.isEmpty ? "mov" : URL(fileURLWithPath: resource.originalFilename).pathExtension
        let identifier = asset.localIdentifier.replacingOccurrences(of: "/", with: "_")
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-photos-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let destination = tempDir.appendingPathComponent("Photos-\(identifier).\(ext)")
        return try await withCheckedThrowingContinuation { continuation in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: destination) }
            }
        }
    }

    private func alreadyImported(name: String, size: Int64) -> Bool {
        NexusV8FileLibrary.shared.files.contains { $0.name == name && $0.size == size }
    }

    private func hasStorageHeadroom(extraBytes: Int64) -> Bool {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let values = try? base.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let free = values?.volumeAvailableCapacityForImportantUsage ?? Int64.max
        let reserve = minimumFreeBytes + max(0, extraBytes)
        return free > reserve
    }

    private func cleanupTemporaryMedia(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        let parent = url.deletingLastPathComponent()
        if parent.path.hasPrefix(FileManager.default.temporaryDirectory.path) {
            try? FileManager.default.removeItem(at: parent)
        }
    }
}

private struct NexusMediaCandidate {
    let name: String
    let size: Int64
    let removeAfterImport: Bool
    let materialize: () throws -> URL
}

private enum NexusMediaError: LocalizedError {
    case archiveEntryMissing
    case assetUnavailable
    var errorDescription: String? {
        switch self {
        case .archiveEntryMissing: return "Media entry disappeared from the archive."
        case .assetUnavailable: return "The media asset could not be exported or decoded."
        }
    }
}

enum NexusVideoFrameExtractor {
    static func contactSheet(for url: URL, maxFrames: Int = 6, maxPixel: CGFloat = 640) async throws -> URL {
        try await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let seconds = max(0.1, CMTimeGetSeconds(duration))
            let frameCount = max(2, min(maxFrames, Int(ceil(seconds / 6.0))))
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.4, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.4, preferredTimescale: 600)

            var images: [UIImage] = []
            images.reserveCapacity(frameCount)
            for index in 0..<frameCount {
                try Task.checkCancellation()
                let ratio = frameCount == 1 ? 0.5 : Double(index) / Double(frameCount - 1)
                let time = CMTime(seconds: seconds * ratio, preferredTimescale: 600)
                autoreleasepool {
                    if let cg = try? generator.copyCGImage(at: time, actualTime: nil) {
                        images.append(UIImage(cgImage: cg))
                    }
                }
            }
            guard !images.isEmpty else { throw NexusMediaError.assetUnavailable }

            let columns = 2
            let rows = Int(ceil(Double(images.count) / Double(columns)))
            let cell = CGSize(width: maxPixel, height: maxPixel * 0.75)
            let sheetSize = CGSize(width: cell.width * CGFloat(columns), height: cell.height * CGFloat(rows))
            let renderer = UIGraphicsImageRenderer(size: sheetSize)
            let sheet = renderer.image { _ in
                UIColor.black.setFill()
                UIRectFill(CGRect(origin: .zero, size: sheetSize))
                for (index, image) in images.enumerated() {
                    let row = index / columns
                    let column = index % columns
                    let rect = CGRect(x: CGFloat(column) * cell.width,
                                      y: CGFloat(row) * cell.height,
                                      width: cell.width,
                                      height: cell.height)
                    let fitted = aspectFit(image.size, in: rect.insetBy(dx: 8, dy: 8))
                    image.draw(in: fitted)
                }
            }
            images.removeAll(keepingCapacity: false)
            guard let data = sheet.jpegData(compressionQuality: 0.76) else { throw NexusMediaError.assetUnavailable }
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-video-frames-\(UUID().uuidString).jpg")
            try data.write(to: output, options: .atomic)
            return output
        }.value
    }

    private static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }
}

struct NexusMediaImportView: View {
    @ObservedObject private var media = NexusMediaIngestionStore.shared
    @ObservedObject private var library = NexusV8FileLibrary.shared
    @State private var picker = false
    @State private var allPhotosConfirmation = false

    var body: some View {
        List {
            Section {
                Text("Import actual photo/video bytes into NEXUS so the Analyzed Library can inspect pixels and representative video frames—not just JSON or metadata. Imports are streamed to disk and stop before storage becomes critically low.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if media.busy {
                    ProgressView(value: media.progress) { Text(media.status).font(.caption) }
                } else {
                    Text(media.status).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Files & export archives") {
                Button { picker = true } label: {
                    Label("Import photos/videos or Meta ZIP/folder", systemImage: "photo.stack.fill")
                }
                Text("For Meta ZIPs, NEXUS streams image/video entries to local storage without loading an entire archive or video into RAM.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Apple Photos") {
                Button { Task { _ = await media.importRecentPhotoLibrary(limit: 100) } } label: {
                    Label("Import most recent 100", systemImage: "photo.on.rectangle.angled")
                }
                Button { Task { _ = await media.importRecentPhotoLibrary(limit: 500) } } label: {
                    Label("Import most recent 500", systemImage: "photo.stack")
                }
                Button { allPhotosConfirmation = true } label: {
                    Label("Import all accessible photos & videos safely", systemImage: "square.stack.3d.down.right.fill")
                }
                Text("‘All’ processes assets sequentially, skips duplicates or oversized media, and stops before free storage becomes critically low.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Local media library") {
                LabeledContent("Photos", value: "\(library.files.filter { NexusMediaTypes.isImage($0.url) }.count)")
                LabeledContent("Videos", value: "\(library.files.filter { NexusMediaTypes.isVideo($0.url) }.count)")
                NavigationLink("Open Analyzed Library") { NexusAnalyzedLibraryView() }
            }
        }
        .navigationTitle("Photo & Video Intelligence")
        .fileImporter(isPresented: $picker, allowedContentTypes: [.image, .movie, .video, .zip, .folder, .data], allowsMultipleSelection: true) { result in
            guard let urls = try? result.get() else { return }
            Task { _ = await media.importMedia(from: urls) }
        }
        .confirmationDialog("Import all accessible Photos media?", isPresented: $allPhotosConfirmation, titleVisibility: .visible) {
            Button("Import all") { Task { _ = await media.importRecentPhotoLibrary(limit: nil) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can consume significant storage. NEXUS imports sequentially and stops before storage becomes critically low.")
        }
    }
}
